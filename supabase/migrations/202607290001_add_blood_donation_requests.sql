-- =============================================================================
-- i-ENTIER -- demandes publiques et vérifiées de don de sang
-- =============================================================================

BEGIN;

CREATE TABLE ientier.blood_donation_requests (
  blood_request_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_display_name   VARCHAR(100) NOT NULL,
  person_age            SMALLINT,
  blood_group           VARCHAR(3) NOT NULL,
  units_needed          SMALLINT NOT NULL DEFAULT 1,
  facility_name         VARCHAR(180) NOT NULL,
  commune               VARCHAR(100) NOT NULL DEFAULT '',
  department            VARCHAR(100) NOT NULL DEFAULT '',
  reason                VARCHAR(500) NOT NULL DEFAULT '',
  contact_name          VARCHAR(120) NOT NULL,
  contact_phone         VARCHAR(40) NOT NULL,
  urgency               VARCHAR(20) NOT NULL DEFAULT 'standard',
  status                VARCHAR(20) NOT NULL DEFAULT 'draft',
  verification_status   ientier.verification_status NOT NULL DEFAULT 'pending',
  consent_to_publish    BOOLEAN NOT NULL DEFAULT FALSE,
  needed_by             TIMESTAMPTZ NOT NULL,
  expires_at            TIMESTAMPTZ NOT NULL,
  published_at          TIMESTAMPTZ,
  created_by            VARCHAR(128)
                        REFERENCES ientier.app_users(user_id)
                        ON DELETE SET NULL,
  reviewed_by           VARCHAR(128)
                        REFERENCES ientier.administrators(user_id)
                        ON DELETE SET NULL,
  reviewed_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_blood_request_name_not_blank
    CHECK (length(btrim(person_display_name)) BETWEEN 1 AND 100),
  CONSTRAINT ck_blood_request_age
    CHECK (person_age IS NULL OR person_age BETWEEN 0 AND 120),
  CONSTRAINT ck_blood_request_group
    CHECK (blood_group IN ('O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+')),
  CONSTRAINT ck_blood_request_units
    CHECK (units_needed BETWEEN 1 AND 50),
  CONSTRAINT ck_blood_request_facility_not_blank
    CHECK (length(btrim(facility_name)) BETWEEN 1 AND 180),
  CONSTRAINT ck_blood_request_contact_not_blank
    CHECK (
      length(btrim(contact_name)) BETWEEN 1 AND 120
      AND length(btrim(contact_phone)) BETWEEN 8 AND 40
    ),
  CONSTRAINT ck_blood_request_reason_length
    CHECK (length(reason) <= 500),
  CONSTRAINT ck_blood_request_urgency
    CHECK (urgency IN ('standard', 'urgent', 'critical')),
  CONSTRAINT ck_blood_request_status
    CHECK (status IN ('draft', 'active', 'fulfilled', 'expired', 'cancelled')),
  CONSTRAINT ck_blood_request_dates
    CHECK (expires_at >= needed_by),
  CONSTRAINT ck_blood_request_publication
    CHECK (
      status <> 'active'
      OR (
        verification_status = 'approved'
        AND consent_to_publish
        AND published_at IS NOT NULL
      )
    )
);

COMMENT ON TABLE ientier.blood_donation_requests IS
  'Besoins de sang à durée limitée, publiés après consentement et validation administrative.';

CREATE INDEX idx_blood_requests_public_feed
  ON ientier.blood_donation_requests
  (status, verification_status, needed_by, expires_at);

CREATE INDEX idx_blood_requests_blood_group
  ON ientier.blood_donation_requests (blood_group, needed_by)
  WHERE status = 'active' AND verification_status = 'approved';

CREATE TRIGGER trg_00_blood_donation_requests_updated_at
BEFORE UPDATE ON ientier.blood_donation_requests
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

ALTER TABLE ientier.blood_donation_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY blood_requests_verified_select
ON ientier.blood_donation_requests FOR SELECT
TO authenticated
USING (
  (
    status = 'active'
    AND verification_status = 'approved'
    AND consent_to_publish
    AND expires_at > CURRENT_TIMESTAMP
  )
  OR ientier.current_actor_is_admin()
);

CREATE POLICY blood_requests_admin_insert
ON ientier.blood_donation_requests FOR INSERT
TO authenticated
WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY blood_requests_admin_update
ON ientier.blood_donation_requests FOR UPDATE
TO authenticated
USING (ientier.current_actor_is_admin())
WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY blood_requests_admin_delete
ON ientier.blood_donation_requests FOR DELETE
TO authenticated
USING (ientier.current_actor_is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE
ON ientier.blood_donation_requests
TO authenticated;

GRANT ALL ON ientier.blood_donation_requests TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'ientier'
      AND tablename = 'blood_donation_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE ientier.blood_donation_requests;
  END IF;
END;
$$;

COMMIT;
