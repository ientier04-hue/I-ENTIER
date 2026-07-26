-- =============================================================================
-- i-ENTIER -- schéma SQL global
-- Applications couvertes :
--   1. i-ENTIER Patient
--   2. i-ENTIER Professionnel
--   3. i-ENTIER Administration
--
-- Cible : PostgreSQL 15+
-- Encodage attendu : UTF-8
--
-- Ce schéma consolide les collections du projet Firebase partagé `i-entier`
-- dans un modèle relationnel normalisé. Les identifiants d'utilisateurs restent
-- des VARCHAR(128) afin d'accepter les UUID Supabase Auth sous forme textuelle.
--
-- Correspondance principale Firestore -> SQL :
--   user                                      -> app_users
--   patients                                 -> patient_profiles
--   patients/*/healthMeasurements            -> health_measurements
--   patients/*/cycleEntries                   -> cycle_entries + cycle_entry_symptoms
--   patients/*/mentalHealthEntries            -> mental_health_entries
--                                                 + mental_health_entry_feelings
--   patients/*/laboratoryResults              -> laboratory_results
--                                                 + laboratory_result_items
--   patients/*/preventiveCareRecords          -> preventive_care_records
--   patients/*/preventiveCareReminders        -> preventive_care_reminders
--   patients/*/notifications                  -> notifications
--   patients/*/prescriptions                  -> prescriptions + prescription_items
--   providerProfiles                         -> provider_profiles
--   personnelMedical                         -> v_public_professionals
--   institution                              -> v_public_institutions
--   appointments                             -> appointments
--   administrators                           -> administrators
--   providerReviews                          -> provider_reviews
--
-- Notes d'exploitation :
--   * Exécuter ce fichier sur une base neuve.
--   * Les rôles techniques propriétaires de la base contournent normalement
--     la RLS PostgreSQL. Les clients applicatifs ne doivent jamais utiliser le
--     rôle propriétaire.
--   * Pour une connexion applicative, le backend doit définir l'acteur :
--       SET LOCAL ientier.current_user_id = '<firebase-uid>';
--     Dans Supabase, remplacer current_actor_id() par auth.uid()::text est une
--     adaptation naturelle.
--   * Les écritures d'administration et les réponses aux rendez-vous doivent
--     utiliser review_provider(...) et respond_to_appointment(...), afin que
--     la décision et son audit/sa notification restent atomiques.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS ientier;
SET search_path TO ientier, public;

-- =============================================================================
-- 1. Types de référence
-- =============================================================================

CREATE TYPE admin_role AS ENUM (
  'reviewer',
  'administrator',
  'super_admin'
);

CREATE TYPE provider_account_type AS ENUM (
  'professional',
  'institution'
);

CREATE TYPE verification_status AS ENUM (
  'pending',
  'approved',
  'rejected'
);

CREATE TYPE appointment_mode AS ENUM (
  'inPerson',
  'homeVisit',
  'video'
);

CREATE TYPE appointment_status AS ENUM (
  'pending',
  'confirmed',
  'cancelled'
);

CREATE TYPE health_metric_kind AS ENUM (
  'bloodPressure',
  'bloodGlucose',
  'weight',
  'temperature',
  'oxygen'
);

CREATE TYPE patient_medical_item_type AS ENUM (
  'condition',
  'allergy',
  'medication',
  'surgery'
);

CREATE TYPE cycle_flow AS ENUM (
  'light',
  'medium',
  'heavy'
);

CREATE TYPE cycle_mood AS ENUM (
  'great',
  'calm',
  'sensitive',
  'irritable',
  'sad'
);

CREATE TYPE cycle_symptom AS ENUM (
  'cramps',
  'headache',
  'fatigue',
  'bloating',
  'backache',
  'tenderBreasts',
  'nausea',
  'acne'
);

CREATE TYPE mental_health_mood AS ENUM (
  'veryLow',
  'low',
  'neutral',
  'good',
  'veryGood'
);

CREATE TYPE mental_health_feeling AS ENUM (
  'anxious',
  'sad',
  'stressed',
  'tired',
  'lonely',
  'angry',
  'calm',
  'hopeful'
);

CREATE TYPE preventive_care_category AS ENUM (
  'checkup',
  'vaccine',
  'screening',
  'dental',
  'vision',
  'habit'
);

CREATE TYPE notification_type AS ENUM (
  'appointment',
  'result',
  'reminder',
  'security'
);

CREATE TYPE notification_source AS ENUM (
  'app',
  'preventiveReminder',
  'preventiveRecord',
  'laboratoryResult',
  'prescription',
  'appointment',
  'security'
);

CREATE TYPE prescription_source AS ENUM (
  'scan',
  'doctor'
);

CREATE TYPE prescription_status AS ENUM (
  'available',
  'expired',
  'revoked',
  'dispensed'
);

CREATE TYPE laboratory_result_status AS ENUM (
  'pending',
  'processing',
  'available',
  'cancelled'
);

CREATE TYPE laboratory_abnormal_flag AS ENUM (
  'normal',
  'low',
  'high',
  'critical',
  'unknown'
);

-- =============================================================================
-- 2. Identité, comptes et rôles
-- =============================================================================

CREATE TABLE app_users (
  user_id               VARCHAR(128) PRIMARY KEY,
  email                 CITEXT,
  display_name          VARCHAR(140) NOT NULL DEFAULT '',
  photo_url             TEXT,
  auth_provider         VARCHAR(64) NOT NULL DEFAULT 'google.com',
  phone                 VARCHAR(40),
  email_verified        BOOLEAN NOT NULL DEFAULT FALSE,
  disabled_at           TIMESTAMPTZ,
  last_sign_in_at       TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_app_users_email UNIQUE (email),
  CONSTRAINT ck_app_users_uid_not_blank
    CHECK (length(btrim(user_id)) BETWEEN 1 AND 128),
  CONSTRAINT ck_app_users_display_name_length
    CHECK (length(display_name) <= 140),
  CONSTRAINT ck_app_users_email_length
    CHECK (email IS NULL OR length(email::TEXT) BETWEEN 3 AND 254),
  CONSTRAINT ck_app_users_phone_length
    CHECK (phone IS NULL OR length(phone) <= 40)
);

COMMENT ON TABLE app_users IS
  'Identités partagées par les trois applications; user_id est fourni par le système d''authentification.';

CREATE TABLE administrators (
  user_id               VARCHAR(128) PRIMARY KEY
                        REFERENCES app_users(user_id) ON DELETE RESTRICT,
  role                  admin_role NOT NULL DEFAULT 'reviewer',
  active                BOOLEAN NOT NULL DEFAULT TRUE,
  provisioned_by        VARCHAR(128)
                        REFERENCES administrators(user_id) ON DELETE SET NULL,
  notes                 VARCHAR(500) NOT NULL DEFAULT '',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_administrators_notes_length
    CHECK (length(notes) <= 500)
);

COMMENT ON TABLE administrators IS
  'Rôles provisionnés par un backend ou un super-administrateur, jamais auto-attribués par un client.';

-- =============================================================================
-- 3. Dossier patient
-- =============================================================================

CREATE TABLE patient_profiles (
  patient_id            VARCHAR(128) PRIMARY KEY
                        REFERENCES app_users(user_id) ON DELETE RESTRICT,
  sex                   VARCHAR(40),
  birth_date            DATE,
  weight_kg             NUMERIC(6,2),
  height_cm             NUMERIC(6,2),
  phone                 VARCHAR(40) NOT NULL DEFAULT '',
  address               VARCHAR(300) NOT NULL DEFAULT '',
  blood_type            VARCHAR(24) NOT NULL DEFAULT '',
  special_needs         VARCHAR(500) NOT NULL DEFAULT '',
  pregnancy_status      VARCHAR(80) NOT NULL DEFAULT '',
  primary_doctor        VARCHAR(140) NOT NULL DEFAULT '',
  insurance             VARCHAR(180) NOT NULL DEFAULT '',
  profile_complete      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_patient_birth_date
    CHECK (birth_date IS NULL OR birth_date >= DATE '1900-01-01'),
  CONSTRAINT ck_patient_weight
    CHECK (weight_kg IS NULL OR weight_kg BETWEEN 1 AND 500),
  CONSTRAINT ck_patient_height
    CHECK (height_cm IS NULL OR height_cm BETWEEN 30 AND 300),
  CONSTRAINT ck_patient_phone_length
    CHECK (length(phone) <= 40),
  CONSTRAINT ck_patient_address_length
    CHECK (length(address) <= 300),
  CONSTRAINT ck_patient_special_needs_length
    CHECK (length(special_needs) <= 500),
  CONSTRAINT ck_patient_primary_doctor_length
    CHECK (length(primary_doctor) <= 140),
  CONSTRAINT ck_patient_insurance_length
    CHECK (length(insurance) <= 180)
);

CREATE TABLE patient_emergency_contacts (
  patient_id            VARCHAR(128) PRIMARY KEY
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  contact_name          VARCHAR(140) NOT NULL DEFAULT '',
  relationship          VARCHAR(80) NOT NULL DEFAULT '',
  phone                 VARCHAR(40) NOT NULL DEFAULT '',
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_emergency_contact_name_length
    CHECK (length(contact_name) <= 140),
  CONSTRAINT ck_emergency_relationship_length
    CHECK (length(relationship) <= 80),
  CONSTRAINT ck_emergency_phone_length
    CHECK (length(phone) <= 40)
);

