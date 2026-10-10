-- Run on an isolated PostgreSQL instance with the baseline and call migration.
BEGIN;
SET search_path = ientier, public;
INSERT INTO app_users(user_id) VALUES
('10000000-0000-4000-8000-000000000001'), ('10000000-0000-4000-8000-000000000002'),
('20000000-0000-4000-8000-000000000001'), ('20000000-0000-4000-8000-000000000002');
INSERT INTO patient_profiles(patient_id) VALUES ('10000000-0000-4000-8000-000000000001'), ('10000000-0000-4000-8000-000000000002');
INSERT INTO provider_profiles(provider_id, account_type, display_name, category, registration_number, phone, email, address,
 description, services_summary, schedule_summary, verification_status, is_visible, terms_accepted)
VALUES ('20000000-0000-4000-8000-000000000001', 'professional', 'Dr Test', 'Médecin', 'TEST', '12345678', 'doctor@example.test', 'Test street',
 'Test profile', 'Consultation', 'Lundi', 'approved', true, true);
INSERT INTO appointments(appointment_id, patient_id, patient_name_snapshot, provider_id, provider_type_snapshot,
 provider_name_snapshot, mode, scheduled_at, schedule_label, status, responded_at, created_at)
SELECT id, patient, 'Patient', '20000000-0000-4000-8000-000000000001', 'professional', 'Dr Test', mode::appointment_mode,
 now() + offset_time, 'Test', status::appointment_status, CASE WHEN status = 'confirmed' THEN now() END, now() - interval '1 day'
FROM (VALUES
 ('first', '10000000-0000-4000-8000-000000000001', 'video', 'confirmed', interval '0 minutes'),
 ('busy', '10000000-0000-4000-8000-000000000002', 'video', 'confirmed', interval '1 minute'),
 ('future', '10000000-0000-4000-8000-000000000001', 'video', 'confirmed', interval '1 day'),
 ('pending', '10000000-0000-4000-8000-000000000001', 'video', 'pending', interval '2 minutes'),
 ('in-person', '10000000-0000-4000-8000-000000000001', 'inPerson', 'confirmed', interval '3 minutes')
) AS data(id, patient, mode, status, offset_time);

CREATE FUNCTION pg_temp.expect_error(sql text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(expected IN SQLERRM) > 0 THEN RETURN; END IF;
    RAISE EXCEPTION 'Expected %, got %', expected, SQLERRM;
  END;
  RAISE EXCEPTION 'Expected failure: %', expected;
END $$;
CREATE FUNCTION pg_temp.assert_true(result boolean, message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF result IS DISTINCT FROM true THEN RAISE EXCEPTION '%', message; END IF; END $$;

SET LOCAL ROLE service_role;
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000002', 'start', 'first')$q$, 'not_allowed');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'future')$q$, 'outside_call_window');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'pending')$q$, 'appointment_unavailable');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'in-person')$q$, 'appointment_unavailable');
SELECT pg_temp.assert_true(ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'first')->>'status' = 'ringing', 'Invitation created');
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 1, 'One invitation');
SELECT ientier.video_call_command('20000000-0000-4000-8000-000000000001', 'start', 'first');
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 1, 'Crossed calls reuse one invitation');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000002', 'start', 'busy')$q$, 'participant_busy');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'accept', NULL, (SELECT id FROM ientier.video_calls LIMIT 1))$q$, 'not_allowed');
SELECT pg_temp.assert_true(ientier.video_call_command('20000000-0000-4000-8000-000000000001', 'accept', NULL, (SELECT id FROM ientier.video_calls LIMIT 1))->>'status' = 'accepted', 'Callee accepts');
SELECT pg_temp.assert_true(ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'join', NULL, (SELECT id FROM ientier.video_calls LIMIT 1))->>'status' = 'accepted', 'Caller joins');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000002', 'join', NULL, (SELECT id FROM ientier.video_calls LIMIT 1))$q$, 'not_allowed');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 1, 'Patient sees own call');
SET LOCAL request.jwt.claims = '{"is_anonymous": true}';
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 0, 'Anonymous session cannot read even a matching participant call');
SET LOCAL request.jwt.claims = '{}';
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 0, 'Missing permanent-account claim fails closed');
SET LOCAL request.jwt.claims = '{"is_anonymous": false}';
SELECT pg_temp.expect_error($q$UPDATE ientier.video_calls SET caller_id = 'intruder'$q$, 'permission denied');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'first')$q$, 'permission denied');
SET LOCAL request.jwt.claim.sub = '20000000-0000-4000-8000-000000000001';
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 1, 'Provider sees own call');
SET LOCAL request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls) = 0, 'Third user cannot read call');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.expect_error($q$SELECT * FROM ientier.video_calls$q$, 'permission denied');
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT pg_temp.assert_true(ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'end', NULL, (SELECT id FROM ientier.video_calls LIMIT 1))->>'status' = 'ended', 'Either participant can end');
SELECT pg_temp.assert_true(ientier.video_call_command('20000000-0000-4000-8000-000000000001', 'accept', NULL, (SELECT id FROM ientier.video_calls LIMIT 1))->>'status' = 'ended', 'Ended call cannot be revived');
SELECT pg_temp.assert_true((SELECT revision FROM ientier.video_calls LIMIT 1) >= 3, 'Monotonic revision');
SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'first');
UPDATE ientier.video_calls SET expires_at = now() - interval '1 second' WHERE status = 'ringing';
SELECT ientier.expire_video_calls();
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls WHERE status = 'missed') = 1, 'Unanswered invitation expires');
SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'first');
SELECT ientier.video_call_command('20000000-0000-4000-8000-000000000001', 'accept', NULL, (SELECT id FROM ientier.video_calls WHERE status = 'ringing'));
UPDATE ientier.video_calls SET patient_seen_at = now() - interval '2 minutes' WHERE status = 'accepted';
SELECT ientier.expire_video_calls();
SELECT pg_temp.assert_true((SELECT count(*) FROM ientier.video_calls WHERE status IN ('ringing', 'accepted')) = 0, 'Abandoned session expires');
SELECT pg_temp.expect_error($q$SELECT ientier.video_call_command('10000000-0000-4000-8000-000000000001', 'start', 'first')$q$, 'rate_limited');
RESET ROLE;

SELECT 'All video call SQL assertions passed' AS result;
ROLLBACK;
