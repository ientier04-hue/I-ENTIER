BEGIN;

SET search_path TO ientier, public;

CREATE TABLE mobile_clinics (
  mobile_clinic_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_provider_id          VARCHAR(128) NOT NULL
                             REFERENCES provider_profiles(provider_id) ON DELETE RESTRICT,
  owner_account_type         provider_account_type NOT NULL,
  creator_type               VARCHAR(48) NOT NULL,
  name                       VARCHAR(180) NOT NULL,
  responsible_name           VARCHAR(160) NOT NULL,
  phone                      VARCHAR(40) NOT NULL DEFAULT '',
  email                      CITEXT,
  description                VARCHAR(1200) NOT NULL DEFAULT '',
  base_address               VARCHAR(300) NOT NULL DEFAULT '',
  department                 VARCHAR(100) NOT NULL,
  commune                    VARCHAR(120) NOT NULL,
  latitude                   NUMERIC(9,6),
  longitude                  NUMERIC(9,6),
  identity_document_url      TEXT NOT NULL,
  professional_license_url   TEXT NOT NULL DEFAULT '',
  operating_authorization_url TEXT NOT NULL,
  partner_document_urls      TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  verification_status        verification_status NOT NULL DEFAULT 'pending',
  rejection_reason           VARCHAR(700) NOT NULL DEFAULT '',
  certification_badge        VARCHAR(100) NOT NULL DEFAULT '',
  certified_at               TIMESTAMPTZ,
  reviewed_by                VARCHAR(128) REFERENCES administrators(user_id) ON DELETE SET NULL,
  reviewed_at                TIMESTAMPTZ,
  is_published               BOOLEAN NOT NULL DEFAULT FALSE,
  is_deployed                BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_mobile_clinic_creator_type CHECK (creator_type IN (
    'doctor', 'nurse', 'midwife', 'dentist', 'other_certified_professional',
    'hospital', 'private_clinic', 'health_center', 'ngo',
    'public_health_institution', 'company'
  )),
  CONSTRAINT ck_mobile_clinic_identity CHECK (
    length(btrim(name)) BETWEEN 3 AND 180
    AND length(btrim(responsible_name)) BETWEEN 3 AND 160
    AND length(btrim(department)) BETWEEN 2 AND 100
    AND length(btrim(commune)) BETWEEN 2 AND 120
  ),
  CONSTRAINT ck_mobile_clinic_documents CHECK (
    length(btrim(identity_document_url)) > 5
    AND length(btrim(operating_authorization_url)) > 5
    AND (
      creator_type NOT IN ('doctor', 'nurse', 'midwife', 'dentist', 'other_certified_professional')
      OR length(btrim(professional_license_url)) > 5
    )
  ),
  CONSTRAINT ck_mobile_clinic_coordinates CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
  ),
  CONSTRAINT ck_mobile_clinic_certification CHECK (
    (verification_status = 'approved'
      AND certification_badge = 'Clinique Mobile Certifiée I-Entier'
      AND certified_at IS NOT NULL
      AND reviewed_by IS NOT NULL
      AND reviewed_at IS NOT NULL)
    OR (verification_status <> 'approved'
      AND certification_badge = ''
      AND certified_at IS NULL)
  ),
  CONSTRAINT ck_mobile_clinic_publication CHECK (
    is_published = FALSE OR verification_status = 'approved'
  )
);

CREATE INDEX ix_mobile_clinics_owner
  ON mobile_clinics (owner_provider_id, updated_at DESC);
CREATE INDEX ix_mobile_clinics_public
  ON mobile_clinics (department, commune, is_deployed, updated_at DESC)
  WHERE verification_status = 'approved' AND is_published = TRUE;
CREATE INDEX ix_mobile_clinics_review_queue
  ON mobile_clinics (verification_status, created_at);