CREATE TABLE patient_medical_items (
  item_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id            VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  item_type             patient_medical_item_type NOT NULL,
  label                 VARCHAR(180) NOT NULL,
  details               VARCHAR(500) NOT NULL DEFAULT '',
  active                BOOLEAN NOT NULL DEFAULT TRUE,
  started_on            DATE,
  ended_on              DATE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_patient_medical_item_label
    CHECK (length(btrim(label)) BETWEEN 1 AND 180),
  CONSTRAINT ck_patient_medical_item_details
    CHECK (length(details) <= 500),
  CONSTRAINT ck_patient_medical_item_dates
    CHECK (ended_on IS NULL OR started_on IS NULL OR ended_on >= started_on)
);

CREATE UNIQUE INDEX uq_patient_medical_item
  ON patient_medical_items (patient_id, item_type, lower(label));

CREATE INDEX ix_patient_medical_items_lookup
  ON patient_medical_items (patient_id, item_type, active);

-- =============================================================================
-- 4. Dossiers professionnels, institutions, services et disponibilités
-- =============================================================================

CREATE TABLE provider_profiles (
  provider_id                  VARCHAR(128) PRIMARY KEY
                               REFERENCES app_users(user_id) ON DELETE RESTRICT,
  account_type                 provider_account_type NOT NULL,
  display_name                 VARCHAR(140) NOT NULL,
  category                     VARCHAR(120) NOT NULL,
  registration_number          VARCHAR(120) NOT NULL,
  contact_person               VARCHAR(140) NOT NULL DEFAULT '',
  workplace                    VARCHAR(160) NOT NULL DEFAULT '',
  linked_institution_id        VARCHAR(128),
  linked_institution_name_snapshot VARCHAR(160) NOT NULL DEFAULT '',
  phone                        VARCHAR(40) NOT NULL,
  email                        CITEXT NOT NULL,
  address                      VARCHAR(300) NOT NULL,
  description                  VARCHAR(1500) NOT NULL,
  experience                   VARCHAR(300) NOT NULL DEFAULT '',
  qualifications               VARCHAR(800) NOT NULL DEFAULT '',
  services_summary             VARCHAR(1200) NOT NULL,
  schedule_summary             VARCHAR(500) NOT NULL,
  institution_prices_published BOOLEAN NOT NULL DEFAULT FALSE,
  service_prices_summary       VARCHAR(1200) NOT NULL DEFAULT '',
  room_prices_summary          VARCHAR(1200) NOT NULL DEFAULT '',
  legacy_availability_config   JSONB NOT NULL DEFAULT '{}'::JSONB,
  available                    BOOLEAN NOT NULL DEFAULT TRUE,
  is_visible                   BOOLEAN NOT NULL DEFAULT FALSE,
  verification_status          verification_status NOT NULL DEFAULT 'pending',
  rejection_reason             VARCHAR(600) NOT NULL DEFAULT '',
  terms_accepted               BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_provider_linked_institution
    FOREIGN KEY (linked_institution_id)
    REFERENCES provider_profiles(provider_id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT ck_provider_display_name
    CHECK (length(btrim(display_name)) BETWEEN 2 AND 140),
  CONSTRAINT ck_provider_category
    CHECK (length(btrim(category)) BETWEEN 2 AND 120),
  CONSTRAINT ck_provider_registration_number
    CHECK (length(btrim(registration_number)) BETWEEN 2 AND 120),
  CONSTRAINT ck_provider_contact_person
    CHECK (length(contact_person) <= 140),
  CONSTRAINT ck_provider_workplace
    CHECK (length(workplace) <= 160),
  CONSTRAINT ck_provider_linked_name
    CHECK (length(linked_institution_name_snapshot) <= 160),
  CONSTRAINT ck_provider_phone
    CHECK (length(btrim(phone)) BETWEEN 5 AND 40),
  CONSTRAINT ck_provider_email
    CHECK (length(btrim(email::TEXT)) BETWEEN 5 AND 180),
  CONSTRAINT ck_provider_address
    CHECK (length(btrim(address)) BETWEEN 4 AND 300),
  CONSTRAINT ck_provider_description
    CHECK (length(btrim(description)) BETWEEN 4 AND 1500),
  CONSTRAINT ck_provider_experience
    CHECK (length(experience) <= 300),
  CONSTRAINT ck_provider_qualifications
    CHECK (length(qualifications) <= 800),
  CONSTRAINT ck_provider_services_summary
    CHECK (length(btrim(services_summary)) BETWEEN 2 AND 1200),
  CONSTRAINT ck_provider_schedule_summary
    CHECK (length(btrim(schedule_summary)) BETWEEN 2 AND 500),
  CONSTRAINT ck_provider_price_summaries
    CHECK (
      length(service_prices_summary) <= 1200
      AND length(room_prices_summary) <= 1200
    ),
  CONSTRAINT ck_provider_legacy_availability_object
    CHECK (jsonb_typeof(legacy_availability_config) = 'object'),
  CONSTRAINT ck_provider_visibility
    CHECK (NOT is_visible OR verification_status = 'approved'),
  CONSTRAINT ck_provider_rejection_reason
    CHECK (
      (verification_status = 'rejected' AND length(btrim(rejection_reason)) BETWEEN 1 AND 600)
      OR
      (verification_status <> 'rejected' AND rejection_reason = '')
    ),
  CONSTRAINT ck_provider_terms
    CHECK (terms_accepted),
  CONSTRAINT ck_provider_account_specific_fields
    CHECK (
      (
        account_type = 'professional'
        AND institution_prices_published = FALSE
        AND service_prices_summary = ''
        AND room_prices_summary = ''
      )
      OR
      (
        account_type = 'institution'
        AND linked_institution_id IS NULL
        AND linked_institution_name_snapshot = ''
      )
    )
);

CREATE INDEX ix_provider_profiles_review_queue
  ON provider_profiles (verification_status, updated_at DESC);

CREATE INDEX ix_provider_profiles_public_directory
  ON provider_profiles (account_type, category, display_name)
  WHERE verification_status = 'approved' AND is_visible = TRUE;

CREATE INDEX ix_provider_profiles_linked_institution
  ON provider_profiles (linked_institution_id)
  WHERE linked_institution_id IS NOT NULL;

CREATE TABLE institution_capabilities (
  provider_id            VARCHAR(128) PRIMARY KEY
                         REFERENCES provider_profiles(provider_id) ON DELETE CASCADE,
  latitude               NUMERIC(9,6),
  longitude              NUMERIC(9,6),
  home_sampling          BOOLEAN NOT NULL DEFAULT FALSE,
  online_results         BOOLEAN NOT NULL DEFAULT FALSE,
  accredited             BOOLEAN NOT NULL DEFAULT FALSE,
  has_emergency_service  BOOLEAN NOT NULL DEFAULT FALSE,
  metadata               JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_institution_latitude
    CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  CONSTRAINT ck_institution_longitude
    CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  CONSTRAINT ck_institution_metadata_object
    CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE TABLE provider_services (
  service_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id            VARCHAR(128) NOT NULL
                         REFERENCES provider_profiles(provider_id) ON DELETE CASCADE,
  name                   VARCHAR(160) NOT NULL,
  description            VARCHAR(1000) NOT NULL DEFAULT '',
  price_amount           NUMERIC(12,2),
  currency_code          CHAR(3) NOT NULL DEFAULT 'HTG',
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order             SMALLINT NOT NULL DEFAULT 0,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_provider_service_name
    CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  CONSTRAINT ck_provider_service_description
    CHECK (length(description) <= 1000),
  CONSTRAINT ck_provider_service_price
    CHECK (price_amount IS NULL OR price_amount >= 0),
  CONSTRAINT ck_provider_service_currency
    CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE UNIQUE INDEX uq_provider_service_name
  ON provider_services (provider_id, lower(name));

CREATE INDEX ix_provider_services_active
  ON provider_services (provider_id, active, sort_order);

CREATE TABLE provider_appointment_modes (
  provider_id            VARCHAR(128) NOT NULL
                         REFERENCES provider_profiles(provider_id) ON DELETE CASCADE,
  mode                   appointment_mode NOT NULL,
  enabled                BOOLEAN NOT NULL DEFAULT FALSE,
  schedule_label         VARCHAR(500) NOT NULL DEFAULT '',
  default_price_label    VARCHAR(80) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (provider_id, mode),
  CONSTRAINT ck_provider_mode_schedule
    CHECK (length(schedule_label) <= 500),
  CONSTRAINT ck_provider_mode_default_price
    CHECK (length(default_price_label) <= 80)
);

CREATE TABLE provider_service_modes (
  service_id             UUID NOT NULL
                         REFERENCES provider_services(service_id) ON DELETE CASCADE,
  mode                   appointment_mode NOT NULL,

  PRIMARY KEY (service_id, mode)
);

CREATE TABLE provider_availability (
  availability_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id            VARCHAR(128) NOT NULL,
  mode                   appointment_mode NOT NULL,
  weekday                SMALLINT NOT NULL,
  opening_time           TIME NOT NULL,
  closing_time           TIME NOT NULL,
  valid_from             DATE,
  valid_until            DATE,
  slot_duration_minutes  SMALLINT NOT NULL DEFAULT 30,
  timezone_name          VARCHAR(64) NOT NULL DEFAULT 'America/Port-au-Prince',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_provider_availability_mode
    FOREIGN KEY (provider_id, mode)
    REFERENCES provider_appointment_modes(provider_id, mode)
    ON DELETE CASCADE,
  CONSTRAINT ck_provider_availability_weekday
    CHECK (weekday BETWEEN 1 AND 7),
  CONSTRAINT ck_provider_availability_hours
    CHECK (closing_time > opening_time),
  CONSTRAINT ck_provider_availability_period
    CHECK (
      (valid_from IS NULL AND valid_until IS NULL)
      OR
      (valid_from IS NOT NULL AND valid_until IS NOT NULL AND valid_until >= valid_from)
    ),
  CONSTRAINT ck_provider_slot_duration
    CHECK (slot_duration_minutes BETWEEN 5 AND 480)
);

CREATE UNIQUE INDEX uq_provider_availability_slot
  ON provider_availability (
    provider_id,
    mode,
    weekday,
    opening_time,
    closing_time,
    COALESCE(valid_from, DATE '-infinity'),
    COALESCE(valid_until, DATE 'infinity')
  );

CREATE INDEX ix_provider_availability_lookup
  ON provider_availability (provider_id, mode, weekday, valid_from, valid_until);

CREATE TABLE provider_reviews (
  review_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firestore_id           VARCHAR(160) UNIQUE,
  provider_id            VARCHAR(128) NOT NULL
                         REFERENCES provider_profiles(provider_id) ON DELETE RESTRICT,
  admin_id               VARCHAR(128) NOT NULL
                         REFERENCES administrators(user_id) ON DELETE RESTRICT,
  previous_status        verification_status NOT NULL,
  new_status             verification_status NOT NULL,
  reason                 VARCHAR(600) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_provider_review_transition
    CHECK (
      previous_status <> new_status
      AND new_status IN ('approved', 'rejected')
    ),
  CONSTRAINT ck_provider_review_reason
    CHECK (
      (new_status = 'rejected' AND length(btrim(reason)) BETWEEN 1 AND 600)
      OR
      (new_status = 'approved' AND reason = '')
    )
);

CREATE INDEX ix_provider_reviews_provider
  ON provider_reviews (provider_id, created_at DESC);

CREATE INDEX ix_provider_reviews_admin
  ON provider_reviews (admin_id, created_at DESC);

-- =============================================================================
-- 5. Rendez-vous partagés Patient <-> Professionnel
-- =============================================================================

CREATE TABLE appointments (
  appointment_id         VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE RESTRICT,
  patient_name_snapshot  VARCHAR(140) NOT NULL,
  provider_id            VARCHAR(128) NOT NULL
                         REFERENCES provider_profiles(provider_id) ON DELETE RESTRICT,
  provider_type_snapshot provider_account_type NOT NULL,
  provider_name_snapshot VARCHAR(160) NOT NULL,
  service_id             UUID
                         REFERENCES provider_services(service_id) ON DELETE SET NULL,
  service_name_snapshot  VARCHAR(160) NOT NULL DEFAULT '',
  mode                   appointment_mode NOT NULL DEFAULT 'inPerson',
  location               VARCHAR(300) NOT NULL DEFAULT '',
  scheduled_at           TIMESTAMPTZ NOT NULL,
  schedule_label         VARCHAR(500) NOT NULL,
  status                 appointment_status NOT NULL DEFAULT 'pending',
  patient_note           VARCHAR(500) NOT NULL DEFAULT '',
  response_note          VARCHAR(500) NOT NULL DEFAULT '',
  responded_at           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_appointments_id_patient UNIQUE (appointment_id, patient_id),
  CONSTRAINT uq_appointments_patient_provider_slot
    UNIQUE (patient_id, provider_id, scheduled_at),
  CONSTRAINT ck_appointment_id
    CHECK (length(btrim(appointment_id)) BETWEEN 1 AND 160),
  CONSTRAINT ck_appointment_patient_name
    CHECK (length(btrim(patient_name_snapshot)) BETWEEN 1 AND 140),
  CONSTRAINT ck_appointment_provider_name
    CHECK (length(btrim(provider_name_snapshot)) BETWEEN 1 AND 160),
  CONSTRAINT ck_appointment_service
    CHECK (length(service_name_snapshot) <= 160),
  CONSTRAINT ck_appointment_location
    CHECK (
      length(location) <= 300
      AND (mode <> 'homeVisit' OR length(btrim(location)) > 3)
    ),
  CONSTRAINT ck_appointment_schedule_label
    CHECK (length(btrim(schedule_label)) BETWEEN 1 AND 500),
  CONSTRAINT ck_appointment_notes
    CHECK (
      length(patient_note) <= 500
      AND length(response_note) <= 500
    ),
  CONSTRAINT ck_appointment_schedule_window
    CHECK (
      scheduled_at > created_at + INTERVAL '30 minutes'
      AND scheduled_at < created_at + INTERVAL '366 days'
    ),
  CONSTRAINT ck_appointment_response_state
    CHECK (
      (
        status = 'pending'
        AND responded_at IS NULL
        AND response_note = ''
      )
      OR
      (
        status IN ('confirmed', 'cancelled')
        AND responded_at IS NOT NULL
      )
    )
);

CREATE INDEX ix_appointments_patient
  ON appointments (patient_id, scheduled_at DESC);

CREATE INDEX ix_appointments_provider
  ON appointments (provider_id, scheduled_at, status);

CREATE INDEX ix_appointments_pending_provider
  ON appointments (provider_id, scheduled_at)
  WHERE status = 'pending';

CREATE TABLE appointment_status_history (
  history_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  appointment_id         VARCHAR(160) NOT NULL
                         REFERENCES appointments(appointment_id) ON DELETE RESTRICT,
  previous_status        appointment_status NOT NULL,
  new_status             appointment_status NOT NULL,
  changed_by             VARCHAR(128) NOT NULL
                         REFERENCES app_users(user_id) ON DELETE RESTRICT,
  note                   VARCHAR(500) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_appointment_history_change
    CHECK (previous_status <> new_status),
  CONSTRAINT ck_appointment_history_note
    CHECK (length(note) <= 500)
);

CREATE INDEX ix_appointment_history
  ON appointment_status_history (appointment_id, created_at);

-- =============================================================================
-- 6. Suivi médical privé du patient
-- =============================================================================

CREATE TABLE health_measurements (
  measurement_id         VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  kind                   health_metric_kind NOT NULL,
  value                  NUMERIC(10,3) NOT NULL,
  secondary_value        NUMERIC(10,3),
  pulse_bpm              NUMERIC(6,2),
  unit                   VARCHAR(20) NOT NULL,
  context                VARCHAR(120) NOT NULL DEFAULT '',
  note                   VARCHAR(300) NOT NULL DEFAULT '',
  measured_at            TIMESTAMPTZ NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_health_measurement_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT ck_health_measurement_note
    CHECK (length(note) <= 300),
  CONSTRAINT ck_health_measurement_context
    CHECK (length(context) <= 120),
  CONSTRAINT ck_health_measurement_pulse
    CHECK (pulse_bpm IS NULL OR pulse_bpm BETWEEN 20 AND 250),
  CONSTRAINT ck_health_measurement_date
    CHECK (measured_at <= created_at),
  CONSTRAINT ck_health_measurement_values
    CHECK (
      (
        kind = 'bloodPressure'
        AND value BETWEEN 40 AND 300
        AND secondary_value IS NOT NULL
        AND secondary_value BETWEEN 20 AND 200
      )
      OR
      (
        kind = 'bloodGlucose'
        AND value BETWEEN 10 AND 1000
        AND secondary_value IS NULL
      )
      OR
      (
        kind = 'weight'
        AND value BETWEEN 1 AND 500
        AND secondary_value IS NULL
      )
      OR
      (
        kind = 'temperature'
        AND value BETWEEN 25 AND 45
        AND secondary_value IS NULL
      )
      OR
      (
        kind = 'oxygen'
        AND value BETWEEN 50 AND 100
        AND secondary_value IS NULL
      )
    )
);

CREATE INDEX ix_health_measurements_patient_metric
  ON health_measurements (patient_id, kind, measured_at DESC);

CREATE TABLE cycle_entries (
  cycle_entry_id         VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  entry_date             DATE NOT NULL,
  is_period              BOOLEAN NOT NULL DEFAULT FALSE,
  flow                   cycle_flow,
  mood                   cycle_mood,
  note                   VARCHAR(500) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_cycle_entry_day UNIQUE (patient_id, entry_date),
  CONSTRAINT uq_cycle_entry_firestore UNIQUE (patient_id, firestore_id),
  CONSTRAINT ck_cycle_entry_flow
    CHECK (is_period OR flow IS NULL),
  CONSTRAINT ck_cycle_entry_note
    CHECK (length(note) <= 500)
);

CREATE INDEX ix_cycle_entries_patient_date
  ON cycle_entries (patient_id, entry_date DESC);

CREATE TABLE cycle_entry_symptoms (
  cycle_entry_id         VARCHAR(160) NOT NULL
                         REFERENCES cycle_entries(cycle_entry_id) ON DELETE CASCADE,
  symptom                cycle_symptom NOT NULL,

  PRIMARY KEY (cycle_entry_id, symptom)
);

CREATE TABLE mental_health_entries (
  mental_health_entry_id VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  mood                   mental_health_mood NOT NULL,
  mood_score             SMALLINT NOT NULL,
  note                   VARCHAR(500) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_mental_health_entry_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT ck_mental_health_mood_score
    CHECK (
      mood_score = CASE mood
        WHEN 'veryLow' THEN 1
        WHEN 'low' THEN 2
        WHEN 'neutral' THEN 3
        WHEN 'good' THEN 4
        WHEN 'veryGood' THEN 5
      END
    ),
  CONSTRAINT ck_mental_health_note
    CHECK (length(note) <= 500)
);

CREATE INDEX ix_mental_health_entries_patient
  ON mental_health_entries (patient_id, created_at DESC);

CREATE TABLE mental_health_entry_feelings (
  mental_health_entry_id VARCHAR(160) NOT NULL
                         REFERENCES mental_health_entries(mental_health_entry_id)
                         ON DELETE CASCADE,
  feeling                mental_health_feeling NOT NULL,

  PRIMARY KEY (mental_health_entry_id, feeling)
);

-- =============================================================================
-- 7. Laboratoires et résultats
-- =============================================================================

CREATE TABLE laboratory_exam_catalog (
  exam_id                VARCHAR(80) PRIMARY KEY,
  name                   VARCHAR(160) NOT NULL,
  category               VARCHAR(80) NOT NULL,
  description            VARCHAR(1000) NOT NULL DEFAULT '',
  sample_type            VARCHAR(120) NOT NULL DEFAULT '',
  preparation            VARCHAR(1000) NOT NULL DEFAULT '',
  turnaround             VARCHAR(120) NOT NULL DEFAULT '',
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_laboratory_exam_id
    CHECK (length(btrim(exam_id)) BETWEEN 1 AND 80),
  CONSTRAINT ck_laboratory_exam_name
    CHECK (length(btrim(name)) BETWEEN 1 AND 160)
);

CREATE TABLE laboratory_results (
  laboratory_result_id   VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  laboratory_id          VARCHAR(128)
                         REFERENCES provider_profiles(provider_id) ON DELETE SET NULL,
  exam_id                VARCHAR(80)
                         REFERENCES laboratory_exam_catalog(exam_id) ON DELETE SET NULL,
  exam_name_snapshot     VARCHAR(160) NOT NULL,
  laboratory_name_snapshot VARCHAR(160) NOT NULL DEFAULT '',
  status                 laboratory_result_status NOT NULL DEFAULT 'pending',
  summary                VARCHAR(1000) NOT NULL DEFAULT '',
  reference_range        VARCHAR(500) NOT NULL DEFAULT '',
  note                   VARCHAR(1500) NOT NULL DEFAULT '',
  file_url               TEXT NOT NULL DEFAULT '',
  collected_at           TIMESTAMPTZ,
  published_at           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_laboratory_result_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT uq_laboratory_result_id_patient
    UNIQUE (laboratory_result_id, patient_id),
  CONSTRAINT ck_laboratory_result_exam_name
    CHECK (length(btrim(exam_name_snapshot)) BETWEEN 1 AND 160),
  CONSTRAINT ck_laboratory_result_lab_name
    CHECK (length(laboratory_name_snapshot) <= 160),
  CONSTRAINT ck_laboratory_result_dates
    CHECK (
      published_at IS NULL
      OR collected_at IS NULL
      OR published_at >= collected_at
    ),
  CONSTRAINT ck_laboratory_result_published
    CHECK (status <> 'available' OR published_at IS NOT NULL)
);

CREATE INDEX ix_laboratory_results_patient
  ON laboratory_results (patient_id, status, COALESCE(published_at, collected_at) DESC);

CREATE INDEX ix_laboratory_results_laboratory
  ON laboratory_results (laboratory_id, created_at DESC)
  WHERE laboratory_id IS NOT NULL;

CREATE TABLE laboratory_result_items (
  result_item_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  laboratory_result_id   VARCHAR(160) NOT NULL
                         REFERENCES laboratory_results(laboratory_result_id)
                         ON DELETE CASCADE,
  analyte_name           VARCHAR(160) NOT NULL,
  numeric_value          NUMERIC(18,6),
  text_value             VARCHAR(500),
  unit                   VARCHAR(40) NOT NULL DEFAULT '',
  reference_min          NUMERIC(18,6),
  reference_max          NUMERIC(18,6),
  reference_text         VARCHAR(300) NOT NULL DEFAULT '',
  abnormal_flag          laboratory_abnormal_flag NOT NULL DEFAULT 'unknown',
  sort_order             SMALLINT NOT NULL DEFAULT 0,

  CONSTRAINT ck_laboratory_result_item_name
    CHECK (length(btrim(analyte_name)) BETWEEN 1 AND 160),
  CONSTRAINT ck_laboratory_result_item_value
    CHECK (
      numeric_value IS NOT NULL
      OR (text_value IS NOT NULL AND length(btrim(text_value)) > 0)
    ),
  CONSTRAINT ck_laboratory_result_reference
    CHECK (
      reference_min IS NULL
      OR reference_max IS NULL
      OR reference_max >= reference_min
    )
);

CREATE INDEX ix_laboratory_result_items_result
  ON laboratory_result_items (laboratory_result_id, sort_order);

-- =============================================================================
-- 8. Prévention
-- =============================================================================

CREATE TABLE preventive_care_records (
  preventive_record_id   VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  category               preventive_care_category NOT NULL,
  title                  VARCHAR(120) NOT NULL,
  plan_item_id           VARCHAR(80) NOT NULL DEFAULT '',
  completed_at           TIMESTAMPTZ NOT NULL,
  next_due_at            TIMESTAMPTZ,
  provider_name          VARCHAR(120) NOT NULL DEFAULT '',
  note                   VARCHAR(500) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_preventive_record_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT uq_preventive_record_id_patient
    UNIQUE (preventive_record_id, patient_id),
  CONSTRAINT ck_preventive_record_title
    CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  CONSTRAINT ck_preventive_record_plan_item
    CHECK (length(plan_item_id) <= 80),
  CONSTRAINT ck_preventive_record_completed
    CHECK (completed_at <= created_at),
  CONSTRAINT ck_preventive_record_next_due
    CHECK (next_due_at IS NULL OR next_due_at > completed_at),
  CONSTRAINT ck_preventive_record_provider
    CHECK (length(provider_name) <= 120),
  CONSTRAINT ck_preventive_record_note
    CHECK (length(note) <= 500)
);

CREATE INDEX ix_preventive_records_patient
  ON preventive_care_records (patient_id, completed_at DESC);

CREATE INDEX ix_preventive_records_due
  ON preventive_care_records (patient_id, next_due_at)
  WHERE next_due_at IS NOT NULL;

CREATE TABLE preventive_care_reminders (
  preventive_reminder_id VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  category               preventive_care_category NOT NULL,
  title                  VARCHAR(120) NOT NULL,
  plan_item_id           VARCHAR(80) NOT NULL DEFAULT '',
  due_at                 TIMESTAMPTZ NOT NULL,
  note                   VARCHAR(300) NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_preventive_reminder_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT uq_preventive_reminder_id_patient
    UNIQUE (preventive_reminder_id, patient_id),
  CONSTRAINT ck_preventive_reminder_title
    CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  CONSTRAINT ck_preventive_reminder_plan_item
    CHECK (length(plan_item_id) <= 80),
  CONSTRAINT ck_preventive_reminder_note
    CHECK (length(note) <= 300)
);

CREATE INDEX ix_preventive_reminders_due
  ON preventive_care_reminders (patient_id, due_at);

-- =============================================================================
-- 9. Ordonnances
-- =============================================================================

CREATE TABLE prescriptions (
  prescription_id        VARCHAR(160) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(160),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  source                 prescription_source NOT NULL,
  status                 prescription_status NOT NULL DEFAULT 'available',
  doctor_id              VARCHAR(128)
                         REFERENCES provider_profiles(provider_id) ON DELETE SET NULL,
  doctor_name_snapshot   VARCHAR(140) NOT NULL DEFAULT '',
  file_name              VARCHAR(250) NOT NULL DEFAULT '',
  storage_path           TEXT NOT NULL DEFAULT '',
  mime_type              VARCHAR(120),
  file_size_bytes        BIGINT,
  issued_at              TIMESTAMPTZ,
  expires_at             TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_prescription_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT uq_prescription_id_patient
    UNIQUE (prescription_id, patient_id),
  CONSTRAINT ck_prescription_file_name
    CHECK (length(file_name) <= 250),
  CONSTRAINT ck_prescription_file_size
    CHECK (file_size_bytes IS NULL OR file_size_bytes BETWEEN 1 AND 10485760),
  CONSTRAINT ck_prescription_dates
    CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at > issued_at),
  CONSTRAINT ck_prescription_source_payload
    CHECK (
      (
        source = 'scan'
        AND length(btrim(storage_path)) > 0
        AND position('/' IN storage_path) > 0
      )
      OR
      (
        source = 'doctor'
        AND (doctor_id IS NOT NULL OR length(btrim(doctor_name_snapshot)) > 0)
      )
    )
);

CREATE INDEX ix_prescriptions_patient
  ON prescriptions (patient_id, created_at DESC);

CREATE INDEX ix_prescriptions_doctor
  ON prescriptions (doctor_id, created_at DESC)
  WHERE doctor_id IS NOT NULL;

CREATE TABLE prescription_items (
  prescription_item_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prescription_id        VARCHAR(160) NOT NULL
                         REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
  medication_name        VARCHAR(180) NOT NULL,
  active_ingredient      VARCHAR(180) NOT NULL DEFAULT '',
  dosage                 VARCHAR(120) NOT NULL DEFAULT '',
  pharmaceutical_form    VARCHAR(80) NOT NULL DEFAULT '',
  administration_route   VARCHAR(80) NOT NULL DEFAULT '',
  frequency              VARCHAR(120) NOT NULL DEFAULT '',
  duration_days          INTEGER,
  quantity               NUMERIC(12,3),
  instructions           VARCHAR(500) NOT NULL DEFAULT '',
  sort_order             SMALLINT NOT NULL DEFAULT 0,

  CONSTRAINT ck_prescription_item_name
    CHECK (length(btrim(medication_name)) BETWEEN 1 AND 180),
  CONSTRAINT ck_prescription_item_duration
    CHECK (duration_days IS NULL OR duration_days > 0),
  CONSTRAINT ck_prescription_item_quantity
    CHECK (quantity IS NULL OR quantity > 0),
  CONSTRAINT ck_prescription_item_instructions
    CHECK (length(instructions) <= 500)
);

CREATE INDEX ix_prescription_items
  ON prescription_items (prescription_id, sort_order);

-- =============================================================================
-- 10. Notifications et relations vers leur source
-- =============================================================================

CREATE TABLE notifications (
  notification_id        VARCHAR(180) PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  firestore_id           VARCHAR(180),
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  title                  VARCHAR(120) NOT NULL,
  message                VARCHAR(300) NOT NULL,
  type                   notification_type NOT NULL,
  is_read                BOOLEAN NOT NULL DEFAULT FALSE,
  scheduled_at           TIMESTAMPTZ,
  action_label           VARCHAR(80),
  source                 notification_source NOT NULL DEFAULT 'app',
  source_id              VARCHAR(180) NOT NULL DEFAULT '',
  appointment_id         VARCHAR(160),
  preventive_record_id   VARCHAR(160),
  preventive_reminder_id VARCHAR(160),
  laboratory_result_id   VARCHAR(160),
  prescription_id        VARCHAR(160),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_notification_firestore
    UNIQUE (patient_id, firestore_id),
  CONSTRAINT fk_notification_appointment
    FOREIGN KEY (appointment_id, patient_id)
    REFERENCES appointments(appointment_id, patient_id) ON DELETE CASCADE,
  CONSTRAINT fk_notification_preventive_record
    FOREIGN KEY (preventive_record_id, patient_id)
    REFERENCES preventive_care_records(preventive_record_id, patient_id)
    ON DELETE CASCADE,
  CONSTRAINT fk_notification_preventive_reminder
    FOREIGN KEY (preventive_reminder_id, patient_id)
    REFERENCES preventive_care_reminders(preventive_reminder_id, patient_id)
    ON DELETE CASCADE,
  CONSTRAINT fk_notification_laboratory_result
    FOREIGN KEY (laboratory_result_id, patient_id)
    REFERENCES laboratory_results(laboratory_result_id, patient_id)
    ON DELETE CASCADE,
  CONSTRAINT fk_notification_prescription
    FOREIGN KEY (prescription_id, patient_id)
    REFERENCES prescriptions(prescription_id, patient_id)
    ON DELETE CASCADE,
  CONSTRAINT ck_notification_title
    CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  CONSTRAINT ck_notification_message
    CHECK (length(btrim(message)) BETWEEN 1 AND 300),
  CONSTRAINT ck_notification_action
    CHECK (action_label IS NULL OR length(action_label) <= 80),
  CONSTRAINT ck_notification_source_id
    CHECK (length(source_id) <= 180),
  CONSTRAINT ck_notification_source_reference
    CHECK (
      (
        source IN ('app', 'security')
        AND appointment_id IS NULL
        AND preventive_record_id IS NULL
        AND preventive_reminder_id IS NULL
        AND laboratory_result_id IS NULL
        AND prescription_id IS NULL
      )
      OR
      (
        source = 'appointment'
        AND appointment_id IS NOT NULL
        AND source_id = appointment_id
        AND preventive_record_id IS NULL
        AND preventive_reminder_id IS NULL
        AND laboratory_result_id IS NULL
        AND prescription_id IS NULL
      )
      OR
      (
        source = 'preventiveRecord'
        AND preventive_record_id IS NOT NULL
        AND source_id = preventive_record_id
        AND appointment_id IS NULL
        AND preventive_reminder_id IS NULL
        AND laboratory_result_id IS NULL
        AND prescription_id IS NULL
      )
      OR
      (
        source = 'preventiveReminder'
        AND preventive_reminder_id IS NOT NULL
        AND source_id = preventive_reminder_id
        AND appointment_id IS NULL
        AND preventive_record_id IS NULL
        AND laboratory_result_id IS NULL
        AND prescription_id IS NULL
      )
      OR
      (
        source = 'laboratoryResult'
        AND laboratory_result_id IS NOT NULL
        AND source_id = laboratory_result_id
        AND appointment_id IS NULL
        AND preventive_record_id IS NULL
        AND preventive_reminder_id IS NULL
        AND prescription_id IS NULL
      )
      OR
      (
        source = 'prescription'
        AND prescription_id IS NOT NULL
        AND source_id = prescription_id
        AND appointment_id IS NULL
        AND preventive_record_id IS NULL
        AND preventive_reminder_id IS NULL
        AND laboratory_result_id IS NULL
      )
    )
);

CREATE INDEX ix_notifications_patient_feed
  ON notifications (patient_id, created_at DESC);

CREATE INDEX ix_notifications_patient_unread
  ON notifications (patient_id, created_at DESC)
  WHERE is_read = FALSE;

CREATE INDEX ix_notifications_scheduled
  ON notifications (scheduled_at)
  WHERE scheduled_at IS NOT NULL;

-- =============================================================================
-- 11. Catalogues applicatifs configurables
-- =============================================================================

CREATE TABLE health_service_catalog (
  service_key            VARCHAR(80) PRIMARY KEY,
  title                  VARCHAR(120) NOT NULL,
  summary                VARCHAR(300) NOT NULL,
  image_path             TEXT NOT NULL DEFAULT '',
  background_color       CHAR(7) NOT NULL DEFAULT '#FFFFFF',
  accent_color           CHAR(7) NOT NULL DEFAULT '#1769F5',
  action_label           VARCHAR(80) NOT NULL DEFAULT 'Accéder',
  external_url           TEXT,
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order             SMALLINT NOT NULL DEFAULT 0,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_health_service_key
    CHECK (service_key ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
  CONSTRAINT ck_health_service_title
    CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  CONSTRAINT ck_health_service_summary
    CHECK (length(btrim(summary)) BETWEEN 1 AND 300),
  CONSTRAINT ck_health_service_colors
    CHECK (
      background_color ~ '^#[0-9A-Fa-f]{6}$'
      AND accent_color ~ '^#[0-9A-Fa-f]{6}$'
    )
);

-- =============================================================================
-- 12. Fonctions et déclencheurs de cohérence
-- =============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION prevent_row_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'La table % contient des enregistrements immuables après création.', TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$$;

CREATE OR REPLACE FUNCTION prevent_row_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'La table % est un journal immuable.', TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$$;

CREATE OR REPLACE FUNCTION current_actor_id()
RETURNS VARCHAR(128)
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('ientier.current_user_id', TRUE), '')::VARCHAR(128);
$$;

CREATE OR REPLACE FUNCTION current_actor_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM administrators a
    WHERE a.user_id = current_actor_id()
      AND a.active = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION validate_provider_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  linked_type provider_account_type;
  linked_status verification_status;
  linked_visible BOOLEAN;
BEGIN
  IF NEW.account_type = 'professional' AND NEW.linked_institution_id IS NOT NULL THEN
    SELECT account_type, verification_status, is_visible
      INTO linked_type, linked_status, linked_visible
    FROM provider_profiles
    WHERE provider_id = NEW.linked_institution_id;

    IF NOT FOUND
       OR linked_type <> 'institution'
       OR linked_status <> 'approved'
       OR linked_visible <> TRUE THEN
      RAISE EXCEPTION 'L''institution liée doit exister, être approuvée et publiée.';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.provider_id IS DISTINCT FROM OLD.provider_id
       OR NEW.account_type IS DISTINCT FROM OLD.account_type
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'L''identité, le type et la date de création du dossier sont immuables.';
    END IF;

    IF NEW.verification_status IS DISTINCT FROM OLD.verification_status
       AND NOT current_actor_is_admin() THEN
      RAISE EXCEPTION 'Seul un administrateur actif peut changer le statut de vérification.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_institution_capabilities()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM provider_profiles p
    WHERE p.provider_id = NEW.provider_id
      AND p.account_type = 'institution'
  ) THEN
    RAISE EXCEPTION 'Les capacités institutionnelles exigent un profil de type institution.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_appointment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  profile provider_profiles%ROWTYPE;
  configured_mode_count INTEGER;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT *
      INTO profile
    FROM provider_profiles
    WHERE provider_id = NEW.provider_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Le prestataire du rendez-vous n''existe pas.';
    END IF;

    IF profile.account_type <> NEW.provider_type_snapshot THEN
      RAISE EXCEPTION 'Le type du prestataire ne correspond pas à son dossier.';
    END IF;

    IF profile.verification_status <> 'approved'
       OR profile.is_visible <> TRUE
       OR profile.available <> TRUE THEN
      RAISE EXCEPTION 'Le prestataire doit être approuvé, publié et disponible.';
    END IF;

    IF NEW.service_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM provider_services s
         WHERE s.service_id = NEW.service_id
           AND s.provider_id = NEW.provider_id
           AND s.active = TRUE
       ) THEN
      RAISE EXCEPTION 'Le service choisi n''appartient pas au prestataire.';
    END IF;

    SELECT count(*)
      INTO configured_mode_count
    FROM provider_appointment_modes m
    WHERE m.provider_id = NEW.provider_id;

    IF configured_mode_count > 0
       AND NOT EXISTS (
         SELECT 1
         FROM provider_appointment_modes m
         WHERE m.provider_id = NEW.provider_id
           AND m.mode = NEW.mode
           AND m.enabled = TRUE
       ) THEN
      RAISE EXCEPTION 'Ce mode de rendez-vous n''est pas activé par le prestataire.';
    END IF;
  ELSE
    IF NEW.appointment_id IS DISTINCT FROM OLD.appointment_id
       OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.patient_name_snapshot IS DISTINCT FROM OLD.patient_name_snapshot
       OR NEW.provider_id IS DISTINCT FROM OLD.provider_id
       OR NEW.provider_type_snapshot IS DISTINCT FROM OLD.provider_type_snapshot
       OR NEW.provider_name_snapshot IS DISTINCT FROM OLD.provider_name_snapshot
       OR NEW.service_id IS DISTINCT FROM OLD.service_id
       OR NEW.service_name_snapshot IS DISTINCT FROM OLD.service_name_snapshot
       OR NEW.mode IS DISTINCT FROM OLD.mode
       OR NEW.location IS DISTINCT FROM OLD.location
       OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR NEW.schedule_label IS DISTINCT FROM OLD.schedule_label
       OR NEW.patient_note IS DISTINCT FROM OLD.patient_note
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Seuls le statut et la réponse du prestataire peuvent changer.';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF OLD.status <> 'pending' OR NEW.status NOT IN ('confirmed', 'cancelled') THEN
        RAISE EXCEPTION 'Transition de statut de rendez-vous invalide.';
      END IF;

      IF current_actor_id() IS NOT NULL
         AND current_actor_id() <> OLD.provider_id
         AND NOT current_actor_is_admin() THEN
        RAISE EXCEPTION 'Seul le prestataire concerné peut répondre.';
      END IF;

      NEW.responded_at := COALESCE(NEW.responded_at, CURRENT_TIMESTAMP);
    ELSIF NEW.response_note IS DISTINCT FROM OLD.response_note
          OR NEW.responded_at IS DISTINCT FROM OLD.responded_at THEN
      RAISE EXCEPTION 'La réponse ne peut changer sans décision de statut.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit_appointment_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO appointment_status_history (
      appointment_id,
      previous_status,
      new_status,
      changed_by,
      note
    )
    VALUES (
      NEW.appointment_id,
      OLD.status,
      NEW.status,
      COALESCE(current_actor_id(), NEW.provider_id),
      NEW.response_note
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Déclencheurs updated_at.
CREATE TRIGGER trg_00_app_users_updated_at
BEFORE UPDATE ON app_users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_administrators_updated_at
BEFORE UPDATE ON administrators
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_patient_profiles_updated_at
BEFORE UPDATE ON patient_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_patient_emergency_contacts_updated_at
BEFORE UPDATE ON patient_emergency_contacts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_patient_medical_items_updated_at
BEFORE UPDATE ON patient_medical_items
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_provider_profiles_updated_at
BEFORE UPDATE ON provider_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_institution_capabilities_updated_at
BEFORE UPDATE ON institution_capabilities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_provider_services_updated_at
BEFORE UPDATE ON provider_services
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_provider_modes_updated_at
BEFORE UPDATE ON provider_appointment_modes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_provider_availability_updated_at
BEFORE UPDATE ON provider_availability
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_appointments_updated_at
BEFORE UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_cycle_entries_updated_at
BEFORE UPDATE ON cycle_entries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_laboratory_exam_catalog_updated_at
BEFORE UPDATE ON laboratory_exam_catalog
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_laboratory_results_updated_at
BEFORE UPDATE ON laboratory_results
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_preventive_records_updated_at
BEFORE UPDATE ON preventive_care_records
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_notifications_updated_at
BEFORE UPDATE ON notifications
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_00_health_service_catalog_updated_at
BEFORE UPDATE ON health_service_catalog
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Déclencheurs métier.
CREATE TRIGGER trg_10_validate_provider_profile
BEFORE INSERT OR UPDATE ON provider_profiles
FOR EACH ROW EXECUTE FUNCTION validate_provider_profile();

CREATE TRIGGER trg_10_validate_institution_capabilities
BEFORE INSERT OR UPDATE ON institution_capabilities
FOR EACH ROW EXECUTE FUNCTION validate_institution_capabilities();

CREATE TRIGGER trg_10_validate_appointment
BEFORE INSERT OR UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION validate_appointment();

CREATE TRIGGER trg_90_audit_appointment_status
AFTER UPDATE OF status ON appointments
FOR EACH ROW EXECUTE FUNCTION audit_appointment_status();

-- Collections immuables après création, conformément aux règles Firestore.
CREATE TRIGGER trg_health_measurements_immutable
BEFORE UPDATE ON health_measurements
FOR EACH ROW EXECUTE FUNCTION prevent_row_update();

CREATE TRIGGER trg_mental_health_entries_immutable
BEFORE UPDATE ON mental_health_entries
FOR EACH ROW EXECUTE FUNCTION prevent_row_update();

CREATE TRIGGER trg_preventive_reminders_immutable
BEFORE UPDATE ON preventive_care_reminders
FOR EACH ROW EXECUTE FUNCTION prevent_row_update();

CREATE TRIGGER trg_prescriptions_immutable
BEFORE UPDATE ON prescriptions
FOR EACH ROW EXECUTE FUNCTION prevent_row_update();

CREATE TRIGGER trg_provider_reviews_immutable
BEFORE UPDATE OR DELETE ON provider_reviews
FOR EACH ROW EXECUTE FUNCTION prevent_row_change();

CREATE TRIGGER trg_appointment_history_immutable
BEFORE UPDATE OR DELETE ON appointment_status_history
FOR EACH ROW EXECUTE FUNCTION prevent_row_change();

-- Revue administrative atomique : mise à jour du profil + audit immuable.
CREATE OR REPLACE FUNCTION review_provider(
  p_provider_id VARCHAR(128),
  p_admin_id VARCHAR(128),
  p_new_status verification_status,
  p_reason VARCHAR(600) DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  old_status verification_status;
  normalized_reason VARCHAR(600) := btrim(COALESCE(p_reason, ''));
  new_review_id UUID;
BEGIN
  IF current_actor_id() IS NULL THEN
    RAISE EXCEPTION 'Une identité de session ientier.current_user_id est requise.';
  END IF;

  IF current_actor_id() IS NOT NULL AND current_actor_id() <> p_admin_id THEN
    RAISE EXCEPTION 'L''administrateur déclaré ne correspond pas à la session.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM administrators a
    WHERE a.user_id = p_admin_id
      AND a.active = TRUE
  ) THEN
    RAISE EXCEPTION 'Accès administrateur actif requis.';
  END IF;

  IF p_new_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'La décision doit être approved ou rejected.';
  END IF;

  IF p_new_status = 'rejected' AND normalized_reason = '' THEN
    RAISE EXCEPTION 'Un motif de refus est obligatoire.';
  END IF;

  IF p_new_status = 'approved' THEN
    normalized_reason := '';
  END IF;

  SELECT verification_status
    INTO old_status
  FROM provider_profiles
  WHERE provider_id = p_provider_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Le dossier professionnel n''existe pas.';
  END IF;

  IF old_status = p_new_status THEN
    RAISE EXCEPTION 'Cette décision est déjà appliquée.';
  END IF;

  UPDATE provider_profiles
  SET verification_status = p_new_status,
      rejection_reason = normalized_reason,
      is_visible = FALSE
  WHERE provider_id = p_provider_id;

  INSERT INTO provider_reviews (
    provider_id,
    admin_id,
    previous_status,
    new_status,
    reason
  )
  VALUES (
    p_provider_id,
    p_admin_id,
    old_status,
    p_new_status,
    normalized_reason
  )
  RETURNING review_id INTO new_review_id;

  RETURN new_review_id;
END;
$$;

-- Réponse atomique : décision du prestataire + notification patient.
CREATE OR REPLACE FUNCTION respond_to_appointment(
  p_appointment_id VARCHAR(160),
  p_provider_id VARCHAR(128),
  p_new_status appointment_status,
  p_response_note VARCHAR(500) DEFAULT ''
)
RETURNS VARCHAR(180)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  target appointments%ROWTYPE;
  generated_notification_id VARCHAR(180);
  normalized_note VARCHAR(500) := btrim(COALESCE(p_response_note, ''));
BEGIN
  IF current_actor_id() IS NULL THEN
    RAISE EXCEPTION 'Une identité de session ientier.current_user_id est requise.';
  END IF;

  IF current_actor_id() IS NOT NULL
     AND current_actor_id() <> p_provider_id
     AND NOT current_actor_is_admin() THEN
    RAISE EXCEPTION 'Le prestataire déclaré ne correspond pas à la session.';
  END IF;

  IF p_new_status NOT IN ('confirmed', 'cancelled') THEN
    RAISE EXCEPTION 'La réponse doit être confirmed ou cancelled.';
  END IF;

  SELECT *
    INTO target
  FROM appointments
  WHERE appointment_id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Le rendez-vous n''existe pas.';
  END IF;

  IF target.provider_id <> p_provider_id THEN
    RAISE EXCEPTION 'Ce rendez-vous appartient à un autre prestataire.';
  END IF;

  IF target.status <> 'pending' THEN
    RAISE EXCEPTION 'Ce rendez-vous a déjà reçu une réponse.';
  END IF;

  UPDATE appointments
  SET status = p_new_status,
      response_note = normalized_note,
      responded_at = CURRENT_TIMESTAMP
  WHERE appointment_id = p_appointment_id;

  generated_notification_id := 'appointment_' || p_appointment_id;

  INSERT INTO notifications (
    notification_id,
    firestore_id,
    patient_id,
    title,
    message,
    type,
    is_read,
    action_label,
    source,
    source_id,
    appointment_id
  )
  VALUES (
    generated_notification_id,
    generated_notification_id,
    target.patient_id,
    CASE
      WHEN p_new_status = 'confirmed' THEN 'Rendez-vous confirmé'
      ELSE 'Rendez-vous annulé'
    END,
    CASE
      WHEN p_new_status = 'confirmed'
        THEN target.provider_name_snapshot || ' a confirmé votre demande de rendez-vous.'
      ELSE target.provider_name_snapshot || ' a annulé votre demande de rendez-vous.'
    END,
    'appointment',
    FALSE,
    'Voir le rendez-vous',
    'appointment',
    p_appointment_id,
    p_appointment_id
  )
  ON CONFLICT (notification_id) DO UPDATE
  SET title = EXCLUDED.title,
      message = EXCLUDED.message,
      is_read = FALSE,
      updated_at = CURRENT_TIMESTAMP;

  RETURN generated_notification_id;
END;
$$;

-- =============================================================================
-- 13. Vues de lecture partagées entre applications
-- =============================================================================

CREATE VIEW v_public_professionals
WITH (security_barrier = TRUE, security_invoker = TRUE)
AS
SELECT
  p.provider_id,
  p.display_name,
  p.category AS specialty,
  p.workplace,
  p.linked_institution_id,
  COALESCE(i.display_name, p.linked_institution_name_snapshot) AS institution_name,
  p.description AS biography,
  p.experience,
  p.qualifications,
  p.services_summary,
  p.schedule_summary,
  p.phone,
  p.email,
  p.address,
  p.available,
  p.created_at,
  p.updated_at
FROM provider_profiles p
LEFT JOIN provider_profiles i
  ON i.provider_id = p.linked_institution_id
 AND i.account_type = 'institution'
WHERE p.account_type = 'professional'
  AND p.verification_status = 'approved'
  AND p.is_visible = TRUE;

COMMENT ON VIEW v_public_professionals IS
  'Remplace la collection Firestore personnelMedical sans dupliquer le dossier privé.';

CREATE VIEW v_public_institutions
WITH (security_barrier = TRUE, security_invoker = TRUE)
AS
SELECT
  p.provider_id,
  p.display_name,
  p.category AS institution_type,
  p.description,
  p.services_summary,
  p.schedule_summary,
  p.phone,
  p.email,
  p.address,
  p.available,
  p.institution_prices_published,
  p.service_prices_summary,
  p.room_prices_summary,
  c.latitude,
  c.longitude,
  COALESCE(c.home_sampling, FALSE) AS home_sampling,
  COALESCE(c.online_results, FALSE) AS online_results,
  COALESCE(c.accredited, FALSE) AS accredited,
  COALESCE(c.has_emergency_service, FALSE) AS has_emergency_service,
  p.created_at,
  p.updated_at
FROM provider_profiles p
LEFT JOIN institution_capabilities c
  ON c.provider_id = p.provider_id
WHERE p.account_type = 'institution'
  AND p.verification_status = 'approved'
  AND p.is_visible = TRUE;

COMMENT ON VIEW v_public_institutions IS
  'Remplace la collection Firestore institution et alimente hôpitaux, cliniques, pharmacies et laboratoires.';

CREATE VIEW v_provider_application_queue
WITH (security_barrier = TRUE, security_invoker = TRUE)
AS
SELECT
  p.*,
  (
    SELECT max(r.created_at)
    FROM provider_reviews r
    WHERE r.provider_id = p.provider_id
  ) AS last_reviewed_at,
  (
    SELECT count(*)
    FROM provider_reviews r
    WHERE r.provider_id = p.provider_id
  ) AS review_count
FROM provider_profiles p;

COMMENT ON VIEW v_provider_application_queue IS
  'Vue destinée à i-ENTIER Administration; la RLS limite son accès aux propriétaires et administrateurs.';

CREATE VIEW v_patient_health_timeline
WITH (security_barrier = TRUE, security_invoker = TRUE)
AS
SELECT
  h.patient_id,
  h.measurement_id AS event_id,
  h.measured_at AS event_at,
  'healthMeasurement'::TEXT AS event_type,
  h.kind::TEXT AS category,
  h.value::TEXT || ' ' || h.unit AS summary
FROM health_measurements h
UNION ALL
SELECT
  m.patient_id,
  m.mental_health_entry_id,
  m.created_at,
  'mentalHealthEntry',
  m.mood::TEXT,
  'Score ' || m.mood_score::TEXT
FROM mental_health_entries m
UNION ALL
SELECT
  r.patient_id,
  r.preventive_record_id,
  r.completed_at,
  'preventiveCareRecord',
  r.category::TEXT,
  r.title
FROM preventive_care_records r
UNION ALL
SELECT
  l.patient_id,
  l.laboratory_result_id,
  COALESCE(l.published_at, l.collected_at, l.created_at),
  'laboratoryResult',
  l.status::TEXT,
  l.exam_name_snapshot
FROM laboratory_results l;

-- =============================================================================
-- 14. Sécurité ligne par ligne (RLS)
-- =============================================================================

ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE administrators ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_medical_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE institution_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_appointment_modes ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_service_modes ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE health_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE cycle_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE cycle_entry_symptoms ENABLE ROW LEVEL SECURITY;
ALTER TABLE mental_health_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE mental_health_entry_feelings ENABLE ROW LEVEL SECURITY;
ALTER TABLE laboratory_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE laboratory_result_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE preventive_care_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE preventive_care_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY app_users_select
ON app_users FOR SELECT
USING (user_id = current_actor_id() OR current_actor_is_admin());

CREATE POLICY app_users_insert
ON app_users FOR INSERT
WITH CHECK (user_id = current_actor_id());

CREATE POLICY app_users_update
ON app_users FOR UPDATE
USING (user_id = current_actor_id())
WITH CHECK (user_id = current_actor_id());

CREATE POLICY administrators_select
ON administrators FOR SELECT
USING (user_id = current_actor_id() OR current_actor_is_admin());

CREATE POLICY patient_profiles_owner
ON patient_profiles FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY patient_emergency_contacts_owner
ON patient_emergency_contacts FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY patient_medical_items_owner
ON patient_medical_items FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY provider_profiles_select
ON provider_profiles FOR SELECT
USING (
  provider_id = current_actor_id()
  OR current_actor_is_admin()
  OR (
    current_actor_id() IS NOT NULL
    AND verification_status = 'approved'
    AND is_visible = TRUE
  )
);

CREATE POLICY provider_profiles_insert
ON provider_profiles FOR INSERT
WITH CHECK (
  provider_id = current_actor_id()
  AND verification_status = 'pending'
  AND is_visible = FALSE
);

CREATE POLICY provider_profiles_update_owner
ON provider_profiles FOR UPDATE
USING (provider_id = current_actor_id())
WITH CHECK (provider_id = current_actor_id());

CREATE POLICY provider_profiles_update_admin
ON provider_profiles FOR UPDATE
USING (current_actor_is_admin())
WITH CHECK (current_actor_is_admin());

CREATE POLICY institution_capabilities_select
ON institution_capabilities FOR SELECT
USING (
  provider_id = current_actor_id()
  OR current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM provider_profiles p
    WHERE p.provider_id = institution_capabilities.provider_id
      AND p.verification_status = 'approved'
      AND p.is_visible = TRUE
  )
);

