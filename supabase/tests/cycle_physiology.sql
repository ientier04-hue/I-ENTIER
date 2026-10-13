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
('20000000-0000-4000-8000-000000000001'), ('20000000-0000-4000-8000-000000000002');
INSERT INTO patient_profiles(patient_id) VALUES
('20000000-0000-4000-8000-000000000001'), ('20000000-0000-4000-8000-000000000002');

SELECT pg_temp.assert_true(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'ientier.cycle_entries'::regclass),
  'Cycle entry RLS remains enabled');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '20000000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claims = '{"is_anonymous": false}';
INSERT INTO cycle_entries(cycle_entry_id, patient_id, entry_date, note)
VALUES ('physiology-defaults', '20000000-0000-4000-8000-000000000001', CURRENT_DATE - 1, 'Preserved');
SELECT pg_temp.assert_true((SELECT
  basal_temperature_c IS NULL AND NOT temperature_disturbed
  AND lh_test = '' AND cervical_mucus = '' AND note = 'Preserved'
  FROM cycle_entries WHERE cycle_entry_id = 'physiology-defaults'),
  'Entries without physiology retain unknown/default observations');

INSERT INTO cycle_entries(cycle_entry_id, patient_id, entry_date,
  basal_temperature_c, temperature_disturbed, lh_test, cervical_mucus)
VALUES ('physiology-observations', '20000000-0000-4000-8000-000000000001',
  CURRENT_DATE, 36.42, true, 'positive', 'stretchy');
SELECT pg_temp.assert_true((SELECT basal_temperature_c = 36.42 AND temperature_disturbed
  AND lh_test = 'positive' AND cervical_mucus = 'stretchy'
  FROM cycle_entries WHERE cycle_entry_id = 'physiology-observations'),
  'Owner can store and read physiology observations');

UPDATE cycle_entries SET basal_temperature_c = 34, lh_test = 'negative', cervical_mucus = 'dry'
WHERE cycle_entry_id = 'physiology-observations';
UPDATE cycle_entries SET basal_temperature_c = 42, cervical_mucus = 'sticky'
WHERE cycle_entry_id = 'physiology-observations';
UPDATE cycle_entries SET cervical_mucus = 'creamy' WHERE cycle_entry_id = 'physiology-observations';
UPDATE cycle_entries SET cervical_mucus = 'watery' WHERE cycle_entry_id = 'physiology-observations';
SELECT pg_temp.assert_true((SELECT basal_temperature_c = 42 AND lh_test = 'negative'
  AND cervical_mucus = 'watery' FROM cycle_entries WHERE cycle_entry_id = 'physiology-observations'),
  'Both inclusive temperature bounds and every documented observation are accepted');

SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET basal_temperature_c = 33.99$q$, 'cycle_basal_temperature_range');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET basal_temperature_c = 42.01$q$, 'cycle_basal_temperature_range');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET basal_temperature_c = 'NaN'::numeric$q$, 'cycle_basal_temperature_range');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET basal_temperature_c = 'Infinity'::numeric$q$, 'numeric field overflow');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET basal_temperature_c = '-Infinity'::numeric$q$, 'numeric field overflow');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET lh_test = 'invalid'$q$, 'cycle_lh_test_value');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET cervical_mucus = 'invalid'$q$, 'cycle_cervical_mucus_value');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET temperature_disturbed = NULL$q$, 'not-null constraint');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET lh_test = NULL$q$, 'not-null constraint');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET cervical_mucus = NULL$q$, 'not-null constraint');

UPDATE cycle_entries SET basal_temperature_c = NULL, temperature_disturbed = false,
  lh_test = '', cervical_mucus = '' WHERE cycle_entry_id = 'physiology-observations';
SELECT pg_temp.assert_true((SELECT basal_temperature_c IS NULL AND NOT temperature_disturbed
  AND lh_test = '' AND cervical_mucus = ''
  FROM cycle_entries WHERE cycle_entry_id = 'physiology-observations'),
  'Owner can clear every physiology observation without deleting the journal entry');
SELECT pg_temp.expect_error($q$UPDATE cycle_entries SET patient_id = '20000000-0000-4000-8000-000000000002'$q$, 'row-level security');

SET LOCAL request.jwt.claim.sub = '20000000-0000-4000-8000-000000000002';
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_entries) = 0, 'Other patient cannot read observations');
SELECT pg_temp.expect_error($q$INSERT INTO cycle_entries(patient_id, entry_date, basal_temperature_c)
  VALUES ('20000000-0000-4000-8000-000000000001', CURRENT_DATE + 1, 36.5)$q$, 'row-level security');
WITH changed AS (UPDATE cycle_entries SET basal_temperature_c = 36.7 RETURNING *)
SELECT pg_temp.assert_true((SELECT count(*) FROM changed) = 0, 'Other patient cannot change observations');
WITH removed AS (DELETE FROM cycle_entries RETURNING *)
SELECT pg_temp.assert_true((SELECT count(*) FROM removed) = 0, 'Other patient cannot delete observations');

SET LOCAL request.jwt.claim.sub = '';
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_entries) = 0, 'Missing identity cannot read observations');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.expect_error('SELECT basal_temperature_c FROM cycle_entries', 'permission denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '20000000-0000-4000-8000-000000000001';
DELETE FROM cycle_entries;
SELECT pg_temp.assert_true((SELECT count(*) FROM cycle_entries) = 0, 'Owner can delete journal entries');
RESET ROLE;
SELECT 'All cycle physiology SQL assertions passed';
ROLLBACK;
