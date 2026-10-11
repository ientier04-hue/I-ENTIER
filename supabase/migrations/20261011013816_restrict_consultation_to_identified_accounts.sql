ALTER POLICY consultation_documents_participants ON ientier.consultation_documents USING (NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,false) AND (patient_id=(SELECT auth.uid())::text OR provider_id=(SELECT auth.uid())::text));

ALTER POLICY laboratory_exam_requests_participants ON ientier.laboratory_exam_requests USING (NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,false) AND (patient_id=(SELECT auth.uid())::text OR provider_id=(SELECT auth.uid())::text));

CREATE OR REPLACE FUNCTION ientier_private.publish_video_consultation(
  p_appointment_id text, p_request_id uuid, p_kind text, p_payload jsonb
) RETURNS jsonb
-- Existing appointment triggers resolve their tables in the trusted ientier
-- schema. Explicitly place pg_temp last to prevent temporary-table shadowing.
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE
  a ientier.appointments%ROWTYPE;
  provider ientier.provider_profiles%ROWTYPE;
  existing ientier.consultation_documents%ROWTYPE;
  doc ientier.consultation_documents%ROWTYPE;
  normalized jsonb := '{}'::jsonb;
  items jsonb := '[]'::jsonb;
  item jsonb;
  new_prescription text;
  new_appointment text;
  label text;
  exam_key text;
  instruction text;
  transcription text := '';
  duration integer;
  idx integer := 0;
  new_date timestamptz;
  new_mode ientier.appointment_mode;
  document_title text;