CREATE POLICY institution_capabilities_owner
ON institution_capabilities FOR ALL
USING (provider_id = current_actor_id())
WITH CHECK (provider_id = current_actor_id());

CREATE POLICY provider_services_select
ON provider_services FOR SELECT
USING (
  provider_id = current_actor_id()
  OR current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM provider_profiles p
    WHERE p.provider_id = provider_services.provider_id
      AND p.verification_status = 'approved'
      AND p.is_visible = TRUE
  )
);

CREATE POLICY provider_services_owner
ON provider_services FOR ALL
USING (provider_id = current_actor_id())
WITH CHECK (provider_id = current_actor_id());

CREATE POLICY provider_modes_select
ON provider_appointment_modes FOR SELECT
USING (
  provider_id = current_actor_id()
  OR current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM provider_profiles p
    WHERE p.provider_id = provider_appointment_modes.provider_id
      AND p.verification_status = 'approved'
      AND p.is_visible = TRUE
  )
);

CREATE POLICY provider_modes_owner
ON provider_appointment_modes FOR ALL
USING (provider_id = current_actor_id())
WITH CHECK (provider_id = current_actor_id());

CREATE POLICY provider_service_modes_select
ON provider_service_modes FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM provider_services s
    WHERE s.service_id = provider_service_modes.service_id
  )
);

