-- Allow active i-ENTIER administrators to supervise OFATMA requests while
-- keeping the approval/rejection workflow restricted to verified professionals.

BEGIN;

CREATE POLICY medical_insurance_admin_read
ON ientier.medical_insurance_coverages
FOR SELECT TO authenticated
USING (ientier.current_actor_is_admin());

CREATE POLICY insurance_cards_admin_select
ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'insurance-cards'
  AND ientier.current_actor_is_admin()
);

COMMIT;
