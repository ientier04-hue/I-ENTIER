-- =============================================================================
-- i-ENTIER -- Mobilité Santé / transport sanitaire communautaire
-- =============================================================================

BEGIN;

CREATE TABLE ientier.community_transport_partner_applications (
  partner_application_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id                VARCHAR(128) NOT NULL
                              REFERENCES ientier.app_users(user_id)
                              ON DELETE CASCADE,
  driver_name                 VARCHAR(120) NOT NULL,
  contact_phone               VARCHAR(40) NOT NULL,
  department                  VARCHAR(40) NOT NULL,
  commune                     VARCHAR(100) NOT NULL,
  vehicle_type                VARCHAR(30) NOT NULL,
  vehicle_make_model          VARCHAR(120) NOT NULL,
  vehicle_year                SMALLINT NOT NULL,
  plate_number                VARCHAR(30) NOT NULL,
  road_capability             VARCHAR(30) NOT NULL DEFAULT 'standard',
  has_own_health_companion    BOOLEAN NOT NULL DEFAULT FALSE,
  companion_name              VARCHAR(120) NOT NULL DEFAULT '',
  companion_qualification     VARCHAR(180) NOT NULL DEFAULT '',
  accepts_cash                BOOLEAN NOT NULL DEFAULT TRUE,
  accepts_moncash             BOOLEAN NOT NULL DEFAULT FALSE,
  status                      VARCHAR(24) NOT NULL DEFAULT 'submitted',
  verification_status         ientier.verification_status
                              NOT NULL DEFAULT 'pending',
  review_notes                VARCHAR(1000) NOT NULL DEFAULT '',
  reviewed_by                 VARCHAR(128)
                              REFERENCES ientier.administrators(user_id)
                              ON DELETE SET NULL,
  reviewed_at                 TIMESTAMPTZ,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_transport_partner_driver
    CHECK (
      length(btrim(driver_name)) BETWEEN 2 AND 120
      AND length(btrim(contact_phone)) BETWEEN 8 AND 40
    ),
  CONSTRAINT ck_transport_partner_location
    CHECK (
      length(btrim(department)) BETWEEN 2 AND 40
      AND length(btrim(commune)) BETWEEN 2 AND 100
    ),
  CONSTRAINT ck_transport_partner_vehicle_type
    CHECK (vehicle_type IN ('car', 'suv', 'van', 'pickup', 'minibus')),
  CONSTRAINT ck_transport_partner_vehicle
    CHECK (
      length(btrim(vehicle_make_model)) BETWEEN 2 AND 120
      AND vehicle_year BETWEEN 1980 AND 2100
      AND length(btrim(plate_number)) BETWEEN 2 AND 30
    ),
  CONSTRAINT ck_transport_partner_road_capability
    CHECK (
      road_capability IN ('standard', 'high_clearance', 'four_wheel_drive')
    ),
  CONSTRAINT ck_transport_partner_companion
    CHECK (
      NOT has_own_health_companion
      OR (
        length(btrim(companion_name)) BETWEEN 2 AND 120
        AND length(btrim(companion_qualification)) BETWEEN 2 AND 180
      )
    ),
  CONSTRAINT ck_transport_partner_payment
    CHECK (accepts_cash OR accepts_moncash),
  CONSTRAINT ck_transport_partner_status
    CHECK (status IN ('submitted', 'under_review', 'active', 'suspended', 'rejected')),
  CONSTRAINT ck_transport_partner_activation
    CHECK (
      status <> 'active'
      OR (
        verification_status = 'approved'
        AND reviewed_by IS NOT NULL
        AND reviewed_at IS NOT NULL
      )
    )
);

COMMENT ON TABLE ientier.community_transport_partner_applications IS
  'Candidatures de conducteurs communautaires. Une candidature validée ne transforme pas le véhicule en ambulance médicalisée.';

CREATE INDEX idx_transport_partner_review_queue
  ON ientier.community_transport_partner_applications
  (verification_status, status, created_at);

CREATE UNIQUE INDEX uq_community_transport_active_plate
  ON ientier.community_transport_partner_applications
  (upper(btrim(plate_number)))
  WHERE status IN ('submitted', 'under_review', 'active', 'suspended');