CREATE POLICY provider_service_modes_owner
ON provider_service_modes FOR ALL
USING (
  EXISTS (
    SELECT 1
    FROM provider_services s
    WHERE s.service_id = provider_service_modes.service_id
      AND s.provider_id = current_actor_id()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM provider_services s
    WHERE s.service_id = provider_service_modes.service_id
      AND s.provider_id = current_actor_id()
  )
);

CREATE POLICY provider_availability_select
ON provider_availability FOR SELECT
USING (
  provider_id = current_actor_id()
  OR current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM provider_profiles p
    WHERE p.provider_id = provider_availability.provider_id
      AND p.verification_status = 'approved'
      AND p.is_visible = TRUE
  )
);

CREATE POLICY provider_availability_owner
ON provider_availability FOR ALL
USING (provider_id = current_actor_id())
WITH CHECK (provider_id = current_actor_id());

CREATE POLICY provider_reviews_admin
ON provider_reviews FOR SELECT
USING (current_actor_is_admin());

CREATE POLICY appointments_participants
ON appointments FOR SELECT
USING (
  patient_id = current_actor_id()
  OR provider_id = current_actor_id()
  OR current_actor_is_admin()
);

CREATE POLICY appointments_patient_insert
ON appointments FOR INSERT
WITH CHECK (
  patient_id = current_actor_id()
  AND status = 'pending'
);

