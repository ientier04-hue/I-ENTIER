BEGIN;
SET search_path = ientier, public;
CREATE FUNCTION pg_temp.assert_true(result boolean, message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF result IS DISTINCT FROM true THEN RAISE EXCEPTION '%', message; END IF; END $$;
CREATE FUNCTION pg_temp.expect_error(sql text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(expected IN SQLERRM) > 0 THEN RETURN; END IF;
    RAISE EXCEPTION 'Expected %, got %', expected, SQLERRM;
  END;
  RAISE EXCEPTION 'Expected failure: %', expected;
END $$;

INSERT INTO app_users(user_id) VALUES
('10000000-0000-4000-8000-000000000001'), ('10000000-0000-4000-8000-000000000002');
INSERT INTO patient_profiles(patient_id) VALUES
('10000000-0000-4000-8000-000000000001'), ('10000000-0000-4000-8000-000000000002');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claims = '{"is_anonymous": false}';
INSERT INTO cycle_personal_contexts(patient_id, life_stage, contraception, history_start)
VALUES ('10000000-0000-4000-8000-000000000001', 'menstruating', 'none', CURRENT_DATE);
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_personal_contexts) = 1, 'Owner can read');
SET LOCAL request.jwt.claims = '{"is_anonymous": true}';
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_personal_contexts) = 0, 'Anonymous session cannot read');
SELECT pg_temp.expect_error($q$INSERT INTO cycle_personal_contexts(patient_id) VALUES ('10000000-0000-4000-8000-000000000001')$q$, 'row-level security');
SET LOCAL request.jwt.claims = '{}';
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_personal_contexts) = 0, 'Missing account claim fails closed');
SET LOCAL request.jwt.claims = '{"is_anonymous": false}';
UPDATE cycle_personal_contexts SET breastfeeding = true, life_stage = 'postpartum';
SELECT pg_temp.assert_true((SELECT breastfeeding FROM cycle_personal_contexts), 'Owner can update');
SELECT pg_temp.expect_error($q$UPDATE cycle_personal_contexts SET patient_id = '10000000-0000-4000-8000-000000000002'$q$, 'row-level security');
SELECT pg_temp.expect_error($q$UPDATE cycle_personal_contexts SET life_stage = 'invalid'$q$, 'check constraint');
SELECT pg_temp.expect_error($q$UPDATE cycle_personal_contexts SET history_start = CURRENT_DATE + 1$q$, 'check constraint');
SET LOCAL request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_personal_contexts) = 0, 'Other patient cannot read');
SELECT pg_temp.expect_error($q$INSERT INTO cycle_personal_contexts(patient_id) VALUES ('10000000-0000-4000-8000-000000000001')$q$, 'row-level security');
WITH changed AS (UPDATE cycle_personal_contexts SET has_pcos = true RETURNING *)
SELECT pg_temp.assert_true((SELECT count(*) FROM changed) = 0, 'Other patient cannot update');
WITH removed AS (DELETE FROM cycle_personal_contexts RETURNING *)
SELECT pg_temp.assert_true((SELECT count(*) FROM removed) = 0, 'Other patient cannot delete');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.expect_error('SELECT * FROM cycle_personal_contexts', 'permission denied');
RESET ROLE;

-- The existing cycle entry RLS remains untouched; verify new column constraints.
INSERT INTO cycle_entries(cycle_entry_id, patient_id, entry_date, is_spotting, stress_level, sleep_hours)
VALUES ('cycle-test', '10000000-0000-4000-8000-000000000001', CURRENT_DATE, true, 2, 7.5);
SELECT pg_temp.assert_true((SELECT sleep_hours = 7.5 AND stress_level = 2 AND is_spotting FROM cycle_entries WHERE cycle_entry_id = 'cycle-test'), 'Daily observations round trip');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET is_period = true WHERE cycle_entry_id = 'cycle-test'$q$, 'cycle_bleeding_kind');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET sleep_hours = 25 WHERE cycle_entry_id = 'cycle-test'$q$, 'check constraint');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET stress_level = 4 WHERE cycle_entry_id = 'cycle-test'$q$, 'check constraint');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
DELETE FROM cycle_personal_contexts;
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_personal_contexts) = 0, 'Owner can delete');
RESET ROLE;
SELECT 'All cycle context SQL assertions passed';
ROLLBACK;
