-- Préférences de classement du catalogue propres à chaque patient.

BEGIN;

SET search_path TO ientier, public;

CREATE TABLE patient_service_preferences (
  patient_id          VARCHAR(128) PRIMARY KEY
                      REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  pinned_service_ids  TEXT[] NOT NULL DEFAULT '{}',
  usage               JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_patient_service_pins_limit
    CHECK (cardinality(pinned_service_ids) <= 3),
  CONSTRAINT ck_patient_service_usage_object
    CHECK (jsonb_typeof(usage) = 'object')
);

COMMENT ON TABLE patient_service_preferences IS
  'Ordre des services épinglés et signaux d’usage servant au classement personnalisé.';
COMMENT ON COLUMN patient_service_preferences.usage IS
  'Objet indexé par identifiant de service : open_count et last_opened_at.';

CREATE TRIGGER trg_patient_service_preferences_updated_at
BEFORE UPDATE ON patient_service_preferences
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE patient_service_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY patient_service_preferences_owner
ON patient_service_preferences FOR ALL TO authenticated
USING ((SELECT auth.uid())::TEXT = patient_id)
WITH CHECK ((SELECT auth.uid())::TEXT = patient_id);

GRANT SELECT, INSERT, UPDATE ON patient_service_preferences TO authenticated;

COMMIT;
