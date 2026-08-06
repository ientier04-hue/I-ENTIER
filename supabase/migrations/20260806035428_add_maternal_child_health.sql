-- Service Maman & Bébé : grossesse, calendrier prénatal et suivi 0–5 ans.

BEGIN;

SET search_path TO ientier, public;

CREATE TABLE pregnancy_profiles (
  pregnancy_id          VARCHAR(160) PRIMARY KEY,
  patient_id            VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  last_menstrual_period DATE NOT NULL,
  estimated_due_date    DATE NOT NULL,
  gravida               SMALLINT NOT NULL DEFAULT 1,
  parity                SMALLINT NOT NULL DEFAULT 0,
  previous_complications TEXT[] NOT NULL DEFAULT '{}',
  risk_factors          TEXT[] NOT NULL DEFAULT '{}',
  nutrition_habits      TEXT[] NOT NULL DEFAULT '{}',
  status                VARCHAR(24) NOT NULL DEFAULT 'active',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_pregnancy_dates
    CHECK (estimated_due_date BETWEEN last_menstrual_period + 245
                                  AND last_menstrual_period + 315),
  CONSTRAINT ck_pregnancy_history
    CHECK (gravida BETWEEN 1 AND 30 AND parity BETWEEN 0 AND gravida),
  CONSTRAINT ck_pregnancy_status
    CHECK (status IN ('active', 'postpartum', 'completed', 'archived'))
);

CREATE UNIQUE INDEX uq_one_active_pregnancy_per_patient
  ON pregnancy_profiles (patient_id)
  WHERE status = 'active';
CREATE INDEX ix_pregnancy_profiles_patient
  ON pregnancy_profiles (patient_id, updated_at DESC);

