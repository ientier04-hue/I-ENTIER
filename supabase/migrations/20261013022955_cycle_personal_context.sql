BEGIN;

CREATE TABLE ientier.cycle_personal_contexts (
  patient_id varchar(128) PRIMARY KEY
    REFERENCES ientier.patient_profiles(patient_id) ON DELETE CASCADE,
  life_stage text NOT NULL DEFAULT 'unspecified'
    CHECK (life_stage IN ('unspecified', 'menstruating', 'pregnant', 'postpartum', 'perimenopause', 'menopause')),
  contraception text NOT NULL DEFAULT 'unspecified'
    CHECK (contraception IN ('unspecified', 'none', 'nonHormonal', 'hormonal')),
  breastfeeding boolean NOT NULL DEFAULT false,
  has_pcos boolean NOT NULL DEFAULT false,
  history_start date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cycle_context_history_date CHECK (history_start IS NULL OR history_start BETWEEN DATE '1900-01-01' AND CURRENT_DATE)
);

ALTER TABLE ientier.cycle_personal_contexts ENABLE ROW LEVEL SECURITY;
CREATE POLICY cycle_personal_context_owner ON ientier.cycle_personal_contexts
  FOR ALL TO authenticated
  USING (patient_id = (SELECT auth.uid())::text)
  WITH CHECK (patient_id = (SELECT auth.uid())::text);
REVOKE ALL ON ientier.cycle_personal_contexts FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ientier.cycle_personal_contexts TO authenticated;
GRANT ALL ON ientier.cycle_personal_contexts TO service_role;

CREATE TRIGGER cycle_personal_context_updated_at
  BEFORE UPDATE ON ientier.cycle_personal_contexts
  FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

ALTER TABLE ientier.cycle_entries
  ADD COLUMN is_spotting boolean NOT NULL DEFAULT false,
  ADD COLUMN stress_level smallint CHECK (stress_level BETWEEN 0 AND 3),
  ADD COLUMN sleep_hours numeric(4,2) CHECK (sleep_hours BETWEEN 0 AND 24),
  ADD CONSTRAINT cycle_bleeding_kind CHECK (NOT (is_period AND is_spotting));

NOTIFY pgrst, 'reload schema';
COMMIT;
