BEGIN;

SET search_path TO ientier, public;

DO $$
BEGIN
  CREATE TYPE appointment_payment_method AS ENUM (
    'cash',
    'monCash',
    'natCash',
    'bankTransfer',
    'card'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS payment_method appointment_payment_method
  NOT NULL DEFAULT 'cash';

CREATE OR REPLACE FUNCTION protect_appointment_payment_method()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.payment_method IS DISTINCT FROM OLD.payment_method THEN
    RAISE EXCEPTION
      'Le moyen de paiement ne peut pas être modifié après la réservation.';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_05_appointment_payment_immutable'
      AND tgrelid = 'ientier.appointments'::regclass
  ) THEN
    EXECUTE $trigger$
      CREATE TRIGGER trg_05_appointment_payment_immutable
      BEFORE UPDATE ON appointments
      FOR EACH ROW
      EXECUTE FUNCTION protect_appointment_payment_method()
    $trigger$;
  END IF;
END;
$$;

COMMENT ON COLUMN appointments.payment_method IS
  'Moyen de paiement prévu par le patient; aucun débit n’est effectué par l’application.';

COMMIT;
