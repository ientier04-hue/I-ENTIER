BEGIN;

CREATE TABLE ientier.video_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id varchar(160) NOT NULL REFERENCES ientier.appointments(appointment_id) ON DELETE RESTRICT,
  patient_id varchar(128) NOT NULL REFERENCES ientier.patient_profiles(patient_id) ON DELETE RESTRICT,
  provider_id varchar(128) NOT NULL REFERENCES ientier.provider_profiles(provider_id) ON DELETE RESTRICT,
  caller_id varchar(128) NOT NULL,
  patient_name text NOT NULL,
  provider_name text NOT NULL,
  room_name text NOT NULL UNIQUE DEFAULT ('ientier-' || gen_random_uuid()::text),
  status text NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing', 'accepted', 'ended', 'declined', 'cancelled', 'missed', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '60 seconds'),
  accepted_at timestamptz,
  ended_at timestamptz,
  patient_seen_at timestamptz,
  provider_seen_at timestamptz,
  room_closed_at timestamptz,
  revision bigint NOT NULL DEFAULT 0,
  CHECK (patient_id <> provider_id AND caller_id IN (patient_id, provider_id)),
  CHECK ((status IN ('ringing', 'accepted')) = (ended_at IS NULL))
);
CREATE INDEX video_calls_patient_history ON ientier.video_calls(patient_id, created_at DESC);
CREATE INDEX video_calls_provider_history ON ientier.video_calls(provider_id, created_at DESC);
CREATE INDEX video_calls_appointment ON ientier.video_calls(appointment_id);
CREATE INDEX video_calls_caller_rate ON ientier.video_calls(caller_id, created_at DESC);
CREATE INDEX video_calls_active ON ientier.video_calls(expires_at) WHERE status IN ('ringing', 'accepted');
CREATE INDEX video_calls_cleanup ON ientier.video_calls(ended_at) WHERE room_closed_at IS NULL AND ended_at IS NOT NULL;
CREATE UNIQUE INDEX video_calls_one_per_appointment ON ientier.video_calls(appointment_id) WHERE status IN ('ringing', 'accepted');

ALTER TABLE ientier.video_calls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ientier.video_calls FROM PUBLIC, anon, authenticated;
GRANT SELECT ON ientier.video_calls TO authenticated;
GRANT ALL ON ientier.video_calls TO service_role;
CREATE POLICY video_calls_participants_read ON ientier.video_calls FOR SELECT TO authenticated
  USING ((SELECT auth.uid())::text IN (patient_id, provider_id));

CREATE FUNCTION ientier.bump_video_call_revision() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN NEW.revision := OLD.revision + 1; RETURN NEW; END;
$$;
REVOKE ALL ON FUNCTION ientier.bump_video_call_revision() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER video_calls_revision BEFORE UPDATE ON ientier.video_calls
  FOR EACH ROW EXECUTE FUNCTION ientier.bump_video_call_revision();