CREATE TABLE mobile_clinic_services (
  mobile_clinic_service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile_clinic_id         UUID NOT NULL
                           REFERENCES mobile_clinics(mobile_clinic_id) ON DELETE CASCADE,
  name                     VARCHAR(160) NOT NULL,
  description              VARCHAR(600) NOT NULL DEFAULT '',
  duration_minutes         SMALLINT NOT NULL DEFAULT 30,
  price_htg                NUMERIC(12,2),
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_mobile_clinic_service_name CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  CONSTRAINT ck_mobile_clinic_service_duration CHECK (duration_minutes BETWEEN 10 AND 480),
  CONSTRAINT ck_mobile_clinic_service_price CHECK (price_htg IS NULL OR price_htg >= 0),
  CONSTRAINT uq_mobile_clinic_service UNIQUE (mobile_clinic_id, name)
);

CREATE TABLE mobile_clinic_staff (
  mobile_clinic_staff_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile_clinic_id       UUID NOT NULL
                         REFERENCES mobile_clinics(mobile_clinic_id) ON DELETE CASCADE,
  provider_id            VARCHAR(128) REFERENCES provider_profiles(provider_id) ON DELETE SET NULL,
  full_name              VARCHAR(160) NOT NULL,
  profession             VARCHAR(120) NOT NULL,
  license_number         VARCHAR(120) NOT NULL DEFAULT '',
  document_url           TEXT NOT NULL DEFAULT '',
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_mobile_clinic_staff_identity CHECK (
    length(btrim(full_name)) BETWEEN 3 AND 160
    AND length(btrim(profession)) BETWEEN 2 AND 120
  )
);

CREATE TABLE mobile_clinic_tours (
  mobile_clinic_tour_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile_clinic_id      UUID NOT NULL
                        REFERENCES mobile_clinics(mobile_clinic_id) ON DELETE CASCADE,
  zone_name             VARCHAR(180) NOT NULL,
  location_label        VARCHAR(300) NOT NULL,
  department            VARCHAR(100) NOT NULL,
  commune               VARCHAR(120) NOT NULL,
  latitude              NUMERIC(9,6),
  longitude             NUMERIC(9,6),
  starts_at             TIMESTAMPTZ NOT NULL,
  ends_at               TIMESTAMPTZ NOT NULL,
  daily_schedule        VARCHAR(180) NOT NULL DEFAULT 'Tous les jours 08h-16h',
  status                VARCHAR(20) NOT NULL DEFAULT 'planned',
  notes                 VARCHAR(700) NOT NULL DEFAULT '',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_mobile_clinic_tour_status CHECK (status IN ('planned', 'active', 'completed', 'cancelled')),
  CONSTRAINT ck_mobile_clinic_tour_window CHECK (ends_at > starts_at),
  CONSTRAINT ck_mobile_clinic_tour_identity CHECK (
    length(btrim(zone_name)) BETWEEN 2 AND 180
    AND length(btrim(location_label)) BETWEEN 3 AND 300
  ),
  CONSTRAINT ck_mobile_clinic_tour_coordinates CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
  )
);

CREATE INDEX ix_mobile_clinic_tours_public
  ON mobile_clinic_tours (status, starts_at, ends_at);
CREATE INDEX ix_mobile_clinic_tours_clinic
  ON mobile_clinic_tours (mobile_clinic_id, starts_at DESC);