CREATE INDEX idx_transport_partner_service_area
  ON ientier.community_transport_partner_applications
  (department, commune, road_capability)
  WHERE status = 'active' AND verification_status = 'approved';

CREATE TABLE ientier.community_transport_requests (
  transport_request_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id                VARCHAR(128) NOT NULL
                              REFERENCES ientier.app_users(user_id)
                              ON DELETE CASCADE,
  patient_display_name        VARCHAR(120) NOT NULL,
  contact_phone               VARCHAR(40) NOT NULL,
  pickup_department           VARCHAR(40) NOT NULL,
  pickup_commune              VARCHAR(100) NOT NULL,
  pickup_landmark             VARCHAR(500) NOT NULL,
  destination_name            VARCHAR(180) NOT NULL,
  destination_commune         VARCHAR(100) NOT NULL,
  care_level                  VARCHAR(30) NOT NULL,
  mobility_details            VARCHAR(500) NOT NULL DEFAULT '',
  departure_mode              VARCHAR(20) NOT NULL,
  scheduled_at                TIMESTAMPTZ,
  payment_method              VARCHAR(30) NOT NULL,
  notes                       VARCHAR(500) NOT NULL DEFAULT '',
  health_companion_required   BOOLEAN NOT NULL DEFAULT TRUE,
  status                      VARCHAR(30) NOT NULL DEFAULT 'requested',
  assigned_partner_id         UUID
                              REFERENCES ientier.community_transport_partner_applications(
                                partner_application_id
                              )
                              ON DELETE SET NULL,
  driver_name_snapshot        VARCHAR(120) NOT NULL DEFAULT '',
  vehicle_snapshot            VARCHAR(160) NOT NULL DEFAULT '',
  plate_number_snapshot       VARCHAR(30) NOT NULL DEFAULT '',
  companion_name_snapshot     VARCHAR(120) NOT NULL DEFAULT '',
  companion_role_snapshot     VARCHAR(180) NOT NULL DEFAULT '',
  quoted_amount_htg           NUMERIC(12, 2),
  accepted_at                 TIMESTAMPTZ,
  started_at                  TIMESTAMPTZ,
  completed_at                TIMESTAMPTZ,
  cancelled_at                TIMESTAMPTZ,
  cancellation_reason         VARCHAR(500) NOT NULL DEFAULT '',
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_transport_request_patient
    CHECK (
      length(btrim(patient_display_name)) BETWEEN 2 AND 120
      AND length(btrim(contact_phone)) BETWEEN 8 AND 40
    ),
  CONSTRAINT ck_transport_request_pickup
    CHECK (
      length(btrim(pickup_department)) BETWEEN 2 AND 40
      AND length(btrim(pickup_commune)) BETWEEN 2 AND 100
      AND length(btrim(pickup_landmark)) BETWEEN 3 AND 500
    ),
  CONSTRAINT ck_transport_request_destination
    CHECK (
      length(btrim(destination_name)) BETWEEN 2 AND 180
      AND length(btrim(destination_commune)) BETWEEN 2 AND 100
    ),
  CONSTRAINT ck_transport_request_care
    CHECK (care_level IN ('seated', 'assisted', 'medical_transfer')),
  CONSTRAINT ck_transport_request_departure
    CHECK (
      (departure_mode = 'now' AND scheduled_at IS NULL)
      OR (departure_mode = 'scheduled' AND scheduled_at IS NOT NULL)
    ),
  CONSTRAINT ck_transport_request_payment
    CHECK (
      payment_method IN ('cash', 'moncash', 'agreed_before_departure')
    ),
  CONSTRAINT ck_transport_request_companion_required
    CHECK (health_companion_required),
  CONSTRAINT ck_transport_request_status
    CHECK (
      status IN (
        'requested',
        'matching',
        'driver_assigned',
        'arriving',
        'in_progress',
        'completed',
        'cancelled',
        'no_match'
      )
    ),
  CONSTRAINT ck_transport_request_quote
    CHECK (quoted_amount_htg IS NULL OR quoted_amount_htg >= 0),
  CONSTRAINT ck_transport_request_assignment
    CHECK (
      status NOT IN ('driver_assigned', 'arriving', 'in_progress', 'completed')
      OR (
        assigned_partner_id IS NOT NULL
        AND length(btrim(driver_name_snapshot)) >= 2
        AND length(btrim(plate_number_snapshot)) >= 2
        AND length(btrim(companion_name_snapshot)) >= 2
        AND length(btrim(companion_role_snapshot)) >= 2
        AND quoted_amount_htg IS NOT NULL
        AND accepted_at IS NOT NULL
      )
    )
);