CREATE POLICY appointments_provider_update
ON appointments FOR UPDATE
USING (provider_id = current_actor_id() AND status = 'pending')
WITH CHECK (provider_id = current_actor_id());

CREATE POLICY appointment_history_participants
ON appointment_status_history FOR SELECT
USING (
  current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM appointments a
    WHERE a.appointment_id = appointment_status_history.appointment_id
      AND (
        a.patient_id = current_actor_id()
        OR a.provider_id = current_actor_id()
      )
  )
);

CREATE POLICY health_measurements_owner
ON health_measurements FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY cycle_entries_owner
ON cycle_entries FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY cycle_entry_symptoms_owner
ON cycle_entry_symptoms FOR ALL
USING (
  EXISTS (
    SELECT 1
    FROM cycle_entries c
    WHERE c.cycle_entry_id = cycle_entry_symptoms.cycle_entry_id
      AND c.patient_id = current_actor_id()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM cycle_entries c
    WHERE c.cycle_entry_id = cycle_entry_symptoms.cycle_entry_id
      AND c.patient_id = current_actor_id()
  )
);

CREATE POLICY mental_health_entries_owner
ON mental_health_entries FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY mental_health_feelings_owner
ON mental_health_entry_feelings FOR ALL
USING (
  EXISTS (
    SELECT 1
    FROM mental_health_entries m
    WHERE m.mental_health_entry_id = mental_health_entry_feelings.mental_health_entry_id
      AND m.patient_id = current_actor_id()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM mental_health_entries m
    WHERE m.mental_health_entry_id = mental_health_entry_feelings.mental_health_entry_id
      AND m.patient_id = current_actor_id()
  )
);