CREATE TABLE mobile_clinic_interventions (
  mobile_clinic_intervention_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile_clinic_id              UUID NOT NULL
                                REFERENCES mobile_clinics(mobile_clinic_id) ON DELETE CASCADE,
  mobile_clinic_tour_id         UUID REFERENCES mobile_clinic_tours(mobile_clinic_tour_id) ON DELETE SET NULL,
  appointment_id               VARCHAR(160) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
  service_name                 VARCHAR(160) NOT NULL,
  intervention_at              TIMESTAMPTZ NOT NULL,
  beneficiaries_count          INTEGER NOT NULL DEFAULT 1,
  notes                        VARCHAR(1000) NOT NULL DEFAULT '',
  created_by                   VARCHAR(128) NOT NULL REFERENCES app_users(user_id) ON DELETE RESTRICT,
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_mobile_clinic_intervention_service CHECK (length(btrim(service_name)) BETWEEN 2 AND 160),
  CONSTRAINT ck_mobile_clinic_beneficiaries CHECK (beneficiaries_count BETWEEN 1 AND 10000)
);

ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS mobile_clinic_id UUID
    REFERENCES mobile_clinics(mobile_clinic_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS mobile_clinic_tour_id UUID
    REFERENCES mobile_clinic_tours(mobile_clinic_tour_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_appointments_mobile_clinic
  ON appointments (mobile_clinic_id, scheduled_at DESC)
  WHERE mobile_clinic_id IS NOT NULL;

CREATE OR REPLACE FUNCTION validate_mobile_clinic()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  profile provider_profiles%ROWTYPE;
  professional_creator BOOLEAN;
BEGIN
  SELECT * INTO profile
  FROM provider_profiles
  WHERE provider_id = NEW.owner_provider_id;

  IF NOT FOUND OR profile.verification_status <> 'approved' THEN
    RAISE EXCEPTION 'Un profil professionnel ou institutionnel validé est requis.';
  END IF;

  professional_creator := NEW.creator_type IN (
    'doctor', 'nurse', 'midwife', 'dentist', 'other_certified_professional'
  );
  IF (professional_creator AND profile.account_type <> 'professional')
     OR (NOT professional_creator AND profile.account_type <> 'institution') THEN
    RAISE EXCEPTION 'Le type de créateur ne correspond pas au profil validé.';
  END IF;

  NEW.owner_account_type := profile.account_type;

  IF TG_OP = 'INSERT' THEN
    IF NOT current_actor_is_admin() AND NEW.owner_provider_id <> current_actor_id() THEN
      RAISE EXCEPTION 'Vous ne pouvez soumettre qu''une demande pour votre propre profil.';
    END IF;
    NEW.verification_status := 'pending';
    NEW.rejection_reason := '';
    NEW.certification_badge := '';
    NEW.certified_at := NULL;
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    NEW.is_published := FALSE;
    NEW.is_deployed := FALSE;
  ELSIF NOT current_actor_is_admin() THEN
    IF NEW.owner_provider_id IS DISTINCT FROM OLD.owner_provider_id
       OR NEW.owner_account_type IS DISTINCT FROM OLD.owner_account_type
       OR NEW.creator_type IS DISTINCT FROM OLD.creator_type
       OR NEW.verification_status IS DISTINCT FROM OLD.verification_status
       OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
       OR NEW.certification_badge IS DISTINCT FROM OLD.certification_badge
       OR NEW.certified_at IS DISTINCT FROM OLD.certified_at
       OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
       OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Les informations administratives sont protégées.';
    END IF;
  END IF;

  IF NEW.is_published AND NEW.verification_status <> 'approved' THEN
    RAISE EXCEPTION 'La clinique doit être certifiée avant sa publication.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_00_mobile_clinics_updated_at
BEFORE UPDATE ON mobile_clinics
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_10_validate_mobile_clinic
BEFORE INSERT OR UPDATE ON mobile_clinics
FOR EACH ROW EXECUTE FUNCTION validate_mobile_clinic();

CREATE TRIGGER trg_00_mobile_clinic_services_updated_at
BEFORE UPDATE ON mobile_clinic_services
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_00_mobile_clinic_staff_updated_at
BEFORE UPDATE ON mobile_clinic_staff
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_00_mobile_clinic_tours_updated_at
BEFORE UPDATE ON mobile_clinic_tours
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION review_mobile_clinic(
  p_mobile_clinic_id UUID,
  p_admin_id VARCHAR(128),
  p_new_status verification_status,
  p_reason VARCHAR(700) DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF current_actor_id() <> p_admin_id OR NOT current_actor_is_admin() THEN
    RAISE EXCEPTION 'Accès administrateur requis.';
  END IF;
  IF p_new_status = 'pending' THEN
    RAISE EXCEPTION 'Une décision finale est requise.';
  END IF;
  IF p_new_status = 'rejected' AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'Un motif de refus est requis.';
  END IF;

  UPDATE mobile_clinics
  SET verification_status = p_new_status,
      rejection_reason = CASE WHEN p_new_status = 'rejected' THEN btrim(p_reason) ELSE '' END,
      certification_badge = CASE
        WHEN p_new_status = 'approved' THEN 'Clinique Mobile Certifiée I-Entier'
        ELSE ''
      END,
      certified_at = CASE WHEN p_new_status = 'approved' THEN CURRENT_TIMESTAMP ELSE NULL END,
      reviewed_by = p_admin_id,
      reviewed_at = CURRENT_TIMESTAMP,
      is_published = p_new_status = 'approved',
      is_deployed = CASE WHEN p_new_status = 'approved' THEN is_deployed ELSE FALSE END
  WHERE mobile_clinic_id = p_mobile_clinic_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Clinique mobile introuvable.'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION book_mobile_clinic_appointment(
  p_mobile_clinic_id UUID,
  p_tour_id UUID,
  p_service_id UUID,
  p_patient_name VARCHAR(140),
  p_scheduled_at TIMESTAMPTZ,
  p_patient_note VARCHAR(500) DEFAULT '',
  p_payment_method appointment_payment_method DEFAULT 'cash'
)
RETURNS VARCHAR(160)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  clinic mobile_clinics%ROWTYPE;
  tour mobile_clinic_tours%ROWTYPE;
  service mobile_clinic_services%ROWTYPE;
  actor_id VARCHAR(128) := current_actor_id();
  result_id VARCHAR(160) := 'mobile_clinic_' || gen_random_uuid()::TEXT;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM patient_profiles WHERE patient_id = actor_id
  ) THEN
    RAISE EXCEPTION 'Un profil patient authentifié est requis.';
  END IF;

  SELECT * INTO clinic FROM mobile_clinics
  WHERE mobile_clinic_id = p_mobile_clinic_id
    AND verification_status = 'approved'
    AND is_published = TRUE
    AND EXISTS (
      SELECT 1 FROM provider_profiles p
      WHERE p.provider_id = mobile_clinics.owner_provider_id
        AND p.verification_status = 'approved'
        AND p.is_visible = TRUE
        AND p.available = TRUE
    );
  IF NOT FOUND THEN RAISE EXCEPTION 'Cette clinique mobile n''est pas disponible.'; END IF;

  SELECT * INTO tour FROM mobile_clinic_tours
  WHERE mobile_clinic_tour_id = p_tour_id
    AND mobile_clinic_id = p_mobile_clinic_id
    AND status IN ('planned', 'active')
    AND p_scheduled_at BETWEEN starts_at AND ends_at;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cette tournée n''est pas disponible à cette date.'; END IF;

  SELECT * INTO service FROM mobile_clinic_services
  WHERE mobile_clinic_service_id = p_service_id
    AND mobile_clinic_id = p_mobile_clinic_id
    AND active = TRUE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ce service n''est pas disponible.'; END IF;

  INSERT INTO appointments (
    appointment_id, patient_id, patient_name_snapshot,
    provider_id, provider_type_snapshot, provider_name_snapshot,
    service_name_snapshot, mode, payment_method, location,
    scheduled_at, schedule_label, patient_note,
    mobile_clinic_id, mobile_clinic_tour_id
  ) VALUES (
    result_id, actor_id,
    COALESCE(NULLIF(btrim(p_patient_name), ''), 'Patient i-ENTIER'),
    clinic.owner_provider_id, clinic.owner_account_type, clinic.name,
    service.name || ' · Clinique Mobile', 'inPerson', p_payment_method,
    tour.location_label, p_scheduled_at, tour.daily_schedule,
    btrim(COALESCE(p_patient_note, '')),
    clinic.mobile_clinic_id, tour.mobile_clinic_tour_id
  );
  RETURN result_id;
END;
$$;

ALTER TABLE mobile_clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_clinic_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_clinic_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_clinic_tours ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_clinic_interventions ENABLE ROW LEVEL SECURITY;

CREATE POLICY mobile_clinics_select ON mobile_clinics FOR SELECT TO authenticated
USING (
  owner_provider_id = current_actor_id()
  OR current_actor_is_admin()
  OR (
    verification_status = 'approved'
    AND is_published = TRUE
    AND EXISTS (
      SELECT 1 FROM provider_profiles p
      WHERE p.provider_id = mobile_clinics.owner_provider_id
        AND p.verification_status = 'approved'
        AND p.is_visible = TRUE
        AND p.available = TRUE
    )
  )
);
CREATE POLICY mobile_clinics_insert ON mobile_clinics FOR INSERT TO authenticated
WITH CHECK (owner_provider_id = current_actor_id());
CREATE POLICY mobile_clinics_update ON mobile_clinics FOR UPDATE TO authenticated
USING (owner_provider_id = current_actor_id() OR current_actor_is_admin())
WITH CHECK (owner_provider_id = current_actor_id() OR current_actor_is_admin());
CREATE POLICY mobile_clinics_delete ON mobile_clinics FOR DELETE TO authenticated
USING (
  current_actor_is_admin()
  OR (owner_provider_id = current_actor_id() AND verification_status <> 'approved')
);

CREATE POLICY mobile_clinic_services_select ON mobile_clinic_services FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM mobile_clinics c
  WHERE c.mobile_clinic_id = mobile_clinic_services.mobile_clinic_id
    AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin()
      OR (c.verification_status = 'approved' AND c.is_published = TRUE))
));
CREATE POLICY mobile_clinic_services_owner_all ON mobile_clinic_services FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_services.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
)) WITH CHECK (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_services.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
));

