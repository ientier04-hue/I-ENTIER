BEGIN;
ALTER POLICY cycle_personal_context_owner ON ientier.cycle_personal_contexts
  USING (
    patient_id = (SELECT auth.uid())::text
    AND (SELECT auth.jwt() ->> 'is_anonymous') = 'false'
  )
  WITH CHECK (
    patient_id = (SELECT auth.uid())::text
    AND (SELECT auth.jwt() ->> 'is_anonymous') = 'false'
  );
COMMIT;