-- Only the authenticated Edge Function may perform transitions. This function
-- is deliberately SECURITY INVOKER, with no execute grant to client roles.
CREATE FUNCTION ientier.video_call_command(
  p_actor uuid, p_action text, p_appointment_id text DEFAULT NULL, p_call_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  actor text := p_actor::text;
  target ientier.appointments%ROWTYPE;
  call ientier.video_calls%ROWTYPE;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF p_action = 'start' THEN
    SELECT * INTO target FROM ientier.appointments WHERE appointment_id = p_appointment_id FOR SHARE;
    IF NOT FOUND OR actor NOT IN (target.patient_id, target.provider_id) THEN
      RAISE EXCEPTION 'not_allowed';
    END IF;
    IF target.patient_id = target.provider_id OR target.status <> 'confirmed' OR target.mode <> 'video' THEN
      RAISE EXCEPTION 'appointment_unavailable';
    END IF;
    IF now() < target.scheduled_at - interval '30 minutes' OR now() > target.scheduled_at + interval '4 hours' THEN
      RAISE EXCEPTION 'outside_call_window';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ientier.provider_profiles WHERE provider_id = target.provider_id AND verification_status = 'approved') THEN
      RAISE EXCEPTION 'appointment_unavailable';
    END IF;
    -- Lock both identities in a stable order, including calls across appointments.
    PERFORM pg_advisory_xact_lock(hashtextextended(least(target.patient_id, target.provider_id), 407));
    PERFORM pg_advisory_xact_lock(hashtextextended(greatest(target.patient_id, target.provider_id), 407));
  END IF;

  UPDATE ientier.video_calls SET
    status = CASE WHEN status = 'ringing' THEN 'missed' ELSE 'ended' END,
    ended_at = now()
  WHERE status IN ('ringing', 'accepted')
    AND (actor IN (patient_id, provider_id)
      OR (p_action = 'start' AND (target.patient_id IN (patient_id, provider_id) OR target.provider_id IN (patient_id, provider_id))))
    AND (expires_at <= now() OR (status = 'accepted' AND least(patient_seen_at, provider_seen_at) < now() - interval '90 seconds'));

  IF p_action = 'sync' THEN RETURN '{}'::jsonb; END IF;
  IF p_action = 'start' THEN
    SELECT * INTO call FROM ientier.video_calls
      WHERE appointment_id = target.appointment_id AND status IN ('ringing', 'accepted');
    IF FOUND THEN RETURN to_jsonb(call); END IF;
    IF EXISTS (SELECT 1 FROM ientier.video_calls WHERE status IN ('ringing', 'accepted')
      AND (target.patient_id IN (patient_id, provider_id) OR target.provider_id IN (patient_id, provider_id))) THEN
      RAISE EXCEPTION 'participant_busy';
    END IF;
    IF (SELECT count(*) FROM ientier.video_calls WHERE caller_id = actor AND created_at > now() - interval '1 minute') >= 3 THEN
      RAISE EXCEPTION 'rate_limited';
    END IF;
    INSERT INTO ientier.video_calls(appointment_id, patient_id, provider_id, caller_id, patient_name, provider_name)
      VALUES(target.appointment_id, target.patient_id, target.provider_id, actor, target.patient_name_snapshot, target.provider_name_snapshot)
      RETURNING * INTO call;
    RETURN to_jsonb(call);
  END IF;

  SELECT * INTO call FROM ientier.video_calls WHERE id = p_call_id FOR UPDATE;
  IF NOT FOUND OR actor NOT IN (call.patient_id, call.provider_id) THEN RAISE EXCEPTION 'not_allowed'; END IF;
  IF p_action IN ('accept', 'join', 'heartbeat') AND call.status IN ('ringing', 'accepted') THEN
    SELECT * INTO target FROM ientier.appointments WHERE appointment_id = call.appointment_id;
    IF target.status <> 'confirmed' OR target.mode <> 'video'
      OR NOT EXISTS (SELECT 1 FROM ientier.provider_profiles WHERE provider_id = call.provider_id AND verification_status = 'approved') THEN
      UPDATE ientier.video_calls SET status = 'cancelled', ended_at = now() WHERE id = call.id RETURNING * INTO call;
      RETURN to_jsonb(call);
    END IF;
  END IF;
  IF p_action = 'accept' THEN
    IF actor = call.caller_id THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF call.status = 'ringing' THEN
      UPDATE ientier.video_calls SET status = 'accepted', accepted_at = now(),
        expires_at = now() + interval '2 hours', patient_seen_at = now(), provider_seen_at = now()
        WHERE id = call.id RETURNING * INTO call;
    END IF;
  ELSIF p_action = 'decline' THEN
    IF actor = call.caller_id THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF call.status = 'ringing' THEN
      UPDATE ientier.video_calls SET status = 'declined', ended_at = now() WHERE id = call.id RETURNING * INTO call;
    END IF;
  ELSIF p_action IN ('end', 'fail') THEN
    IF call.status IN ('ringing', 'accepted') THEN
      UPDATE ientier.video_calls SET status = CASE WHEN p_action = 'fail' THEN 'failed'
        WHEN status = 'ringing' THEN 'cancelled' ELSE 'ended' END, ended_at = now()
        WHERE id = call.id RETURNING * INTO call;
    END IF;
  ELSIF p_action IN ('join', 'heartbeat') THEN
    IF call.status = 'accepted' THEN
      UPDATE ientier.video_calls SET
        patient_seen_at = CASE WHEN actor = patient_id THEN now() ELSE patient_seen_at END,
        provider_seen_at = CASE WHEN actor = provider_id THEN now() ELSE provider_seen_at END
        WHERE id = call.id RETURNING * INTO call;
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;
  RETURN to_jsonb(call);
END;
$$;
REVOKE ALL ON FUNCTION ientier.video_call_command(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ientier.video_call_command(uuid, text, text, uuid) TO service_role;

-- Scheduled cleanup can also expire calls after both applications have closed.
CREATE FUNCTION ientier.expire_video_calls() RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  UPDATE ientier.video_calls SET status = CASE WHEN status = 'ringing' THEN 'missed' ELSE 'ended' END, ended_at = now()
  WHERE status IN ('ringing', 'accepted') AND (expires_at <= now()
    OR (status = 'accepted' AND least(patient_seen_at, provider_seen_at) < now() - interval '90 seconds'));
$$;
REVOKE ALL ON FUNCTION ientier.expire_video_calls() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ientier.expire_video_calls() TO service_role;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.video_calls;
  END IF;
END $$;

COMMIT;