COMMENT ON TABLE ientier.community_transport_requests IS
  'Demandes de transport accompagné pour personnes stables; les urgences vitales sont exclues et orientées vers le CAN.';

CREATE INDEX idx_transport_request_matching
  ON ientier.community_transport_requests
  (status, pickup_department, pickup_commune, created_at)
  WHERE status IN ('requested', 'matching');

CREATE INDEX idx_transport_request_owner
  ON ientier.community_transport_requests (requester_id, created_at DESC);

CREATE INDEX idx_transport_request_partner
  ON ientier.community_transport_requests (assigned_partner_id, created_at DESC)
  WHERE assigned_partner_id IS NOT NULL;

CREATE TRIGGER trg_00_community_transport_partners_updated_at
BEFORE UPDATE ON ientier.community_transport_partner_applications
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

CREATE TRIGGER trg_00_community_transport_requests_updated_at
BEFORE UPDATE ON ientier.community_transport_requests
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

ALTER TABLE ientier.community_transport_partner_applications
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.community_transport_requests
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY transport_partner_owner_select
ON ientier.community_transport_partner_applications FOR SELECT
TO authenticated
USING (
  applicant_id = ientier.current_actor_id()
  OR ientier.current_actor_is_admin()
);

CREATE POLICY transport_partner_owner_insert
ON ientier.community_transport_partner_applications FOR INSERT
TO authenticated
WITH CHECK (
  applicant_id = ientier.current_actor_id()
  AND verification_status = 'pending'
  AND status = 'submitted'
  AND reviewed_by IS NULL
  AND reviewed_at IS NULL
);

CREATE POLICY transport_partner_admin_update
ON ientier.community_transport_partner_applications FOR UPDATE
TO authenticated
USING (ientier.current_actor_is_admin())
WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY transport_partner_admin_delete
ON ientier.community_transport_partner_applications FOR DELETE
TO authenticated
USING (ientier.current_actor_is_admin());

CREATE POLICY transport_request_participant_select
ON ientier.community_transport_requests FOR SELECT
TO authenticated
USING (
  requester_id = ientier.current_actor_id()
  OR ientier.current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM ientier.community_transport_partner_applications p
    WHERE p.partner_application_id =
          community_transport_requests.assigned_partner_id
      AND p.applicant_id = ientier.current_actor_id()
      AND p.status = 'active'
      AND p.verification_status = 'approved'
  )
);

CREATE POLICY transport_request_owner_insert
ON ientier.community_transport_requests FOR INSERT
TO authenticated
WITH CHECK (
  requester_id = ientier.current_actor_id()
  AND status = 'requested'
  AND health_companion_required
  AND assigned_partner_id IS NULL
  AND accepted_at IS NULL
  AND started_at IS NULL
  AND completed_at IS NULL
);

CREATE POLICY transport_request_owner_update_before_assignment
ON ientier.community_transport_requests FOR UPDATE
TO authenticated
USING (
  requester_id = ientier.current_actor_id()
  AND status IN ('requested', 'matching')
)
WITH CHECK (
  requester_id = ientier.current_actor_id()
  AND status IN ('requested', 'matching', 'cancelled')
);

CREATE POLICY transport_request_admin_update
ON ientier.community_transport_requests FOR UPDATE
TO authenticated
USING (ientier.current_actor_is_admin())
WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY transport_request_admin_delete
ON ientier.community_transport_requests FOR DELETE
TO authenticated
USING (ientier.current_actor_is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE
ON ientier.community_transport_partner_applications,
   ientier.community_transport_requests
TO authenticated;

GRANT ALL
ON ientier.community_transport_partner_applications,
   ientier.community_transport_requests
TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'ientier'
      AND tablename = 'community_transport_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE ientier.community_transport_requests;
  END IF;
END;
$$;

COMMIT;