BEGIN
  IF auth.uid() IS NULL OR COALESCE((auth.jwt()->>'is_anonymous')::boolean,false) THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
  IF p_request_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('diagnosis','prescription','exams','followup')
     OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' OR octet_length(p_payload::text) > 64000 THEN
    RAISE EXCEPTION 'invalid_payload' USING ERRCODE='22023';
  END IF;
  SELECT * INTO a FROM ientier.appointments
  WHERE appointment_id=p_appointment_id AND provider_id=auth.uid()::text
    AND mode='video' AND status='confirmed' AND NOT provider_hidden FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501'; END IF;
  SELECT * INTO provider FROM ientier.provider_profiles WHERE provider_id=a.provider_id;
  IF provider.verification_status <> 'approved' THEN
    RAISE EXCEPTION 'provider_not_approved' USING ERRCODE='42501';
  END IF;
  -- Serializes retries before creating any side effect, including notifications.
  PERFORM pg_advisory_xact_lock(hashtextextended('consultation:' || p_request_id::text, 0));
  SELECT * INTO existing FROM ientier.consultation_documents WHERE document_id=p_request_id;
  IF FOUND THEN
    IF existing.provider_id<>auth.uid()::text OR existing.appointment_id<>p_appointment_id
       OR existing.kind<>p_kind OR existing.request_fingerprint<>md5(p_payload::text) THEN
      RAISE EXCEPTION 'request_conflict' USING ERRCODE='22023';
    END IF;
    RETURN to_jsonb(existing);
  END IF;

  IF p_kind='diagnosis' THEN
    label := btrim(COALESCE(p_payload->>'diagnosis',''));
    IF length(label) NOT BETWEEN 1 AND 4000
       OR length(COALESCE(p_payload->>'symptoms',''))>4000
       OR length(COALESCE(p_payload->>'observations',''))>4000
       OR length(COALESCE(p_payload->>'plan',''))>4000 THEN
      RAISE EXCEPTION 'invalid_diagnosis' USING ERRCODE='22023';
    END IF;
    normalized := jsonb_build_object('diagnosis',label,
      'symptoms',btrim(COALESCE(p_payload->>'symptoms','')),
      'observations',btrim(COALESCE(p_payload->>'observations','')),
      'plan',btrim(COALESCE(p_payload->>'plan','')));
    document_title := 'Fiche de diagnostic';
  ELSIF p_kind='prescription' THEN
    IF jsonb_typeof(p_payload->'items') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_payload->'items') NOT BETWEEN 1 AND 20
       OR length(COALESCE(p_payload->>'notes',''))>2000 THEN
      RAISE EXCEPTION 'invalid_prescription' USING ERRCODE='22023';
    END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(p_payload->'items') LOOP
      IF jsonb_typeof(item)<>'object'
         OR length(btrim(COALESCE(item->>'medication_name',''))) NOT BETWEEN 1 AND 180
         OR length(btrim(COALESCE(item->>'dosage',''))) NOT BETWEEN 1 AND 120
         OR length(btrim(COALESCE(item->>'frequency',''))) NOT BETWEEN 1 AND 120
         OR COALESCE(item->>'duration_days','') !~ '^[0-9]{1,4}$'
         OR length(COALESCE(item->>'administration_route',''))>80
         OR length(COALESCE(item->>'instructions',''))>500 THEN
        RAISE EXCEPTION 'invalid_prescription' USING ERRCODE='22023';
      END IF;
      duration := (item->>'duration_days')::integer;
      IF duration NOT BETWEEN 1 AND 3650 THEN RAISE EXCEPTION 'invalid_prescription' USING ERRCODE='22023'; END IF;
      items := items || jsonb_build_array(jsonb_build_object(
        'medication_name',btrim(item->>'medication_name'), 'dosage',btrim(item->>'dosage'),
        'frequency',btrim(item->>'frequency'), 'duration_days',duration,
        'administration_route',btrim(COALESCE(item->>'administration_route','')),
        'instructions',btrim(COALESCE(item->>'instructions',''))));
    END LOOP;
    normalized := jsonb_build_object('items',items,'notes',btrim(COALESCE(p_payload->>'notes','')));
    FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
      transcription := transcription || format('%s — %s — %s — %s jours%s%s',
        item->>'medication_name',item->>'dosage',item->>'frequency',item->>'duration_days',
        CASE WHEN item->>'administration_route'<>'' THEN ' — ' || (item->>'administration_route') ELSE '' END,
        CASE WHEN item->>'instructions'<>'' THEN E'\n' || (item->>'instructions') ELSE '' END) || E'\n\n';
    END LOOP;
    transcription := btrim(transcription || (normalized->>'notes'));
    INSERT INTO ientier.prescriptions(patient_id,source,status,doctor_id,doctor_name_snapshot,issued_at,transcription)
    VALUES(a.patient_id,'doctor','available',a.provider_id,provider.display_name,now(),transcription)
    RETURNING prescription_id INTO new_prescription;
    FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
      INSERT INTO ientier.prescription_items(prescription_id,medication_name,dosage,frequency,duration_days,administration_route,instructions,sort_order)
      VALUES(new_prescription,item->>'medication_name',item->>'dosage',item->>'frequency',
        (item->>'duration_days')::integer,item->>'administration_route',item->>'instructions',idx);
      idx := idx+1;
    END LOOP;
    document_title := 'Ordonnance';
  ELSIF p_kind='exams' THEN
    IF jsonb_typeof(p_payload->'items') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_payload->'items') NOT BETWEEN 1 AND 20
       OR COALESCE(p_payload->>'priority','') NOT IN ('routine','urgent')
       OR length(COALESCE(p_payload->>'indication',''))>2000 THEN
      RAISE EXCEPTION 'invalid_exams' USING ERRCODE='22023';
    END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(p_payload->'items') LOOP
      exam_key := NULLIF(btrim(COALESCE(item->>'exam_id','')),'');
      label := btrim(COALESCE(item->>'name',''));
      instruction := btrim(COALESCE(item->>'instructions',''));
      IF exam_key IS NOT NULL THEN
        SELECT name INTO label FROM ientier.laboratory_exam_catalog WHERE exam_id=exam_key AND active;
        IF NOT FOUND THEN RAISE EXCEPTION 'exam_unavailable' USING ERRCODE='22023'; END IF;
      END IF;
      IF jsonb_typeof(item)<>'object' OR length(label) NOT BETWEEN 1 AND 160 OR length(instruction)>1500 THEN
        RAISE EXCEPTION 'invalid_exams' USING ERRCODE='22023';
      END IF;
      items := items || jsonb_build_array(jsonb_build_object('exam_id',exam_key,'name',label,'instructions',instruction));
    END LOOP;
    normalized := jsonb_build_object('items',items,'priority',p_payload->>'priority',
      'indication',btrim(COALESCE(p_payload->>'indication','')));
    document_title := 'Examens à réaliser';
  ELSE
    BEGIN
      new_date := (p_payload->>'scheduled_at')::timestamptz;
      new_mode := (p_payload->>'mode')::ientier.appointment_mode;
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
      RAISE EXCEPTION 'invalid_followup' USING ERRCODE='22023';
    END;
    IF new_date IS NULL OR new_mode IS NULL OR new_date<=now()+interval '30 minutes'
       OR new_date>=now()+interval '365 days'
       OR length(COALESCE(p_payload->>'location',''))>300
       OR length(COALESCE(p_payload->>'note',''))>500
       OR (new_mode='homeVisit' AND length(btrim(COALESCE(p_payload->>'location','')))<4) THEN
      RAISE EXCEPTION 'invalid_followup' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('provider-slot:' || a.provider_id,0));
    PERFORM pg_advisory_xact_lock(hashtextextended('patient-slot:' || a.patient_id,0));
    IF EXISTS(SELECT 1 FROM ientier.appointments booked
      WHERE (booked.provider_id=a.provider_id OR booked.patient_id=a.patient_id)
        AND booked.status IN ('pending','confirmed')
        AND booked.scheduled_at>new_date-interval '30 minutes'
        AND booked.scheduled_at<new_date+interval '30 minutes') THEN
      RAISE EXCEPTION 'slot_unavailable' USING ERRCODE='23505';
    END IF;
    INSERT INTO ientier.appointments(patient_id,patient_name_snapshot,provider_id,provider_type_snapshot,
      provider_name_snapshot,service_id,service_name_snapshot,mode,location,scheduled_at,schedule_label,
      status,response_note,responded_at,payment_method)
    VALUES(a.patient_id,a.patient_name_snapshot,a.provider_id,provider.account_type,provider.display_name,
      a.service_id,a.service_name_snapshot,new_mode,btrim(COALESCE(p_payload->>'location','')),
      new_date,to_char(new_date AT TIME ZONE 'America/Port-au-Prince','DD/MM/YYYY HH24:MI'),
      'confirmed',btrim(COALESCE(p_payload->>'note','')),now(),a.payment_method)
    RETURNING appointment_id INTO new_appointment;
    normalized := jsonb_build_object('scheduled_at',new_date,'mode',new_mode,
      'location',btrim(COALESCE(p_payload->>'location','')),'note',btrim(COALESCE(p_payload->>'note','')));
    document_title := 'Prochain rendez-vous';
  END IF;

  INSERT INTO ientier.consultation_documents(document_id,appointment_id,patient_id,provider_id,
    patient_name,provider_name,kind,payload,request_fingerprint,prescription_id,followup_appointment_id)
  VALUES(p_request_id,a.appointment_id,a.patient_id,a.provider_id,a.patient_name_snapshot,provider.display_name,
    p_kind,normalized,md5(p_payload::text),new_prescription,new_appointment) RETURNING * INTO doc;
  IF p_kind='exams' THEN
    FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
      INSERT INTO ientier.laboratory_exam_requests(document_id,patient_id,provider_id,exam_id,exam_name,instructions,priority)
      VALUES(doc.document_id,a.patient_id,a.provider_id,item->>'exam_id',item->>'name',item->>'instructions',normalized->>'priority');
    END LOOP;
  END IF;
  INSERT INTO ientier.notifications(patient_id,title,message,type,action_label,source,source_id,prescription_id,appointment_id)
  VALUES(a.patient_id,document_title,left(provider.display_name || ' vous a envoyé : ' || lower(document_title) || '.',300),
    CASE WHEN p_kind='followup' THEN 'appointment'::ientier.notification_type ELSE 'result'::ientier.notification_type END,
    'Consulter',
    CASE WHEN p_kind='prescription' THEN 'prescription'::ientier.notification_source
      WHEN p_kind='followup' THEN 'appointment'::ientier.notification_source ELSE 'app'::ientier.notification_source END,
    COALESCE(new_prescription,new_appointment,'consultation:' || doc.document_id::text),new_prescription,new_appointment);
  RETURN to_jsonb(doc);
END;
$$;

CREATE OR REPLACE FUNCTION ientier_private.video_consultation_catalog(p_appointment_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR COALESCE((auth.jwt()->>'is_anonymous')::boolean,false) OR NOT EXISTS(SELECT 1 FROM ientier.appointments a
   JOIN ientier.provider_profiles p ON p.provider_id=a.provider_id
   WHERE a.appointment_id=p_appointment_id AND a.provider_id=auth.uid()::text
     AND a.mode='video' AND a.status='confirmed' AND NOT a.provider_hidden AND p.verification_status='approved') THEN
   RAISE EXCEPTION 'not_allowed' USING ERRCODE='42501';
 END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',exam_id,'name',name,'category',category) ORDER BY name)
   FROM ientier.laboratory_exam_catalog WHERE active),'[]'::jsonb);
END;
$$;
