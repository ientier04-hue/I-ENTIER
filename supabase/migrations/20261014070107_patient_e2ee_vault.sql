BEGIN;
-- The traditional-medicine module is optional; absent legacy datasets export empty.
CREATE SCHEMA IF NOT EXISTS ientier_private;
REVOKE ALL ON SCHEMA ientier_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA ientier_private TO authenticated;

-- References used by pharmacy orders contain no clinical content.
ALTER TABLE ientier.prescriptions ADD COLUMN IF NOT EXISTS transcription text NOT NULL DEFAULT '';
ALTER TABLE ientier.prescriptions ADD COLUMN vault_encrypted boolean NOT NULL DEFAULT false;
ALTER TABLE ientier.prescriptions ADD CONSTRAINT vault_prescription_stub CHECK (
 NOT vault_encrypted OR (source='doctor' AND doctor_id IS NULL AND doctor_name_snapshot='[Chiffré]'
 AND file_name='' AND storage_path='' AND mime_type IS NULL AND file_size_bytes IS NULL
 AND issued_at IS NULL AND expires_at IS NULL AND transcription='')
);

CREATE TABLE ientier.patient_vaults (
 patient_id text PRIMARY KEY REFERENCES ientier.patient_profiles(patient_id),
 vault_id uuid NOT NULL UNIQUE, key_check jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ientier.vault_collections (
 patient_id text NOT NULL REFERENCES ientier.patient_vaults(patient_id),
 collection text NOT NULL CHECK (length(collection) BETWEEN 1 AND 80),
 payload jsonb NOT NULL, revision bigint NOT NULL DEFAULT 1 CHECK (revision>0),
 PRIMARY KEY(patient_id,collection)
);
CREATE TABLE ientier.vault_grants (
 grant_id uuid PRIMARY KEY, patient_id text NOT NULL REFERENCES ientier.patient_vaults(patient_id),
 provider_id text NOT NULL REFERENCES ientier.provider_profiles(provider_id),
 appointment_id text NOT NULL REFERENCES ientier.appointments(appointment_id),
 payload jsonb NOT NULL, owner_key jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 revoked_at timestamptz, CHECK(expires_at>created_at AND expires_at<=created_at+interval '24 hours')
);
CREATE INDEX vault_grants_patient ON ientier.vault_grants(patient_id,created_at DESC);
CREATE INDEX vault_grants_provider ON ientier.vault_grants(provider_id,expires_at);
CREATE INDEX vault_grants_appointment ON ientier.vault_grants(appointment_id);
CREATE TABLE ientier.vault_inbox (
 document_id uuid PRIMARY KEY, grant_id uuid NOT NULL REFERENCES ientier.vault_grants(grant_id),
 patient_id text NOT NULL REFERENCES ientier.patient_vaults(patient_id),
 payload jsonb NOT NULL, imported boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX vault_inbox_patient ON ientier.vault_inbox(patient_id,imported,created_at);
CREATE INDEX vault_inbox_grant ON ientier.vault_inbox(grant_id);
CREATE TABLE ientier.vault_access_events (
 event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 grant_id uuid NOT NULL REFERENCES ientier.vault_grants(grant_id),
 patient_id text NOT NULL REFERENCES ientier.patient_vaults(patient_id),
 actor_id text NOT NULL, action text NOT NULL CHECK(action IN ('authorized','read','revoked','document')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX vault_events_patient ON ientier.vault_access_events(patient_id,created_at DESC);
CREATE INDEX vault_events_grant ON ientier.vault_access_events(grant_id);

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['patient_vaults','vault_collections','vault_grants','vault_inbox','vault_access_events'] LOOP
  EXECUTE format('ALTER TABLE ientier.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON ientier.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('GRANT SELECT ON ientier.%I TO authenticated',t);
  EXECUTE format('CREATE POLICY vault_owner_read ON ientier.%I FOR SELECT TO authenticated USING(patient_id=(SELECT auth.uid())::text)',t);
 END LOOP;
END $$;

CREATE FUNCTION ientier_private.vault_assert_envelope(p jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$ BEGIN
 IF p IS NULL OR jsonb_typeof(p)<>'object' OR p->>'v' IS DISTINCT FROM '1'
 OR jsonb_typeof(p->'n') IS DISTINCT FROM 'string'
 OR jsonb_typeof(p->'c') IS DISTINCT FROM 'string'
 OR jsonb_typeof(p->'t') IS DISTINCT FROM 'string'
 OR octet_length(p::text)>33554432
 OR octet_length(decode(p->>'n','base64'))<>12
 OR octet_length(decode(p->>'t','base64'))<>16
 OR octet_length(decode(p->>'c','base64'))<1 THEN
  RAISE EXCEPTION 'invalid_envelope' USING ERRCODE='22023';
 END IF;
END $$;

CREATE FUNCTION ientier_private.vault_snapshot(actor text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb := '{}'::jsonb; rows jsonb;
BEGIN
 IF auth.uid() IS NULL OR actor<>auth.uid()::text THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.patient_profiles r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('patient_profiles',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.patient_emergency_contacts r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('patient_emergency_contacts',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.patient_medical_items r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('patient_medical_items',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.health_measurements r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('health_measurements',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.cycle_entries r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('cycle_entries',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.cycle_entry_symptoms r WHERE EXISTS (SELECT 1 FROM ientier.cycle_entries parent WHERE parent.cycle_entry_id=r.cycle_entry_id AND parent.patient_id=actor);
 result := result || jsonb_build_object('cycle_entry_symptoms',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.cycle_personal_contexts r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('cycle_personal_contexts',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.mental_health_entries r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('mental_health_entries',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.mental_health_entry_feelings r WHERE EXISTS (SELECT 1 FROM ientier.mental_health_entries parent WHERE parent.mental_health_entry_id=r.mental_health_entry_id AND parent.patient_id=actor);
 result := result || jsonb_build_object('mental_health_entry_feelings',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.laboratory_results r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('laboratory_results',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.laboratory_result_items r WHERE EXISTS (SELECT 1 FROM ientier.laboratory_results parent WHERE parent.laboratory_result_id=r.laboratory_result_id AND parent.patient_id=actor);
 result := result || jsonb_build_object('laboratory_result_items',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.preventive_care_records r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('preventive_care_records',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.preventive_care_reminders r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('preventive_care_reminders',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.prescriptions r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('prescriptions',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.prescription_items r WHERE EXISTS (SELECT 1 FROM ientier.prescriptions parent WHERE parent.prescription_id=r.prescription_id AND parent.patient_id=actor);
 result := result || jsonb_build_object('prescription_items',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.symptom_assessments r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('symptom_assessments',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.pregnancy_profiles r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('pregnancy_profiles',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.pregnancy_reminders r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('pregnancy_reminders',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.child_profiles r WHERE r.guardian_patient_id=actor;
 result := result || jsonb_build_object('child_profiles',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.child_growth_records r WHERE r.guardian_patient_id=actor;
 result := result || jsonb_build_object('child_growth_records',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.child_vaccination_records r WHERE r.guardian_patient_id=actor;
 result := result || jsonb_build_object('child_vaccination_records',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.maternal_care_connections r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('maternal_care_connections',rows);
 IF to_regclass('ientier.natural_health_journal_entries') IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.natural_health_journal_entries r WHERE r.patient_id=actor;
 ELSE rows:='[]'::jsonb; END IF;
 result := result || jsonb_build_object('natural_health_journal_entries',rows);
 IF to_regclass('ientier.traditional_prevention_recommendations') IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.traditional_prevention_recommendations r WHERE r.patient_id=actor;
 ELSE rows:='[]'::jsonb; END IF;
 result := result || jsonb_build_object('traditional_prevention_recommendations',rows);
 IF to_regclass('ientier.traditional_care_orientations') IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.traditional_care_orientations r WHERE r.patient_id=actor;
 ELSE rows:='[]'::jsonb; END IF;
 result := result || jsonb_build_object('traditional_care_orientations',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.consultation_documents r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('consultation_documents',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.laboratory_exam_requests r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('laboratory_exam_requests',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb) INTO rows FROM ientier.notifications r WHERE r.patient_id=actor;
 result := result || jsonb_build_object('notifications',rows);
 SELECT coalesce(jsonb_agg(jsonb_build_object('appointment_id',appointment_id,'patient_note',patient_note,'response_note',response_note,'cancellation_note',cancellation_note) ORDER BY appointment_id),'[]'::jsonb)
 INTO rows FROM ientier.appointments WHERE patient_id=actor;
 result:=result||jsonb_build_object('appointment_notes',rows);
 SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY to_jsonb(h)::text),'[]'::jsonb) INTO rows
 FROM ientier.appointment_status_history h JOIN ientier.appointments a USING(appointment_id) WHERE a.patient_id=actor;
 result:=result||jsonb_build_object('appointment_history',rows);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION ientier_private.vault_snapshot(text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION ientier_private.vault_export_legacy() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text; snapshot jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor) THEN RAISE EXCEPTION 'already_encrypted'; END IF;
 INSERT INTO ientier.patient_profiles(patient_id) VALUES(actor) ON CONFLICT DO NOTHING;
 snapshot:=ientier_private.vault_snapshot(actor);
 RETURN jsonb_build_object('tables',snapshot,'fingerprint',md5(snapshot::text));
END $$;

CREATE FUNCTION ientier_private.vault_activate(p_vault_id uuid,p_key_check jsonb,p_fingerprint text,p_collections jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text; snapshot jsonb; entry record;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('vault:'||actor,0));
 IF EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor) THEN RAISE EXCEPTION 'already_encrypted'; END IF;
 -- Locks prevent a concurrent legacy write between comparison and purge.
 LOCK TABLE ientier.child_growth_records IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.child_profiles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.child_vaccination_records IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.consultation_documents IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.cycle_entries IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.cycle_entry_symptoms IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.cycle_personal_contexts IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.health_measurements IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.laboratory_exam_requests IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.laboratory_result_items IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.laboratory_results IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.maternal_care_connections IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.mental_health_entries IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.mental_health_entry_feelings IN SHARE ROW EXCLUSIVE MODE;
 IF to_regclass('ientier.natural_health_journal_entries') IS NOT NULL THEN
  LOCK TABLE ientier.natural_health_journal_entries IN SHARE ROW EXCLUSIVE MODE;
 END IF;
 LOCK TABLE ientier.notifications IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.patient_emergency_contacts IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.patient_medical_items IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.patient_profiles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.pregnancy_profiles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.pregnancy_reminders IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.prescription_items IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.prescriptions IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.preventive_care_records IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.preventive_care_reminders IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE ientier.symptom_assessments IN SHARE ROW EXCLUSIVE MODE;
 IF to_regclass('ientier.traditional_care_orientations') IS NOT NULL THEN
  LOCK TABLE ientier.traditional_care_orientations IN SHARE ROW EXCLUSIVE MODE;
 END IF;
 IF to_regclass('ientier.traditional_prevention_recommendations') IS NOT NULL THEN
  LOCK TABLE ientier.traditional_prevention_recommendations IN SHARE ROW EXCLUSIVE MODE;
 END IF;
 LOCK TABLE ientier.appointments,ientier.appointment_status_history IN SHARE ROW EXCLUSIVE MODE;
 snapshot:=ientier_private.vault_snapshot(actor);
 IF p_fingerprint IS NULL OR md5(snapshot::text)<>p_fingerprint THEN RAISE EXCEPTION 'legacy_changed' USING ERRCODE='40001'; END IF;
 PERFORM ientier_private.vault_assert_envelope(p_key_check);
 IF jsonb_typeof(p_collections) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid_collections'; END IF;
 FOR entry IN SELECT key FROM jsonb_each(snapshot) LOOP
  IF NOT p_collections ? entry.key THEN RAISE EXCEPTION 'missing_collection'; END IF;
 END LOOP;
 FOR entry IN SELECT key,value FROM jsonb_each(p_collections) LOOP
  PERFORM ientier_private.vault_assert_envelope(entry.value);
 END LOOP;
 -- Data is replaced only in this transaction after the client has verified its encryption.
 DELETE FROM ientier.laboratory_exam_requests r WHERE r.patient_id=actor;
 DELETE FROM ientier.consultation_documents r WHERE r.patient_id=actor;
 DELETE FROM ientier.notifications r WHERE r.patient_id=actor;
 DELETE FROM ientier.maternal_care_connections r WHERE r.patient_id=actor;
 DELETE FROM ientier.cycle_entry_symptoms r WHERE EXISTS (SELECT 1 FROM ientier.cycle_entries parent WHERE parent.cycle_entry_id=r.cycle_entry_id AND parent.patient_id=actor);
 DELETE FROM ientier.mental_health_entry_feelings r WHERE EXISTS (SELECT 1 FROM ientier.mental_health_entries parent WHERE parent.mental_health_entry_id=r.mental_health_entry_id AND parent.patient_id=actor);
 DELETE FROM ientier.prescription_items r WHERE EXISTS (SELECT 1 FROM ientier.prescriptions parent WHERE parent.prescription_id=r.prescription_id AND parent.patient_id=actor);
 DELETE FROM ientier.laboratory_result_items r WHERE EXISTS (SELECT 1 FROM ientier.laboratory_results parent WHERE parent.laboratory_result_id=r.laboratory_result_id AND parent.patient_id=actor);
 DELETE FROM ientier.pregnancy_reminders r WHERE r.patient_id=actor;
 DELETE FROM ientier.child_growth_records r WHERE r.guardian_patient_id=actor;
 DELETE FROM ientier.child_vaccination_records r WHERE r.guardian_patient_id=actor;
 DELETE FROM ientier.patient_emergency_contacts r WHERE r.patient_id=actor;
 DELETE FROM ientier.patient_medical_items r WHERE r.patient_id=actor;
 DELETE FROM ientier.health_measurements r WHERE r.patient_id=actor;
 DELETE FROM ientier.cycle_entries r WHERE r.patient_id=actor;
 DELETE FROM ientier.cycle_personal_contexts r WHERE r.patient_id=actor;
 DELETE FROM ientier.mental_health_entries r WHERE r.patient_id=actor;
 DELETE FROM ientier.laboratory_results r WHERE r.patient_id=actor;
 DELETE FROM ientier.preventive_care_records r WHERE r.patient_id=actor;
 DELETE FROM ientier.preventive_care_reminders r WHERE r.patient_id=actor;
 PERFORM set_config('ientier.vault_migration','scrub',true);
 UPDATE ientier.prescriptions SET vault_encrypted=true,source='doctor',doctor_id=NULL,doctor_name_snapshot='[Chiffré]',
 file_name='',storage_path='',mime_type=NULL,file_size_bytes=NULL,issued_at=NULL,expires_at=NULL,transcription=''
 WHERE patient_id=actor;
 PERFORM set_config('ientier.vault_migration','',true);
 DELETE FROM ientier.symptom_assessments r WHERE r.patient_id=actor;
 DELETE FROM ientier.pregnancy_profiles r WHERE r.patient_id=actor;
 DELETE FROM ientier.child_profiles r WHERE r.guardian_patient_id=actor;
 IF to_regclass('ientier.natural_health_journal_entries') IS NOT NULL THEN
  DELETE FROM ientier.natural_health_journal_entries r WHERE r.patient_id=actor;
 END IF;
 IF to_regclass('ientier.traditional_prevention_recommendations') IS NOT NULL THEN
  DELETE FROM ientier.traditional_prevention_recommendations r WHERE r.patient_id=actor;
 END IF;
 IF to_regclass('ientier.traditional_care_orientations') IS NOT NULL THEN
  DELETE FROM ientier.traditional_care_orientations r WHERE r.patient_id=actor;
 END IF;
 UPDATE ientier.patient_profiles SET sex=NULL,birth_date=NULL,weight_kg=NULL,height_cm=NULL,
 phone='',address='',blood_type='',special_needs='',pregnancy_status='',primary_doctor='',insurance='',profile_complete=false
 WHERE patient_id=actor;
 PERFORM set_config('ientier.vault_migration','scrub',true);
 UPDATE ientier.appointments SET patient_note='',response_note='',cancellation_note='' WHERE patient_id=actor;
 UPDATE ientier.appointment_status_history h SET note='' FROM ientier.appointments a WHERE a.appointment_id=h.appointment_id AND a.patient_id=actor;
 PERFORM set_config('ientier.vault_migration','',true);
 IF to_regclass('ientier.natural_health_sharing_grants') IS NOT NULL THEN
  UPDATE ientier.natural_health_sharing_grants SET revoked_at=now() WHERE patient_id=actor AND revoked_at IS NULL;
 END IF;
 INSERT INTO ientier.patient_vaults(patient_id,vault_id,key_check) VALUES(actor,p_vault_id,p_key_check);
 INSERT INTO ientier.vault_collections(patient_id,collection,payload)
 SELECT actor,key,value FROM jsonb_each(p_collections);
END $$;

-- No medical text or file is accepted by this compatibility endpoint.
CREATE FUNCTION ientier_private.vault_prescription_reference(p_prescription_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor)
 OR p_prescription_id IS NULL OR length(p_prescription_id) NOT BETWEEN 1 AND 160
 THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 INSERT INTO ientier.prescriptions(prescription_id,patient_id,source,doctor_name_snapshot,vault_encrypted)
 VALUES(p_prescription_id,actor,'doctor','[Chiffré]',true) ON CONFLICT DO NOTHING;
 IF NOT EXISTS(SELECT 1 FROM ientier.prescriptions WHERE prescription_id=p_prescription_id AND patient_id=actor AND vault_encrypted AND status='available')
 THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
END $$;
REVOKE ALL ON FUNCTION ientier_private.vault_prescription_reference(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_prescription_reference(text) TO authenticated;
CREATE FUNCTION ientier.vault_prescription_reference(p_prescription_id text) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_prescription_reference(p_prescription_id); $$;
REVOKE ALL ON FUNCTION ientier.vault_prescription_reference(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_prescription_reference(text) TO authenticated;

-- Preserve immutable audit fields while allowing only the atomic vault migration
-- to erase clinical plaintext. Invoker identity is essential here.
CREATE FUNCTION ientier_private.vault_legacy_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ BEGIN
 IF TG_OP='UPDATE' AND current_setting('ientier.vault_migration',true)='scrub'
 AND current_user=pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid='ientier_private.vault_activate(uuid,jsonb,text,jsonb)'::regprocedure)) THEN
  IF TG_TABLE_NAME='prescriptions' THEN
   IF NEW.patient_id=auth.uid()::text AND NEW.vault_encrypted
    AND (to_jsonb(NEW)-ARRAY['vault_encrypted','source','doctor_id','doctor_name_snapshot','file_name','storage_path','mime_type','file_size_bytes','issued_at','expires_at','transcription','updated_at'])=
        (to_jsonb(OLD)-ARRAY['vault_encrypted','source','doctor_id','doctor_name_snapshot','file_name','storage_path','mime_type','file_size_bytes','issued_at','expires_at','transcription','updated_at']) THEN RETURN NEW; END IF;
  ELSIF TG_TABLE_NAME='appointment_status_history' THEN
   IF NEW.note='' AND (to_jsonb(NEW)-'note')=(to_jsonb(OLD)-'note')
    AND EXISTS(SELECT 1 FROM ientier.appointments WHERE appointment_id=NEW.appointment_id AND patient_id=auth.uid()::text)
    THEN RETURN NEW; END IF;
  END IF;
 END IF;
 RAISE EXCEPTION 'immutable_record' USING ERRCODE='55000';
END $$;
REVOKE ALL ON FUNCTION ientier_private.vault_legacy_immutable() FROM PUBLIC,anon,authenticated;
DROP TRIGGER trg_prescriptions_immutable ON ientier.prescriptions;
CREATE TRIGGER trg_prescriptions_immutable BEFORE UPDATE ON ientier.prescriptions FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_legacy_immutable();
DROP TRIGGER trg_appointment_history_immutable ON ientier.appointment_status_history;
CREATE TRIGGER trg_appointment_history_immutable BEFORE UPDATE OR DELETE ON ientier.appointment_status_history FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_legacy_immutable();

CREATE FUNCTION ientier_private.vault_write(p_collection text,p_expected_revision bigint,p_payload jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text; rev bigint;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor) THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('vault-write:'||actor||':'||p_collection,0));
 PERFORM ientier_private.vault_assert_envelope(p_payload);
 SELECT revision INTO rev FROM ientier.vault_collections WHERE patient_id=actor AND collection=p_collection FOR UPDATE;
 IF p_expected_revision IS NULL OR coalesce(rev,0)<>p_expected_revision THEN RAISE EXCEPTION 'concurrent_change' USING ERRCODE='40001'; END IF;
 INSERT INTO ientier.vault_collections(patient_id,collection,payload,revision) VALUES(actor,p_collection,p_payload,1)
 ON CONFLICT(patient_id,collection) DO UPDATE SET payload=excluded.payload,revision=ientier.vault_collections.revision+1;
END $$;

CREATE FUNCTION ientier_private.vault_authorize(p_grant_id uuid,p_provider_id text,p_appointment_id text,p_minutes integer,p_payload jsonb,p_owner_key jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text;
BEGIN
 IF actor IS NULL OR (auth.jwt()->>'is_anonymous') IS DISTINCT FROM 'false'
 OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor)
 OR NOT EXISTS(SELECT 1 FROM ientier.appointments a JOIN ientier.provider_profiles p ON p.provider_id=a.provider_id
 WHERE a.patient_id=actor AND a.appointment_id=p_appointment_id AND a.provider_id=p_provider_id
 AND a.status IN ('pending','confirmed') AND p.verification_status='approved')
 THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 IF p_minutes IS NULL OR p_minutes NOT IN (15,30,60,120,1440) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
 PERFORM ientier_private.vault_assert_envelope(p_payload);
 PERFORM ientier_private.vault_assert_envelope(p_owner_key);
 INSERT INTO ientier.vault_grants(grant_id,patient_id,provider_id,appointment_id,payload,owner_key,expires_at)
 VALUES(p_grant_id,actor,p_provider_id,p_appointment_id,p_payload,p_owner_key,now()+make_interval(mins=>p_minutes));
 INSERT INTO ientier.vault_access_events(grant_id,patient_id,actor_id,action) VALUES(p_grant_id,actor,actor,'authorized');
END $$;

CREATE FUNCTION ientier_private.vault_read_grant(p_grant_id uuid,p_probe boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text; g ientier.vault_grants;
BEGIN
 SELECT * INTO g FROM ientier.vault_grants WHERE grant_id=p_grant_id FOR SHARE;
 IF actor IS NULL OR g.provider_id IS DISTINCT FROM actor OR g.revoked_at IS NOT NULL OR g.expires_at<=clock_timestamp()
 OR NOT EXISTS(SELECT 1 FROM ientier.provider_profiles WHERE provider_id=actor AND verification_status='approved')
 THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 IF p_probe IS NOT TRUE THEN INSERT INTO ientier.vault_access_events(grant_id,patient_id,actor_id,action) VALUES(g.grant_id,g.patient_id,actor,'read'); END IF;
 RETURN jsonb_build_object('grant_id',g.grant_id,'patient_id',g.patient_id,'provider_id',g.provider_id,
 'appointment_id',g.appointment_id,
 'provider_name',(SELECT display_name FROM ientier.provider_profiles WHERE provider_id=g.provider_id),
 'patient_name',(SELECT patient_name_snapshot FROM ientier.appointments WHERE appointment_id=g.appointment_id),'expires_at',g.expires_at,'server_time',clock_timestamp())
 || CASE WHEN p_probe IS TRUE THEN '{}'::jsonb ELSE jsonb_build_object('payload',g.payload) END;
END $$;

CREATE FUNCTION ientier_private.vault_revoke(p_grant_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 UPDATE ientier.vault_grants SET revoked_at=now() WHERE grant_id=p_grant_id AND patient_id=actor AND revoked_at IS NULL;
 IF FOUND THEN INSERT INTO ientier.vault_access_events(grant_id,patient_id,actor_id,action) VALUES(p_grant_id,actor,actor,'revoked'); END IF;
END $$;

CREATE FUNCTION ientier_private.vault_publish(p_grant_id uuid,p_document_id uuid,p_payload jsonb,p_followup jsonb DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text:=auth.uid()::text; g ientier.vault_grants; existing ientier.vault_inbox; a ientier.appointments; dt timestamptz; mode ientier.appointment_mode;
BEGIN
 SELECT * INTO g FROM ientier.vault_grants WHERE grant_id=p_grant_id FOR SHARE;
 IF actor IS NULL OR g.provider_id IS DISTINCT FROM actor OR g.revoked_at IS NOT NULL OR g.expires_at<=clock_timestamp()
 OR NOT EXISTS(SELECT 1 FROM ientier.provider_profiles WHERE provider_id=actor AND verification_status='approved')
 THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 PERFORM ientier_private.vault_assert_envelope(p_payload);
 PERFORM pg_advisory_xact_lock(hashtextextended('vault-document:'||p_document_id::text,0));
 SELECT * INTO existing FROM ientier.vault_inbox WHERE document_id=p_document_id;
 IF FOUND THEN
  IF existing.grant_id<>p_grant_id OR existing.payload<>p_payload THEN RAISE EXCEPTION 'request_conflict'; END IF;
  RETURN;
 END IF;
 IF p_followup IS NOT NULL THEN
  dt:=(p_followup->>'scheduled_at')::timestamptz; mode:=(p_followup->>'mode')::ientier.appointment_mode;
  IF dt IS NULL OR mode IS NULL OR dt<=now()+interval '30 minutes' OR dt>=now()+interval '365 days'
   OR length(coalesce(p_followup->>'location',''))>300
   OR (mode='homeVisit' AND length(btrim(coalesce(p_followup->>'location','')))<4)
  THEN RAISE EXCEPTION 'invalid_followup' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('provider-slot:'||actor,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('patient-slot:'||g.patient_id,0));
  IF EXISTS(SELECT 1 FROM ientier.appointments WHERE (provider_id=actor OR patient_id=g.patient_id)
   AND status IN ('pending','confirmed') AND scheduled_at>dt-interval '30 minutes' AND scheduled_at<dt+interval '30 minutes')
  THEN RAISE EXCEPTION 'slot_unavailable' USING ERRCODE='23505'; END IF;
  SELECT * INTO a FROM ientier.appointments WHERE appointment_id=g.appointment_id;
  INSERT INTO ientier.appointments(appointment_id,patient_id,patient_name_snapshot,provider_id,provider_type_snapshot,
   provider_name_snapshot,service_id,service_name_snapshot,mode,location,scheduled_at,schedule_label,status,responded_at,payment_method)
  VALUES('followup-'||p_document_id::text,g.patient_id,a.patient_name_snapshot,actor,a.provider_type_snapshot,
   a.provider_name_snapshot,a.service_id,a.service_name_snapshot,mode,coalesce(p_followup->>'location',''),dt,
   to_char(dt AT TIME ZONE 'America/Port-au-Prince','DD/MM/YYYY HH24:MI'),'confirmed',now(),a.payment_method);
 END IF;
 INSERT INTO ientier.vault_inbox(document_id,grant_id,patient_id,payload) VALUES(p_document_id,p_grant_id,g.patient_id,p_payload);
 INSERT INTO ientier.vault_access_events(grant_id,patient_id,actor_id,action) VALUES(p_grant_id,g.patient_id,actor,'document');
END $$;

CREATE FUNCTION ientier_private.vault_acknowledge(p_document_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
 UPDATE ientier.vault_inbox SET imported=true WHERE document_id=p_document_id AND patient_id=auth.uid()::text;
END $$;

REVOKE ALL ON FUNCTION ientier_private.vault_export_legacy() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_export_legacy() TO authenticated;
CREATE FUNCTION ientier.vault_export_legacy() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_export_legacy(); $$;
REVOKE ALL ON FUNCTION ientier.vault_export_legacy() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_export_legacy() TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_activate(uuid,jsonb,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_activate(uuid,jsonb,text,jsonb) TO authenticated;
CREATE FUNCTION ientier.vault_activate(p_vault_id uuid,p_key_check jsonb,p_fingerprint text,p_collections jsonb) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_activate(p_vault_id,p_key_check,p_fingerprint,p_collections); $$;
REVOKE ALL ON FUNCTION ientier.vault_activate(uuid,jsonb,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_activate(uuid,jsonb,text,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_write(text,bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_write(text,bigint,jsonb) TO authenticated;
CREATE FUNCTION ientier.vault_write(p_collection text,p_expected_revision bigint,p_payload jsonb) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_write(p_collection,p_expected_revision,p_payload); $$;
REVOKE ALL ON FUNCTION ientier.vault_write(text,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_write(text,bigint,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_authorize(uuid,text,text,integer,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_authorize(uuid,text,text,integer,jsonb,jsonb) TO authenticated;
CREATE FUNCTION ientier.vault_authorize(p_grant_id uuid,p_provider_id text,p_appointment_id text,p_minutes integer,p_payload jsonb,p_owner_key jsonb) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_authorize(p_grant_id,p_provider_id,p_appointment_id,p_minutes,p_payload,p_owner_key); $$;
REVOKE ALL ON FUNCTION ientier.vault_authorize(uuid,text,text,integer,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_authorize(uuid,text,text,integer,jsonb,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_read_grant(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_read_grant(uuid,boolean) TO authenticated;
CREATE FUNCTION ientier.vault_read_grant(p_grant_id uuid,p_probe boolean DEFAULT false) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_read_grant(p_grant_id,p_probe); $$;
REVOKE ALL ON FUNCTION ientier.vault_read_grant(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_read_grant(uuid,boolean) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_revoke(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_revoke(uuid) TO authenticated;
CREATE FUNCTION ientier.vault_revoke(p_grant_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_revoke(p_grant_id); $$;
REVOKE ALL ON FUNCTION ientier.vault_revoke(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_revoke(uuid) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_publish(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_publish(uuid,uuid,jsonb,jsonb) TO authenticated;
CREATE FUNCTION ientier.vault_publish(p_grant_id uuid,p_document_id uuid,p_payload jsonb,p_followup jsonb DEFAULT NULL) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_publish(p_grant_id,p_document_id,p_payload,p_followup); $$;
REVOKE ALL ON FUNCTION ientier.vault_publish(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_publish(uuid,uuid,jsonb,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_acknowledge(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ientier_private.vault_acknowledge(uuid) TO authenticated;
CREATE FUNCTION ientier.vault_acknowledge(p_document_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT ientier_private.vault_acknowledge(p_document_id); $$;
REVOKE ALL ON FUNCTION ientier.vault_acknowledge(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.vault_acknowledge(uuid) TO authenticated;

REVOKE ALL ON FUNCTION ientier_private.vault_assert_envelope(jsonb) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION ientier_private.vault_block_plaintext() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor text; parent_name text; parent_key text;
BEGIN
 actor:=coalesce(to_jsonb(NEW)->>'patient_id',to_jsonb(NEW)->>'guardian_patient_id');
 IF actor IS NULL AND TG_NARGS=2 THEN
  EXECUTE format('SELECT patient_id FROM ientier.%I WHERE %I::text=$1',TG_ARGV[0],TG_ARGV[1])
   INTO actor USING to_jsonb(NEW)->>TG_ARGV[1];
 END IF;
 IF EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor) THEN
  IF TG_TABLE_NAME='prescriptions' THEN
   IF NEW.vault_encrypted THEN RETURN NEW; END IF; -- CHECK constraint enforces the empty stub.
  END IF;
  IF TG_TABLE_NAME='notifications' THEN
   NEW.title:='i-ENTIER'; NEW.message:='Une mise à jour est disponible.';
   NEW.action_label:=NULL; RETURN NEW;
  END IF;
  RAISE EXCEPTION 'encrypted_vault_required' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ientier_private.vault_block_plaintext() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.patient_profiles FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.patient_profiles AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.patient_emergency_contacts FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.patient_emergency_contacts AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.patient_medical_items FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.patient_medical_items AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.health_measurements FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.health_measurements AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.cycle_entries FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.cycle_entries AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.cycle_entry_symptoms FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext('cycle_entries','cycle_entry_id');
CREATE POLICY vault_legacy_owner_only ON ientier.cycle_entry_symptoms AS RESTRICTIVE FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM ientier.cycle_entries parent WHERE parent.cycle_entry_id=cycle_entry_symptoms.cycle_entry_id AND parent.patient_id=(SELECT auth.uid())::text)) WITH CHECK(EXISTS(SELECT 1 FROM ientier.cycle_entries parent WHERE parent.cycle_entry_id=cycle_entry_symptoms.cycle_entry_id AND parent.patient_id=(SELECT auth.uid())::text));
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.cycle_personal_contexts FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.cycle_personal_contexts AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.mental_health_entries FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.mental_health_entries AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.mental_health_entry_feelings FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext('mental_health_entries','mental_health_entry_id');
CREATE POLICY vault_legacy_owner_only ON ientier.mental_health_entry_feelings AS RESTRICTIVE FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM ientier.mental_health_entries parent WHERE parent.mental_health_entry_id=mental_health_entry_feelings.mental_health_entry_id AND parent.patient_id=(SELECT auth.uid())::text)) WITH CHECK(EXISTS(SELECT 1 FROM ientier.mental_health_entries parent WHERE parent.mental_health_entry_id=mental_health_entry_feelings.mental_health_entry_id AND parent.patient_id=(SELECT auth.uid())::text));
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.laboratory_results FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.laboratory_results AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.laboratory_result_items FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext('laboratory_results','laboratory_result_id');
CREATE POLICY vault_legacy_owner_only ON ientier.laboratory_result_items AS RESTRICTIVE FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM ientier.laboratory_results parent WHERE parent.laboratory_result_id=laboratory_result_items.laboratory_result_id AND parent.patient_id=(SELECT auth.uid())::text)) WITH CHECK(EXISTS(SELECT 1 FROM ientier.laboratory_results parent WHERE parent.laboratory_result_id=laboratory_result_items.laboratory_result_id AND parent.patient_id=(SELECT auth.uid())::text));
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.preventive_care_records FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.preventive_care_records AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.preventive_care_reminders FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.preventive_care_reminders AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.prescriptions FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.prescriptions AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.prescription_items FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext('prescriptions','prescription_id');
CREATE POLICY vault_legacy_owner_only ON ientier.prescription_items AS RESTRICTIVE FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM ientier.prescriptions parent WHERE parent.prescription_id=prescription_items.prescription_id AND parent.patient_id=(SELECT auth.uid())::text)) WITH CHECK(EXISTS(SELECT 1 FROM ientier.prescriptions parent WHERE parent.prescription_id=prescription_items.prescription_id AND parent.patient_id=(SELECT auth.uid())::text));
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.symptom_assessments FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.symptom_assessments AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.pregnancy_profiles FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.pregnancy_profiles AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.pregnancy_reminders FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.pregnancy_reminders AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.child_profiles FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.child_profiles AS RESTRICTIVE FOR ALL TO authenticated USING(guardian_patient_id=(SELECT auth.uid())::text) WITH CHECK(guardian_patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.child_growth_records FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.child_growth_records AS RESTRICTIVE FOR ALL TO authenticated USING(guardian_patient_id=(SELECT auth.uid())::text) WITH CHECK(guardian_patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.child_vaccination_records FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.child_vaccination_records AS RESTRICTIVE FOR ALL TO authenticated USING(guardian_patient_id=(SELECT auth.uid())::text) WITH CHECK(guardian_patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.maternal_care_connections FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.maternal_care_connections AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
DO $optional$ BEGIN
 IF to_regclass('ientier.natural_health_journal_entries') IS NOT NULL THEN
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.natural_health_journal_entries FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.natural_health_journal_entries AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
 END IF;
END $optional$;
DO $optional$ BEGIN
 IF to_regclass('ientier.traditional_prevention_recommendations') IS NOT NULL THEN
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.traditional_prevention_recommendations FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.traditional_prevention_recommendations AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
 END IF;
END $optional$;
DO $optional$ BEGIN
 IF to_regclass('ientier.traditional_care_orientations') IS NOT NULL THEN
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.traditional_care_orientations FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.traditional_care_orientations AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
 END IF;
END $optional$;
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.consultation_documents FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.consultation_documents AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.laboratory_exam_requests FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.laboratory_exam_requests AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);
CREATE TRIGGER vault_no_plaintext BEFORE INSERT OR UPDATE ON ientier.notifications FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_block_plaintext();
CREATE POLICY vault_legacy_owner_only ON ientier.notifications AS RESTRICTIVE FOR ALL TO authenticated USING(patient_id=(SELECT auth.uid())::text) WITH CHECK(patient_id=(SELECT auth.uid())::text);

SET LOCAL search_path=ientier,pg_temp;
DO $migration$
DECLARE definition text;
BEGIN
 definition:=pg_get_functiondef('ientier.validate_appointment()'::regprocedure);
 definition:=replace(definition,E'BEGIN\n',E'BEGIN\n  IF current_setting(''ientier.vault_migration'',true)=''scrub''\n    AND current_user=pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=''ientier_private.vault_activate(uuid,jsonb,text,jsonb)''::regprocedure))\n    AND TG_OP=''UPDATE'' AND NEW.patient_id=auth.uid()::text\n    AND (to_jsonb(NEW)-ARRAY[''patient_note'',''response_note'',''cancellation_note'',''updated_at''])=(to_jsonb(OLD)-ARRAY[''patient_note'',''response_note'',''cancellation_note'',''updated_at''])\n    AND NEW.patient_note='''' AND NEW.response_note='''' AND NEW.cancellation_note=''''\n  THEN RETURN NEW; END IF;\n');
 EXECUTE definition;
END $migration$;
ALTER FUNCTION ientier_private.vault_publish(uuid,uuid,jsonb,jsonb) SET search_path=ientier,pg_temp;
ALTER FUNCTION ientier.validate_appointment() SET search_path=ientier,pg_temp;
ALTER FUNCTION ientier_private.vault_activate(uuid,jsonb,text,jsonb) SET search_path=ientier,pg_temp;
CREATE FUNCTION ientier_private.vault_guard_appointment_notes() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=NEW.patient_id) AND
   (NEW.patient_note NOT IN ('','[Chiffré]') OR NEW.response_note NOT IN ('','[Chiffré]') OR NEW.cancellation_note NOT IN ('','[Chiffré]'))
 THEN RAISE EXCEPTION 'encrypted_vault_required' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ientier_private.vault_guard_appointment_notes() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER vault_guard_notes BEFORE INSERT OR UPDATE ON ientier.appointments
 FOR EACH ROW EXECUTE FUNCTION ientier_private.vault_guard_appointment_notes();
CREATE POLICY vault_storage_insert ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK(bucket_id<>'prescriptions' OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=(SELECT auth.uid())::text));
CREATE POLICY vault_storage_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(bucket_id<>'prescriptions' OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=(SELECT auth.uid())::text))
 WITH CHECK(bucket_id<>'prescriptions' OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=(SELECT auth.uid())::text));

DO $optional$ BEGIN
 IF to_regclass('ientier.natural_health_sharing_grants') IS NOT NULL THEN
CREATE POLICY vault_no_permanent_sharing ON ientier.natural_health_sharing_grants AS RESTRICTIVE FOR ALL TO authenticated
 USING (patient_id=(SELECT auth.uid())::text)
 WITH CHECK (revoked_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=(SELECT auth.uid())::text));
 END IF;
END $optional$;

-- Insurance retains its own workflow; the legacy clinical profile is no longer updated.
CREATE OR REPLACE FUNCTION ientier.submit_medical_insurance_coverage(
  p_patient_name VARCHAR,
  p_member_number VARCHAR,
  p_card_front_path TEXT,
  p_card_back_path TEXT,
  p_card_front_mime_type VARCHAR,
  p_card_back_mime_type VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := ientier.current_actor_id();
  new_id UUID;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Une session patient authentifiée est requise.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ientier.patient_profiles WHERE patient_id = actor_id
  ) THEN
    RAISE EXCEPTION 'Un profil patient complet est requis.';
  END IF;
  IF length(btrim(COALESCE(p_patient_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Le nom du patient est requis.';
  END IF;
  IF split_part(p_card_front_path, '/', 1) <> actor_id
     OR split_part(p_card_back_path, '/', 1) <> actor_id THEN
    RAISE EXCEPTION 'Chemin de carte d''assurance invalide.';
  END IF;
  IF p_card_front_path = p_card_back_path THEN
    RAISE EXCEPTION 'Le recto et le verso doivent être deux images distinctes.';
  END IF;
  IF p_card_front_mime_type NOT IN ('image/jpeg','image/png','image/webp')
     OR p_card_back_mime_type NOT IN ('image/jpeg','image/png','image/webp') THEN
    RAISE EXCEPTION 'Format de carte non accepté.';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = 'insurance-cards' AND name = p_card_front_path
  ) OR NOT EXISTS (
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = 'insurance-cards' AND name = p_card_back_path
  ) THEN
    RAISE EXCEPTION 'Les images recto et verso doivent être téléversées avant la soumission.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM ientier.medical_insurance_coverages c
    WHERE c.patient_id = actor_id
      AND c.insurer_code = 'OFATMA'
      AND (
        c.status = 'pending'
        OR (c.status = 'verified' AND c.valid_until >= CURRENT_DATE)
      )
  ) THEN
    RAISE EXCEPTION 'Une couverture OFATMA active ou en cours de validation existe déjà.';
  END IF;

  INSERT INTO ientier.medical_insurance_coverages (
    patient_id,
    patient_name_snapshot,
    insurer_code,
    member_number,
    card_front_path,
    card_back_path,
    card_front_mime_type,
    card_back_mime_type
  ) VALUES (
    actor_id,
    btrim(p_patient_name),
    'OFATMA',
    btrim(COALESCE(p_member_number, '')),
    p_card_front_path,
    p_card_back_path,
    p_card_front_mime_type,
    p_card_back_mime_type
  ) RETURNING coverage_id INTO new_id;

  UPDATE ientier.patient_profiles
  SET insurance = 'OFATMA'
  WHERE patient_id = actor_id
    AND NOT EXISTS(SELECT 1 FROM ientier.patient_vaults WHERE patient_id=actor_id);

  RETURN new_id;
END;
$$;

COMMIT;