CREATE POLICY laboratory_results_owner
ON laboratory_results FOR SELECT
USING (patient_id = current_actor_id());

CREATE POLICY laboratory_result_items_owner
ON laboratory_result_items FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM laboratory_results r
    WHERE r.laboratory_result_id = laboratory_result_items.laboratory_result_id
      AND r.patient_id = current_actor_id()
  )
);

CREATE POLICY preventive_records_owner
ON preventive_care_records FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY preventive_reminders_owner
ON preventive_care_reminders FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY prescriptions_owner
ON prescriptions FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY prescription_items_owner
ON prescription_items FOR ALL
USING (
  EXISTS (
    SELECT 1
    FROM prescriptions p
    WHERE p.prescription_id = prescription_items.prescription_id
      AND p.patient_id = current_actor_id()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM prescriptions p
    WHERE p.prescription_id = prescription_items.prescription_id
      AND p.patient_id = current_actor_id()
  )
);

CREATE POLICY notifications_patient
ON notifications FOR ALL
USING (patient_id = current_actor_id())
WITH CHECK (patient_id = current_actor_id());

CREATE POLICY notifications_provider_insert
ON notifications FOR INSERT
WITH CHECK (
  source = 'appointment'
  AND appointment_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM appointments a
    WHERE a.appointment_id = notifications.appointment_id
      AND a.patient_id = notifications.patient_id
      AND a.provider_id = current_actor_id()
  )
);