CREATE POLICY mobile_clinic_staff_owner_all ON mobile_clinic_staff FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_staff.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
)) WITH CHECK (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_staff.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
));

CREATE POLICY mobile_clinic_tours_select ON mobile_clinic_tours FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM mobile_clinics c
  WHERE c.mobile_clinic_id = mobile_clinic_tours.mobile_clinic_id
    AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin()
      OR (c.verification_status = 'approved' AND c.is_published = TRUE
        AND mobile_clinic_tours.status IN ('planned', 'active')))
));
CREATE POLICY mobile_clinic_tours_owner_all ON mobile_clinic_tours FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_tours.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
)) WITH CHECK (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_tours.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
));

CREATE POLICY mobile_clinic_interventions_owner_all ON mobile_clinic_interventions FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_interventions.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
)) WITH CHECK (EXISTS (
  SELECT 1 FROM mobile_clinics c WHERE c.mobile_clinic_id = mobile_clinic_interventions.mobile_clinic_id
  AND (c.owner_provider_id = current_actor_id() OR current_actor_is_admin())
));

GRANT SELECT, INSERT, UPDATE, DELETE ON
  mobile_clinics,
  mobile_clinic_services,
  mobile_clinic_staff,
  mobile_clinic_tours,
  mobile_clinic_interventions
TO authenticated;
GRANT EXECUTE ON FUNCTION review_mobile_clinic(UUID, VARCHAR, verification_status, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION book_mobile_clinic_appointment(
  UUID, UUID, UUID, VARCHAR, TIMESTAMPTZ, VARCHAR, appointment_payment_method
) TO authenticated;
REVOKE EXECUTE ON FUNCTION review_mobile_clinic(
  UUID, VARCHAR, verification_status, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION book_mobile_clinic_appointment(
  UUID, UUID, UUID, VARCHAR, TIMESTAMPTZ, VARCHAR, appointment_payment_method
) FROM PUBLIC, anon;

COMMENT ON TABLE mobile_clinics IS
  'Demandes et profils certifiés du réseau national de cliniques mobiles i-ENTIER.';
COMMENT ON COLUMN mobile_clinics.certification_badge IS
  'Badge attribué automatiquement et exclusivement après validation administrative.';
COMMENT ON COLUMN appointments.mobile_clinic_id IS
  'Lie un rendez-vous communautaire à la clinique mobile certifiée qui le prend en charge.';

COMMIT;