CREATE TABLE pregnancy_reminders (
  reminder_id           VARCHAR(180) PRIMARY KEY,
  pregnancy_id          VARCHAR(160) NOT NULL
                        REFERENCES pregnancy_profiles(pregnancy_id) ON DELETE CASCADE,
  patient_id            VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  category              VARCHAR(32) NOT NULL,
  title                 VARCHAR(180) NOT NULL,
  details               VARCHAR(700) NOT NULL DEFAULT '',
  due_at                TIMESTAMPTZ NOT NULL,
  status                VARCHAR(24) NOT NULL DEFAULT 'planned',
  completed_at          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_pregnancy_reminder_category
    CHECK (category IN (
      'consultation', 'ultrasound', 'laboratory', 'vaccination',
      'supplementation', 'birth_preparation', 'custom'
    )),
  CONSTRAINT ck_pregnancy_reminder_status
    CHECK (status IN ('planned', 'completed', 'skipped')),
  CONSTRAINT ck_pregnancy_reminder_completion
    CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

CREATE INDEX ix_pregnancy_reminders_due
  ON pregnancy_reminders (patient_id, status, due_at);

CREATE TABLE child_profiles (
  child_id              VARCHAR(160) PRIMARY KEY,
  guardian_patient_id   VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  first_name            VARCHAR(100) NOT NULL,
  birth_date            DATE NOT NULL,
  sex                   VARCHAR(24) NOT NULL DEFAULT 'non_precise',
  birth_weight_kg       NUMERIC(5,2),
  birth_length_cm       NUMERIC(5,2),
  notes                 VARCHAR(700) NOT NULL DEFAULT '',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_child_first_name
    CHECK (length(btrim(first_name)) BETWEEN 1 AND 100),
  CONSTRAINT ck_child_birth_date
    CHECK (birth_date BETWEEN DATE '2000-01-01' AND CURRENT_DATE),
  CONSTRAINT ck_child_age_scope
    CHECK (birth_date >= CURRENT_DATE - INTERVAL '6 years'),
  CONSTRAINT ck_child_sex
    CHECK (sex IN ('feminin', 'masculin', 'intersexe', 'non_precise')),
  CONSTRAINT ck_child_birth_weight
    CHECK (birth_weight_kg IS NULL OR birth_weight_kg BETWEEN 0.3 AND 10),
  CONSTRAINT ck_child_birth_length
    CHECK (birth_length_cm IS NULL OR birth_length_cm BETWEEN 20 AND 75)
);

CREATE INDEX ix_child_profiles_guardian
  ON child_profiles (guardian_patient_id, birth_date DESC);

CREATE TABLE child_growth_records (
  growth_record_id      VARCHAR(180) PRIMARY KEY,
  child_id              VARCHAR(160) NOT NULL
                        REFERENCES child_profiles(child_id) ON DELETE CASCADE,
  guardian_patient_id   VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  measured_at           DATE NOT NULL,
  weight_kg             NUMERIC(6,2) NOT NULL,
  height_cm             NUMERIC(6,2) NOT NULL,
  head_circumference_cm NUMERIC(5,2),
  measured_by           VARCHAR(140) NOT NULL DEFAULT '',
  notes                 VARCHAR(500) NOT NULL DEFAULT '',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_child_growth_date
    CHECK (measured_at <= CURRENT_DATE),
  CONSTRAINT ck_child_growth_weight
    CHECK (weight_kg BETWEEN 0.3 AND 80),
  CONSTRAINT ck_child_growth_height
    CHECK (height_cm BETWEEN 20 AND 150),
  CONSTRAINT ck_child_growth_head
    CHECK (head_circumference_cm IS NULL
           OR head_circumference_cm BETWEEN 15 AND 80)
);

CREATE INDEX ix_child_growth_timeline
  ON child_growth_records (child_id, measured_at DESC);

CREATE TABLE child_vaccination_records (
  vaccination_record_id VARCHAR(180) PRIMARY KEY,
  child_id              VARCHAR(160) NOT NULL
                        REFERENCES child_profiles(child_id) ON DELETE CASCADE,
  guardian_patient_id   VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  vaccine_code          VARCHAR(60) NOT NULL,
  vaccine_name          VARCHAR(180) NOT NULL,
  dose_label            VARCHAR(80) NOT NULL DEFAULT '',
  due_on                DATE NOT NULL,
  administered_on       DATE,
  facility_name         VARCHAR(180) NOT NULL DEFAULT '',
  lot_number            VARCHAR(100) NOT NULL DEFAULT '',
  notes                 VARCHAR(500) NOT NULL DEFAULT '',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_child_vaccine_dates
    CHECK (administered_on IS NULL OR administered_on <= CURRENT_DATE)
);

CREATE INDEX ix_child_vaccinations_due
  ON child_vaccination_records (child_id, administered_on, due_on);

-- Lien de consentement entre la famille et un membre vérifié du réseau de soins.
CREATE TABLE maternal_care_connections (
  connection_id         VARCHAR(180) PRIMARY KEY,
  patient_id            VARCHAR(128) NOT NULL
                        REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  provider_id           VARCHAR(128) NOT NULL
                        REFERENCES provider_profiles(provider_id) ON DELETE CASCADE,
  pregnancy_id          VARCHAR(160)
                        REFERENCES pregnancy_profiles(pregnancy_id) ON DELETE CASCADE,
  child_id              VARCHAR(160)
                        REFERENCES child_profiles(child_id) ON DELETE CASCADE,
  care_role             VARCHAR(60) NOT NULL,
  access_scopes         TEXT[] NOT NULL DEFAULT '{}',
  status                VARCHAR(24) NOT NULL DEFAULT 'pending',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_maternal_connection_target
    CHECK (pregnancy_id IS NOT NULL OR child_id IS NOT NULL),
  CONSTRAINT ck_maternal_connection_status
    CHECK (status IN ('pending', 'active', 'revoked')),
  CONSTRAINT ck_maternal_connection_role
    CHECK (care_role IN ('sage_femme', 'medecin', 'centre_sante', 'maternite'))
);

CREATE UNIQUE INDEX uq_maternal_care_connection
  ON maternal_care_connections (
    patient_id,
    provider_id,
    COALESCE(pregnancy_id, ''),
    COALESCE(child_id, '')
  );
CREATE INDEX ix_maternal_connections_provider
  ON maternal_care_connections (provider_id, status, updated_at DESC);

CREATE TRIGGER trg_pregnancy_profiles_updated_at
BEFORE UPDATE ON pregnancy_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_pregnancy_reminders_updated_at
BEFORE UPDATE ON pregnancy_reminders
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_child_profiles_updated_at
BEFORE UPDATE ON child_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_child_vaccination_records_updated_at
BEFORE UPDATE ON child_vaccination_records
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_maternal_care_connections_updated_at
BEFORE UPDATE ON maternal_care_connections
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE pregnancy_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_growth_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_vaccination_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE maternal_care_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY pregnancy_profiles_owner
ON pregnancy_profiles FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = patient_id);