-- =============================================================================
-- 15. Données de référence présentes dans l'application patient
-- =============================================================================

INSERT INTO health_service_catalog (
  service_key,
  title,
  summary,
  image_path,
  background_color,
  accent_color,
  action_label,
  external_url,
  sort_order
)
VALUES
  (
    'pharmacie',
    'Pharmacie',
    'Commandez vos médicaments en ligne',
    'pharma.png',
    '#D7F5F1',
    '#009B88',
    'Accéder',
    NULL,
    10
  ),
  (
    'don-de-sang',
    'Don de sang',
    'Trouvez un centre et sauvez des vies',
    'sang.png',
    '#FFA2A8',
    '#F01924',
    'Accéder',
    'https://www.croixrouge.ht/2-check-up/',
    20
  ),
  (
    'laboratoire',
    'Laboratoire',
    'Trouvez un labo pour votre examen',
    'laboratoire.png',
    '#DDF6F4',
    '#009B88',
    'Accéder',
    NULL,
    30
  ),
  (
    'suivi-cycle',
    'Suivi de cycle',
    'Comprenez votre cycle et vos symptômes',
    'regles.png',
    '#F0E8FF',
    '#7C5CE5',
    'Accéder',
    NULL,
    40
  ),
  (
    'soutien-psychologique',
    'Bien-être mental',
    'Écoutez-vous et trouvez du soutien',
    'mental_health.png',
    '#F3ECFF',
    '#7656D8',
    'Prendre soin de moi',
    NULL,
    50
  ),
  (
    'medecine-preventive',
    'Prévention',
    'Planifiez vos bilans et protégez votre santé',
    'preventive_medicine.png',
    '#E7F3FF',
    '#176BFF',
    'Voir mon plan',
    NULL,
    60
  )
