-- Finalise le schéma relationnel natif Supabase sur les projets déjà migrés.

BEGIN;

SET search_path TO ientier, public;

ALTER TABLE provider_reviews
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE health_measurements
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE cycle_entries
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE mental_health_entries
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE laboratory_results
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE preventive_care_records
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE preventive_care_reminders
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE prescriptions
  DROP COLUMN IF EXISTS firestore_id CASCADE;
ALTER TABLE notifications
  DROP COLUMN IF EXISTS firestore_id CASCADE;

CREATE OR REPLACE FUNCTION provider_update_appointment(
  p_appointment_id VARCHAR(160),
  p_provider_id VARCHAR(128),
  p_scheduled_at TIMESTAMPTZ,
  p_response_note VARCHAR(500) DEFAULT ''
)
RETURNS VARCHAR(180)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  target appointments%ROWTYPE;
  generated_notification_id VARCHAR(180);
BEGIN
  SELECT *
    INTO target
  FROM appointments
  WHERE appointment_id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND OR current_actor_id() IS NULL
     OR current_actor_id() <> p_provider_id
     OR target.provider_id <> p_provider_id THEN
    RAISE EXCEPTION 'Ce rendez-vous n’appartient pas au prestataire connecté.';
  END IF;
  IF target.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'Ce rendez-vous ne peut plus être modifié.';
  END IF;

  PERFORM set_config(
    'ientier.appointment_management_context',
    'provider_update',
    TRUE
  );
  UPDATE appointments
  SET scheduled_at = p_scheduled_at,
      response_note = CASE
        WHEN target.status = 'confirmed'
          THEN btrim(COALESCE(p_response_note, ''))
        ELSE response_note
      END
  WHERE appointment_id = p_appointment_id;

  generated_notification_id := 'appointment_update_' || p_appointment_id;
  INSERT INTO notifications (
    notification_id,
    patient_id,
    title,
    message,
    type,
    is_read,
    action_label,
    source,
    source_id,
    appointment_id
  )
  VALUES (
    generated_notification_id,
    target.patient_id,
    'Rendez-vous modifié',
    target.provider_name_snapshot
      || ' a modifié la date ou l’heure de votre rendez-vous.',
    'appointment',
    FALSE,
    'Voir le rendez-vous',
    'appointment',
    p_appointment_id,
    p_appointment_id
  )
  ON CONFLICT (notification_id) DO UPDATE
  SET title = EXCLUDED.title,
      message = EXCLUDED.message,
      is_read = FALSE,
      updated_at = CURRENT_TIMESTAMP;

  RETURN generated_notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION respond_to_appointment(
  p_appointment_id VARCHAR(160),
  p_provider_id VARCHAR(128),
  p_new_status appointment_status,
  p_response_note VARCHAR(500) DEFAULT ''
)
RETURNS VARCHAR(180)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  target appointments%ROWTYPE;
  generated_notification_id VARCHAR(180);
  normalized_note VARCHAR(500) := btrim(COALESCE(p_response_note, ''));
BEGIN
  IF current_actor_id() IS NULL
     OR current_actor_id() <> p_provider_id THEN
    RAISE EXCEPTION 'Le prestataire déclaré ne correspond pas à la session.';
  END IF;
  IF p_new_status NOT IN ('confirmed', 'cancelled') THEN
    RAISE EXCEPTION 'La réponse doit être confirmed ou cancelled.';
  END IF;

  SELECT *
    INTO target
  FROM appointments
  WHERE appointment_id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND OR target.provider_id <> p_provider_id THEN
    RAISE EXCEPTION 'Ce rendez-vous appartient à un autre prestataire.';
  END IF;
  IF NOT (
    (target.status = 'pending' AND p_new_status IN ('confirmed', 'cancelled'))
    OR (target.status = 'confirmed' AND p_new_status = 'cancelled')
  ) THEN
    RAISE EXCEPTION 'Cette transition de statut est invalide.';
  END IF;

  PERFORM set_config(
    'ientier.appointment_management_context',
    'provider_response',
    TRUE
  );
  UPDATE appointments
  SET status = p_new_status,
      response_note = CASE
        WHEN p_new_status = 'confirmed' THEN normalized_note
        ELSE response_note
      END,
      responded_at = CURRENT_TIMESTAMP,
      cancellation_note = CASE
        WHEN p_new_status = 'cancelled' THEN normalized_note
        ELSE ''
      END,
      cancelled_by = CASE
        WHEN p_new_status = 'cancelled' THEN 'provider'
        ELSE ''
      END,
      cancelled_at = CASE
        WHEN p_new_status = 'cancelled' THEN CURRENT_TIMESTAMP
        ELSE NULL
      END
  WHERE appointment_id = p_appointment_id;

  generated_notification_id := 'appointment_' || p_appointment_id;
  INSERT INTO notifications (
    notification_id,
    patient_id,
    title,
    message,
    type,
    is_read,
    action_label,
    source,
    source_id,
    appointment_id
  )
  VALUES (
    generated_notification_id,
    target.patient_id,
    CASE
      WHEN p_new_status = 'confirmed' THEN 'Rendez-vous confirmé'
      ELSE 'Rendez-vous annulé'
    END,
    CASE
      WHEN p_new_status = 'confirmed'
        THEN target.provider_name_snapshot
          || ' a confirmé votre demande de rendez-vous.'
      ELSE target.provider_name_snapshot
        || ' a annulé votre rendez-vous.'
    END,
    'appointment',
    FALSE,
    'Voir le rendez-vous',
    'appointment',
    p_appointment_id,
    p_appointment_id
  )
  ON CONFLICT (notification_id) DO UPDATE
  SET title = EXCLUDED.title,
      message = EXCLUDED.message,
      is_read = FALSE,
      updated_at = CURRENT_TIMESTAMP;

  RETURN generated_notification_id;
END;
$$;

COMMIT;
