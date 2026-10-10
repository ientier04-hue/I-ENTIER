BEGIN;

-- Anonymous sign-ins also use the authenticated role. A consultation requires
-- a permanent account in addition to being one of the two participants.
CREATE POLICY video_calls_permanent_accounts ON ientier.video_calls
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING ((SELECT (auth.jwt()->>'is_anonymous')::boolean) IS FALSE);

COMMIT;
