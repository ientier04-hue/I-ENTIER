BEGIN;
SET search_path=ientier,public;
CREATE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
 IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.reject(statement text, expected text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
  IF position(expected IN SQLERRM)>0 THEN RETURN; END IF;
  RAISE EXCEPTION 'Expected %, got %',expected,SQLERRM;
 END; RAISE EXCEPTION 'Unexpected success: %',statement; END $$;
CREATE FUNCTION pg_temp.envelope() RETURNS jsonb LANGUAGE sql AS $$ SELECT
 '{"v":1,"n":"AAAAAAAAAAAAAAAA","t":"AAAAAAAAAAAAAAAAAAAAAA==","c":"YWJjZA=="}'::jsonb $$;
INSERT INTO app_users(user_id) VALUES
 ('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002'),
 ('20000000-0000-4000-8000-000000000001'),('20000000-0000-4000-8000-000000000002');
INSERT INTO patient_profiles(patient_id,blood_type,phone) VALUES
 ('10000000-0000-4000-8000-000000000001','O+','secret-phone'),('10000000-0000-4000-8000-000000000002','A+','other-phone');
INSERT INTO patient_medical_items(patient_id,item_type,label) VALUES('10000000-0000-4000-8000-000000000001','allergy','private-allergy');
INSERT INTO provider_profiles(provider_id,account_type,display_name,category,registration_number,phone,email,address,
 description,services_summary,schedule_summary,verification_status,is_visible,terms_accepted)
VALUES('20000000-0000-4000-8000-000000000001','professional','Dr Test','Médecin','TEST','12345678','doctor@example.test','Test street',
 'Test profile','Consultation','Lundi','approved',true,true);
INSERT INTO appointments(appointment_id,patient_id,patient_name_snapshot,provider_id,provider_type_snapshot,
 provider_name_snapshot,mode,scheduled_at,schedule_label,status,responded_at)
VALUES('vault-visit','10000000-0000-4000-8000-000000000001','Patient','20000000-0000-4000-8000-000000000001','professional',
 'Dr Test','video',now()+interval '1 day','Test','confirmed',now());
INSERT INTO prescriptions(prescription_id,patient_id,source,storage_path,transcription)
 VALUES('legacy-prescription','10000000-0000-4000-8000-000000000001','scan','prescriptions/patient/private.pdf','private-medication');
INSERT INTO prescription_items(prescription_id,medication_name) VALUES('legacy-prescription','private-medication');
INSERT INTO appointment_status_history(appointment_id,previous_status,new_status,changed_by,note)
 VALUES('vault-visit','pending','confirmed','20000000-0000-4000-8000-000000000001','private-note');
INSERT INTO administrators(user_id) VALUES('20000000-0000-4000-8000-000000000002');
INSERT INTO storage.objects(id,bucket_id,name) VALUES
 (gen_random_uuid(),'insurance-cards','10000000-0000-4000-8000-000000000001/front.png'),
 (gen_random_uuid(),'insurance-cards','10000000-0000-4000-8000-000000000001/back.png');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='10000000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claims='{"is_anonymous":false}';
SELECT pg_temp.reject($q$SELECT vault_activate('30000000-0000-4000-8000-000000000001',pg_temp.envelope(),'wrong','{}')$q$,'legacy_changed');
SELECT pg_temp.assert_true((SELECT blood_type='O+' FROM patient_profiles WHERE patient_id=auth.uid()::text),'failed activation preserves plaintext');
DO $$ DECLARE export jsonb; encrypted jsonb; BEGIN
 export:=vault_export_legacy();
 PERFORM pg_temp.assert_true(export->'tables'->'prescriptions'->0->>'transcription'='private-medication','legacy prescription included before scrub');
 PERFORM pg_temp.reject(format('SELECT vault_activate(%L,pg_temp.envelope(),%L,%L::jsonb)',
 '30000000-0000-4000-8000-000000000001',export->>'fingerprint','{}'),'missing_collection');
 SELECT jsonb_object_agg(key,pg_temp.envelope()) INTO encrypted FROM jsonb_each(export->'tables');
 PERFORM vault_activate('30000000-0000-4000-8000-000000000001',pg_temp.envelope(),export->>'fingerprint',encrypted);
END $$;
SELECT pg_temp.assert_true((SELECT blood_type='' AND phone='' FROM patient_profiles WHERE patient_id=auth.uid()::text),'legacy profile scrubbed');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM patient_medical_items WHERE patient_id=auth.uid()::text),'legacy medical rows removed');
SELECT pg_temp.assert_true((SELECT vault_encrypted AND transcription='' AND storage_path='' FROM prescriptions WHERE prescription_id='legacy-prescription'),'prescription reference retained without plaintext');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM prescription_items),'prescription items scrubbed');
SELECT pg_temp.assert_true((SELECT bool_and(note='') FROM appointment_status_history WHERE appointment_id='vault-visit'),'immutable history notes scrubbed');
SELECT submit_medical_insurance_coverage('Patient Test','member-123',
 '10000000-0000-4000-8000-000000000001/front.png','10000000-0000-4000-8000-000000000001/back.png','image/png','image/png');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM medical_insurance_coverages WHERE patient_id=auth.uid()::text),'insurance submission unaffected by clinical encryption');