ON CONFLICT (service_key) DO NOTHING;

INSERT INTO laboratory_exam_catalog (
  exam_id,
  name,
  category,
  description,
  sample_type,
  preparation,
  turnaround
)
VALUES
  (
    'nfs',
    'Numération formule sanguine',
    'Sang',
    'Évalue les globules rouges, les globules blancs et les plaquettes.',
    'Prélèvement sanguin',
    'Aucun jeûne requis, sauf indication contraire.',
    'Sous 24 h'
  ),
  (
    'glycemie',
    'Glycémie',
    'Sang',
    'Mesure le taux de glucose présent dans le sang.',
    'Prélèvement sanguin',
    'Un jeûne de 8 à 12 heures peut être demandé selon la prescription.',
    'Le jour même'
  ),
  (
    'bilan-lipidique',
    'Bilan lipidique',
    'Prévention',
    'Mesure notamment le cholestérol total, le HDL, le LDL et les triglycérides.',
    'Prélèvement sanguin',
    'Le laboratoire précisera si un jeûne est nécessaire avant le prélèvement.',
    'Sous 24 à 48 h'
  ),
  (
    'tsh',
    'TSH',
    'Hormones',
    'Aide à évaluer le fonctionnement de la thyroïde.',
    'Prélèvement sanguin',
    'Signalez vos traitements au laboratoire et suivez les consignes reçues.',
    'Sous 24 à 48 h'
  ),
  (
    'test-grossesse',
    'Test de grossesse β-hCG',
    'Hormones',
    'Recherche ou mesure l''hormone β-hCG.',
    'Sang ou urine',
    'Aucune préparation particulière en général.',
    'Le jour même'
  ),
  (
    'analyse-urines',
    'Analyse d''urines',
    'Urines',
    'Recherche différents marqueurs et signes possibles d''infection.',
    'Échantillon d''urine',
    'Utilisez le flacon fourni et respectez les consignes de recueil.',
    'Sous 24 à 72 h'
  ),
  (
    'vih',
    'Dépistage du VIH',
    'Dépistage',
    'Recherche des marqueurs associés au virus de l''immunodéficience humaine.',
    'Prélèvement sanguin',
    'Aucun jeûne requis. Un accompagnement peut être proposé.',
    'Selon la méthode'
  ),
  (
    'hepatite-b',
    'Dépistage de l''hépatite B',
    'Dépistage',
    'Recherche des marqueurs liés au virus de l''hépatite B.',
    'Prélèvement sanguin',
    'Aucune préparation particulière en général.',
    'Sous 1 à 3 jours'
  )
ON CONFLICT (exam_id) DO NOTHING;

-- Documentation des éléments sensibles.
COMMENT ON TABLE health_measurements IS
  'Mesures privées et immuables après création; suppression autorisée au propriétaire.';
COMMENT ON TABLE mental_health_entries IS
  'Journal de bien-être privé et immuable après création.';
COMMENT ON TABLE provider_reviews IS
  'Journal d''audit immuable de toutes les décisions administratives.';
COMMENT ON TABLE appointments IS
  'Demandes partagées uniquement entre le patient, le prestataire et le backend autorisé.';
COMMENT ON TABLE prescriptions IS
  'Ordonnances scannées ou émises par un professionnel; fichier patient limité à 10 Mio côté stockage.';

COMMIT;
