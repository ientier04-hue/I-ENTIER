-- =============================================================================
-- i-ENTIER -- publication directe des demandes de sang par les patients
-- =============================================================================

BEGIN;

ALTER TABLE ientier.blood_donation_requests
  DROP CONSTRAINT IF EXISTS ck_blood_request_publication;

ALTER TABLE ientier.blood_donation_requests
  ADD CONSTRAINT ck_blood_request_publication
  CHECK (
    status <> 'active'
    OR (
      consent_to_publish
      AND published_at IS NOT NULL
      AND expires_at >= needed_by
    )
  );

COMMENT ON TABLE ientier.blood_donation_requests IS
  'Besoins de sang publiés par les utilisateurs, expirant à la date du besoin et modérables par l''administration.';

DROP POLICY IF EXISTS blood_requests_verified_select
  ON ientier.blood_donation_requests;

CREATE POLICY blood_requests_public_select
ON ientier.blood_donation_requests FOR SELECT
TO authenticated
USING (
  (
    status = 'active'
    AND consent_to_publish
    AND expires_at > CURRENT_TIMESTAMP
  )
  OR created_by = ientier.current_actor_id()
  OR ientier.current_actor_is_admin()
);

DROP POLICY IF EXISTS blood_requests_admin_insert
  ON ientier.blood_donation_requests;

CREATE POLICY blood_requests_user_insert
ON ientier.blood_donation_requests FOR INSERT
TO authenticated
WITH CHECK (
  ientier.current_actor_is_admin()
  OR (
    created_by = ientier.current_actor_id()
    AND status = 'active'
    AND verification_status = 'pending'
    AND consent_to_publish
    AND published_at IS NOT NULL
    AND reviewed_by IS NULL
    AND reviewed_at IS NULL
    AND expires_at > CURRENT_TIMESTAMP
  )
);

DROP INDEX IF EXISTS ientier.idx_blood_requests_blood_group;

CREATE INDEX idx_blood_requests_blood_group
  ON ientier.blood_donation_requests (blood_group, needed_by)
  WHERE status = 'active' AND consent_to_publish;

UPDATE ientier.health_service_catalog
SET external_url = NULL,
    summary = 'Consultez les besoins ou publiez une demande de sang',
    action_label = 'Voir les demandes',
    updated_at = CURRENT_TIMESTAMP
WHERE service_key = 'don-de-sang';

COMMIT;
