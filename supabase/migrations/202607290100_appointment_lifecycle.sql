BEGIN;

SET search_path TO ientier, public;

ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS cancellation_note VARCHAR(500) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cancelled_by VARCHAR(16) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS patient_hidden BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS provider_hidden BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_appointment_cancellation'
      AND conrelid = 'ientier.appointments'::regclass
  ) THEN
    ALTER TABLE appointments
      ADD CONSTRAINT ck_appointment_cancellation
      CHECK (
        length(cancellation_note) <= 500
        AND (
          (cancelled_by = '' AND cancelled_at IS NULL)
          OR (
            cancelled_by IN ('patient', 'provider')
            AND cancelled_at IS NOT NULL
          )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_appointment_hidden_after_cancellation'
      AND conrelid = 'ientier.appointments'::regclass
  ) THEN
    ALTER TABLE appointments
      ADD CONSTRAINT ck_appointment_hidden_after_cancellation
      CHECK (
        (patient_hidden = FALSE AND provider_hidden = FALSE)
        OR status = 'cancelled'
      );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION protect_appointment_payment_method()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.payment_method IS DISTINCT FROM OLD.payment_method
     AND COALESCE(
       current_setting('ientier.appointment_management_context', TRUE),
       ''
     ) <> 'patient_update' THEN
    RAISE EXCEPTION
      'Le moyen de paiement ne peut être modifié que par le patient sur une demande en attente.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_appointment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  profile provider_profiles%ROWTYPE;
  configured_mode_count INTEGER;
  actor_id VARCHAR(128) := current_actor_id();
  management_context TEXT := COALESCE(
    current_setting('ientier.appointment_management_context', TRUE),
    ''
  );
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT *
      INTO profile
    FROM provider_profiles
    WHERE provider_id = NEW.provider_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Le prestataire du rendez-vous n''existe pas.';
    END IF;

    IF profile.account_type <> NEW.provider_type_snapshot THEN
      RAISE EXCEPTION 'Le type du prestataire ne correspond pas à son dossier.';
    END IF;

    IF profile.verification_status <> 'approved'
       OR profile.is_visible <> TRUE
       OR profile.available <> TRUE THEN
      RAISE EXCEPTION 'Le prestataire doit être approuvé, publié et disponible.';
    END IF;

    IF NEW.service_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM provider_services s
         WHERE s.service_id = NEW.service_id
           AND s.provider_id = NEW.provider_id
           AND s.active = TRUE
       ) THEN
      RAISE EXCEPTION 'Le service choisi n''appartient pas au prestataire.';
    END IF;

    SELECT count(*)
      INTO configured_mode_count
    FROM provider_appointment_modes m
    WHERE m.provider_id = NEW.provider_id;

    IF configured_mode_count > 0
       AND NOT EXISTS (
         SELECT 1
         FROM provider_appointment_modes m
         WHERE m.provider_id = NEW.provider_id
           AND m.mode = NEW.mode
           AND m.enabled = TRUE
       ) THEN
      RAISE EXCEPTION 'Ce mode de rendez-vous n''est pas activé par le prestataire.';
    END IF;

    RETURN NEW;
  END IF;

  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Une session authentifiée est requise.';
  END IF;

  IF NEW.appointment_id IS DISTINCT FROM OLD.appointment_id
     OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
     OR NEW.patient_name_snapshot IS DISTINCT FROM OLD.patient_name_snapshot
     OR NEW.provider_id IS DISTINCT FROM OLD.provider_id
     OR NEW.provider_type_snapshot IS DISTINCT FROM OLD.provider_type_snapshot
     OR NEW.provider_name_snapshot IS DISTINCT FROM OLD.provider_name_snapshot
     OR NEW.service_id IS DISTINCT FROM OLD.service_id
     OR NEW.service_name_snapshot IS DISTINCT FROM OLD.service_name_snapshot
     OR NEW.mode IS DISTINCT FROM OLD.mode
     OR NEW.schedule_label IS DISTINCT FROM OLD.schedule_label
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'L’identité du rendez-vous ne peut pas être modifiée.';
  END IF;

  IF management_context = 'patient_update' THEN
    IF actor_id <> OLD.patient_id
       OR OLD.status <> 'pending'
       OR NEW.status <> 'pending'
       OR NEW.response_note IS DISTINCT FROM OLD.response_note
       OR NEW.responded_at IS DISTINCT FROM OLD.responded_at
       OR NEW.cancellation_note IS DISTINCT FROM OLD.cancellation_note
       OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
       OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
       OR NEW.patient_hidden IS DISTINCT FROM OLD.patient_hidden
       OR NEW.provider_hidden IS DISTINCT FROM OLD.provider_hidden THEN
      RAISE EXCEPTION 'Cette demande ne peut pas être modifiée par le patient.';
    END IF;
    IF NEW.scheduled_at <= CURRENT_TIMESTAMP + INTERVAL '30 minutes' THEN
      RAISE EXCEPTION 'Le nouveau créneau doit commencer dans plus de 30 minutes.';
    END IF;
    IF NEW.mode = 'homeVisit' AND length(btrim(NEW.location)) <= 3 THEN
      RAISE EXCEPTION 'Une adresse est requise pour la visite à domicile.';
    END IF;
  ELSIF management_context = 'patient_cancel' THEN
    IF actor_id <> OLD.patient_id
       OR OLD.status NOT IN ('pending', 'confirmed')
       OR NEW.status <> 'cancelled'
       OR NEW.cancelled_by <> 'patient'
       OR NEW.cancelled_at IS NULL
       OR NEW.location IS DISTINCT FROM OLD.location
       OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR NEW.patient_note IS DISTINCT FROM OLD.patient_note
       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
       OR NEW.response_note IS DISTINCT FROM OLD.response_note
       OR NEW.patient_hidden IS DISTINCT FROM OLD.patient_hidden
       OR NEW.provider_hidden IS DISTINCT FROM OLD.provider_hidden THEN
      RAISE EXCEPTION 'Ce rendez-vous ne peut pas être annulé par le patient.';
    END IF;
  ELSIF management_context = 'provider_update' THEN
    IF actor_id <> OLD.provider_id
       OR OLD.status NOT IN ('pending', 'confirmed')
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.location IS DISTINCT FROM OLD.location
       OR NEW.patient_note IS DISTINCT FROM OLD.patient_note
       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
       OR NEW.responded_at IS DISTINCT FROM OLD.responded_at
       OR NEW.cancellation_note IS DISTINCT FROM OLD.cancellation_note
       OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
       OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
       OR NEW.patient_hidden IS DISTINCT FROM OLD.patient_hidden
       OR NEW.provider_hidden IS DISTINCT FROM OLD.provider_hidden THEN
      RAISE EXCEPTION 'Ce rendez-vous ne peut pas être modifié par le prestataire.';
    END IF;
    IF NEW.scheduled_at <= CURRENT_TIMESTAMP + INTERVAL '30 minutes' THEN
      RAISE EXCEPTION 'Le nouveau créneau doit commencer dans plus de 30 minutes.';
    END IF;
  ELSIF management_context = 'provider_response' THEN
    IF actor_id <> OLD.provider_id
       OR NOT (
         (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'cancelled'))
         OR (OLD.status = 'confirmed' AND NEW.status = 'cancelled')
       )
       OR NEW.location IS DISTINCT FROM OLD.location
       OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR NEW.patient_note IS DISTINCT FROM OLD.patient_note
       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
       OR NEW.patient_hidden IS DISTINCT FROM OLD.patient_hidden
       OR NEW.provider_hidden IS DISTINCT FROM OLD.provider_hidden THEN
      RAISE EXCEPTION 'Cette réponse du prestataire est invalide.';
    END IF;
    IF NEW.status = 'confirmed'
       AND (
         NEW.cancelled_by <> ''
         OR NEW.cancelled_at IS NOT NULL
         OR NEW.cancellation_note <> ''
       ) THEN
      RAISE EXCEPTION 'Une confirmation ne peut pas contenir d’annulation.';
    END IF;
    IF NEW.status = 'cancelled'
       AND (NEW.cancelled_by <> 'provider' OR NEW.cancelled_at IS NULL) THEN
      RAISE EXCEPTION 'L’annulation du prestataire est incomplète.';
    END IF;
  ELSIF management_context = 'patient_hide' THEN
    IF actor_id <> OLD.patient_id
       OR OLD.status <> 'cancelled'
       OR NEW.patient_hidden <> TRUE
       OR NEW.provider_hidden IS DISTINCT FROM OLD.provider_hidden
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.location IS DISTINCT FROM OLD.location
       OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR NEW.patient_note IS DISTINCT FROM OLD.patient_note
       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
       OR NEW.response_note IS DISTINCT FROM OLD.response_note
       OR NEW.responded_at IS DISTINCT FROM OLD.responded_at
       OR NEW.cancellation_note IS DISTINCT FROM OLD.cancellation_note
       OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
       OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at THEN
      RAISE EXCEPTION 'Ce rendez-vous ne peut pas être masqué par le patient.';
    END IF;
  ELSIF management_context = 'provider_hide' THEN
    IF actor_id <> OLD.provider_id
       OR OLD.status <> 'cancelled'
       OR NEW.provider_hidden <> TRUE
       OR NEW.patient_hidden IS DISTINCT FROM OLD.patient_hidden
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.location IS DISTINCT FROM OLD.location
       OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR NEW.patient_note IS DISTINCT FROM OLD.patient_note
       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
       OR NEW.response_note IS DISTINCT FROM OLD.response_note
       OR NEW.responded_at IS DISTINCT FROM OLD.responded_at
       OR NEW.cancellation_note IS DISTINCT FROM OLD.cancellation_note
       OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
       OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at THEN
      RAISE EXCEPTION 'Ce rendez-vous ne peut pas être masqué par le prestataire.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Utilisez une action sécurisée pour gérer le rendez-vous.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit_appointment_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO appointment_status_history (
      appointment_id,
      previous_status,
      new_status,
      changed_by,
      note
    )
    VALUES (
      NEW.appointment_id,
      OLD.status,
      NEW.status,
      COALESCE(current_actor_id(), NEW.provider_id),
      COALESCE(NULLIF(NEW.cancellation_note, ''), NEW.response_note)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION patient_update_appointment(
  p_appointment_id VARCHAR(160),
  p_scheduled_at TIMESTAMPTZ,
  p_patient_note VARCHAR(500) DEFAULT '',
  p_payment_method appointment_payment_method DEFAULT 'cash',
  p_location VARCHAR(300) DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  target appointments%ROWTYPE;
BEGIN
  SELECT *
    INTO target
  FROM appointments
  WHERE appointment_id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND OR current_actor_id() IS NULL
     OR target.patient_id <> current_actor_id() THEN
    RAISE EXCEPTION 'Ce rendez-vous n’appartient pas au patient connecté.';
  END IF;
  IF target.status <> 'pending' THEN
    RAISE EXCEPTION 'Seule une demande en attente peut être modifiée.';
  END IF;

  PERFORM set_config(
    'ientier.appointment_management_context',
    'patient_update',
    TRUE
  );
  UPDATE appointments
  SET scheduled_at = p_scheduled_at,
      patient_note = btrim(COALESCE(p_patient_note, '')),
      payment_method = p_payment_method,
      location = btrim(COALESCE(p_location, ''))
  WHERE appointment_id = p_appointment_id;
END;
$$;

CREATE OR REPLACE FUNCTION patient_cancel_appointment(
  p_appointment_id VARCHAR(160),
  p_reason VARCHAR(500) DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  target appointments%ROWTYPE;
BEGIN
  SELECT *
    INTO target
  FROM appointments
  WHERE appointment_id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND OR current_actor_id() IS NULL
     OR target.patient_id <> current_actor_id() THEN
    RAISE EXCEPTION 'Ce rendez-vous n’appartient pas au patient connecté.';
  END IF;
  IF target.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'Ce rendez-vous ne peut plus être annulé.';
  END IF;

  PERFORM set_config(
    'ientier.appointment_management_context',
    'patient_cancel',
    TRUE
  );
  UPDATE appointments
  SET status = 'cancelled',
      cancellation_note = btrim(COALESCE(p_reason, '')),
      cancelled_by = 'patient',
      cancelled_at = CURRENT_TIMESTAMP,
      responded_at = COALESCE(responded_at, CURRENT_TIMESTAMP)
  WHERE appointment_id = p_appointment_id;
END;
$$;

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

CREATE OR REPLACE FUNCTION hide_appointment_for_actor(
  p_appointment_id VARCHAR(160),
  p_actor_type VARCHAR(16)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  target appointments%ROWTYPE;
BEGIN
  SELECT *
    INTO target
  FROM appointments
  WHERE appointment_id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND OR current_actor_id() IS NULL THEN
    RAISE EXCEPTION 'Le rendez-vous n’existe pas.';
  END IF;
  IF target.status <> 'cancelled' THEN
    RAISE EXCEPTION 'Seul un rendez-vous annulé peut être supprimé.';
  END IF;

  IF p_actor_type = 'patient' AND target.patient_id = current_actor_id() THEN
    PERFORM set_config(
      'ientier.appointment_management_context',
      'patient_hide',
      TRUE
    );
    UPDATE appointments
    SET patient_hidden = TRUE
    WHERE appointment_id = p_appointment_id;
  ELSIF p_actor_type = 'provider'
        AND target.provider_id = current_actor_id() THEN
    PERFORM set_config(
      'ientier.appointment_management_context',
      'provider_hide',
      TRUE
    );
    UPDATE appointments
    SET provider_hidden = TRUE
    WHERE appointment_id = p_appointment_id;
  ELSE
    RAISE EXCEPTION 'Vous ne pouvez pas supprimer ce rendez-vous.';
  END IF;
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

REVOKE EXECUTE ON FUNCTION patient_update_appointment(
  VARCHAR,
  TIMESTAMPTZ,
  VARCHAR,
  appointment_payment_method,
  VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION patient_cancel_appointment(
  VARCHAR,
  VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION provider_update_appointment(
  VARCHAR,
  VARCHAR,
  TIMESTAMPTZ,
  VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION hide_appointment_for_actor(
  VARCHAR,
  VARCHAR
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION patient_update_appointment(
  VARCHAR,
  TIMESTAMPTZ,
  VARCHAR,
  appointment_payment_method,
  VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION patient_cancel_appointment(
  VARCHAR,
  VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION provider_update_appointment(
  VARCHAR,
  VARCHAR,
  TIMESTAMPTZ,
  VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION hide_appointment_for_actor(
  VARCHAR,
  VARCHAR
) TO authenticated;

COMMENT ON COLUMN appointments.patient_hidden IS
  'Masque le rendez-vous annulé uniquement dans l’interface patient.';
COMMENT ON COLUMN appointments.provider_hidden IS
  'Masque le rendez-vous annulé uniquement dans l’interface professionnelle.';

COMMIT;