CREATE POLICY pregnancy_reminders_owner
ON pregnancy_reminders FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = patient_id);

CREATE POLICY child_profiles_guardian
ON child_profiles FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = guardian_patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = guardian_patient_id);

CREATE POLICY child_growth_guardian
ON child_growth_records FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = guardian_patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = guardian_patient_id);

CREATE POLICY child_vaccinations_guardian
ON child_vaccination_records FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = guardian_patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = guardian_patient_id);

CREATE POLICY maternal_connections_patient
ON maternal_care_connections FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = patient_id);

CREATE POLICY maternal_connections_provider_select
ON maternal_care_connections FOR SELECT TO authenticated
USING (
  (SELECT auth.uid())::TEXT = provider_id
  AND status IN ('pending', 'active')
);

-- Les professionnels ne voient que les dossiers explicitement partagés.
CREATE POLICY pregnancy_profiles_care_team_select
ON pregnancy_profiles FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM maternal_care_connections connection
    WHERE connection.pregnancy_id = pregnancy_profiles.pregnancy_id
      AND connection.provider_id = (SELECT auth.uid())::TEXT
      AND connection.status = 'active'
      AND 'pregnancy' = ANY(connection.access_scopes)
  )
);

CREATE POLICY pregnancy_reminders_care_team_select
ON pregnancy_reminders FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM maternal_care_connections connection
    WHERE connection.pregnancy_id = pregnancy_reminders.pregnancy_id
      AND connection.provider_id = (SELECT auth.uid())::TEXT
      AND connection.status = 'active'
      AND 'calendar' = ANY(connection.access_scopes)
  )
);

CREATE POLICY child_profiles_care_team_select
ON child_profiles FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM maternal_care_connections connection
    WHERE connection.child_id = child_profiles.child_id
      AND connection.provider_id = (SELECT auth.uid())::TEXT
      AND connection.status = 'active'
      AND 'child_profile' = ANY(connection.access_scopes)
  )
);

CREATE POLICY child_growth_care_team_select
ON child_growth_records FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM maternal_care_connections connection
    WHERE connection.child_id = child_growth_records.child_id
      AND connection.provider_id = (SELECT auth.uid())::TEXT
      AND connection.status = 'active'
      AND 'growth' = ANY(connection.access_scopes)
  )
);

CREATE POLICY child_vaccinations_care_team_select
ON child_vaccination_records FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM maternal_care_connections connection
    WHERE connection.child_id = child_vaccination_records.child_id
      AND connection.provider_id = (SELECT auth.uid())::TEXT
      AND connection.status = 'active'
      AND 'vaccinations' = ANY(connection.access_scopes)
  )
);

GRANT SELECT, INSERT, UPDATE, DELETE ON
  pregnancy_profiles,
  pregnancy_reminders,
  child_profiles,
  child_growth_records,
  child_vaccination_records,
  maternal_care_connections
TO authenticated;

GRANT ALL ON
  pregnancy_profiles,
  pregnancy_reminders,
  child_profiles,
  child_growth_records,
  child_vaccination_records,
  maternal_care_connections
TO service_role;

DO $$
DECLARE
  relation_name TEXT;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[
    'pregnancy_profiles',
    'pregnancy_reminders',
    'child_profiles',
    'child_growth_records',
    'child_vaccination_records',
    'maternal_care_connections'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'ientier'
        AND tablename = relation_name
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE ientier.%I',
        relation_name
      );
    END IF;
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