SELECT vault_prescription_reference('new-prescription');
SELECT vault_prescription_reference('new-prescription');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM prescriptions WHERE prescription_id='new-prescription' AND vault_encrypted),'pharmacy reference registration is idempotent');
SELECT pg_temp.reject($q$INSERT INTO prescription_items(prescription_id,medication_name) VALUES('new-prescription','should-not-leak')$q$,'encrypted_vault_required');
SELECT pg_temp.assert_true((SELECT count(*)>=28 FROM vault_collections),'all encrypted collections saved');
SELECT pg_temp.reject($q$SELECT vault_export_legacy()$q$,'already_encrypted');
SELECT pg_temp.reject($q$UPDATE patient_profiles SET blood_type='AB+' WHERE patient_id=auth.uid()::text$q$,'encrypted_vault_required');
SELECT pg_temp.reject($q$UPDATE patient_vaults SET key_check='{}'$q$,'permission denied');
SELECT pg_temp.reject($q$SELECT vault_write('health_measurements',0,pg_temp.envelope())$q$,'concurrent_change');
SELECT vault_write('health_measurements',1,pg_temp.envelope());
SELECT pg_temp.assert_true((SELECT revision=2 FROM vault_collections WHERE collection='health_measurements'),'optimistic revision increases');
SELECT pg_temp.reject($q$SELECT vault_write('files',0,'{"v":1}')$q$,'invalid_envelope');
SELECT pg_temp.reject($q$SELECT vault_authorize('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','vault-visit',30,pg_temp.envelope(),pg_temp.envelope())$q$,'not_allowed');
SELECT pg_temp.reject($q$SELECT vault_authorize('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','vault-visit',9999,pg_temp.envelope(),pg_temp.envelope())$q$,'invalid_duration');
SELECT vault_authorize('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','vault-visit',30,pg_temp.envelope(),pg_temp.envelope());
SET LOCAL request.jwt.claim.sub='10000000-0000-4000-8000-000000000002';
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM patient_vaults),'another patient cannot read vault metadata');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM vault_collections),'another patient cannot read ciphertext');
SELECT pg_temp.assert_true((SELECT blood_type='A+' FROM patient_profiles WHERE patient_id=auth.uid()::text),'other patient preserved');
SELECT pg_temp.reject($q$SELECT vault_read_grant('40000000-0000-4000-8000-000000000001')$q$,'not_allowed');
SET LOCAL request.jwt.claim.sub='20000000-0000-4000-8000-000000000002';
SELECT pg_temp.assert_true(current_actor_is_admin(),'admin fixture has real admin privileges');
SELECT review_medical_insurance_coverage((SELECT coverage_id FROM medical_insurance_coverages LIMIT 1),true,'',current_date+30);
SELECT pg_temp.assert_true((SELECT bool_and(status='verified') FROM medical_insurance_coverages),'admin insurance validation remains available');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM vault_collections),'admin cannot read another patient vault');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM patient_profiles),'admin cannot read legacy clinical profiles');
SELECT pg_temp.reject($q$SELECT vault_read_grant('40000000-0000-4000-8000-000000000001')$q$,'not_allowed');
SET LOCAL request.jwt.claim.sub='20000000-0000-4000-8000-000000000001';
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM vault_grants),'provider cannot read owner key directly');
SELECT pg_temp.assert_true((vault_read_grant('40000000-0000-4000-8000-000000000001')->>'patient_id')='10000000-0000-4000-8000-000000000001','intended provider may read active grant');
SELECT pg_temp.assert_true(NOT (vault_read_grant('40000000-0000-4000-8000-000000000001') ? 'owner_key'),'read RPC never reveals wrapped owner key');
SELECT pg_temp.assert_true(NOT (vault_read_grant('40000000-0000-4000-8000-000000000001',true) ? 'payload'),'validity probes do not resend clinical snapshots');
SELECT vault_publish('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000010',pg_temp.envelope(),
 jsonb_build_object('scheduled_at',now()+interval '3 days','mode','video','location',''));
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM appointments WHERE appointment_id='followup-50000000-0000-4000-8000-000000000010' AND patient_note='' AND response_note=''),'encrypted follow-up schedules metadata only');
SELECT vault_publish('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',pg_temp.envelope());
SELECT vault_publish('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',pg_temp.envelope());
SET LOCAL request.jwt.claim.sub='10000000-0000-4000-8000-000000000001';
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM vault_inbox WHERE document_id='50000000-0000-4000-8000-000000000001'),'publication retries are idempotent');
SELECT vault_acknowledge('50000000-0000-4000-8000-000000000001');
SELECT vault_revoke('40000000-0000-4000-8000-000000000001');
SET LOCAL request.jwt.claim.sub='20000000-0000-4000-8000-000000000001';
SELECT pg_temp.reject($q$SELECT vault_read_grant('40000000-0000-4000-8000-000000000001')$q$,'not_allowed');
SELECT pg_temp.reject($q$SELECT vault_publish('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002',pg_temp.envelope())$q$,'not_allowed');
RESET ROLE;
UPDATE vault_grants SET revoked_at=NULL,created_at=now()-interval '2 hours',expires_at=now()-interval '1 hour';
SET LOCAL ROLE authenticated;
SELECT pg_temp.reject($q$SELECT vault_read_grant('40000000-0000-4000-8000-000000000001')$q$,'not_allowed');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.reject($q$SELECT vault_export_legacy()$q$,'permission denied');
SELECT pg_temp.reject($q$SELECT * FROM patient_vaults$q$,'permission denied');
RESET ROLE;
SELECT 'PASS: ownership, no recovery endpoint, atomic migration, plaintext rejection, revisions, recipient binding, expiry, revocation, encrypted inbox, idempotency and unchanged insurance validation';
ROLLBACK;
