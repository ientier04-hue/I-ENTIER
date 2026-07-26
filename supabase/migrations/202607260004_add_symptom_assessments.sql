-- =============================================================================
-- i-ENTIER -- évaluations assistées des symptômes
-- Dépend de 202607260001_initial_ientier_schema.sql et
-- 202607260002_supabase_integration.sql.
-- =============================================================================

BEGIN;

CREATE TABLE ientier.symptom_assessments (
  assessment_id          VARCHAR(160) PRIMARY KEY
                         DEFAULT gen_random_uuid()::TEXT,
  patient_id             VARCHAR(128) NOT NULL
                         REFERENCES ientier.patient_profiles(patient_id)
                         ON DELETE CASCADE,
  category_id            VARCHAR(80) NOT NULL,
  category_title         VARCHAR(140) NOT NULL,
  status                 VARCHAR(24) NOT NULL DEFAULT 'draft',
  current_question_id    VARCHAR(120),
  answers                JSONB NOT NULL DEFAULT '{}'::JSONB,
  consents               JSONB NOT NULL DEFAULT '{}'::JSONB,
  context_snapshot       JSONB NOT NULL DEFAULT '{}'::JSONB,
  result                 JSONB NOT NULL DEFAULT '{}'::JSONB,
  pathway_version        INTEGER NOT NULL DEFAULT 1,
  started_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at           TIMESTAMPTZ,

  CONSTRAINT ck_symptom_assessment_category
    CHECK (
      length(btrim(category_id)) BETWEEN 1 AND 80
      AND length(btrim(category_title)) BETWEEN 1 AND 140
    ),
  CONSTRAINT ck_symptom_assessment_status
    CHECK (status IN ('draft', 'completed')),
  CONSTRAINT ck_symptom_assessment_completion
    CHECK (
      (status = 'draft' AND completed_at IS NULL)
      OR
      (status = 'completed' AND completed_at IS NOT NULL)
    ),
  CONSTRAINT ck_symptom_assessment_version
    CHECK (pathway_version >= 1),
  CONSTRAINT ck_symptom_assessment_json_objects
    CHECK (
      jsonb_typeof(answers) = 'object'
      AND jsonb_typeof(consents) = 'object'
      AND jsonb_typeof(context_snapshot) = 'object'
      AND jsonb_typeof(result) = 'object'
    )
);

CREATE INDEX ix_symptom_assessments_patient_started
  ON ientier.symptom_assessments (patient_id, started_at DESC);

CREATE INDEX ix_symptom_assessments_patient_status
  ON ientier.symptom_assessments (patient_id, status, updated_at DESC);

CREATE TRIGGER trg_00_symptom_assessments_updated_at
BEFORE UPDATE ON ientier.symptom_assessments
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

ALTER TABLE ientier.symptom_assessments ENABLE ROW LEVEL SECURITY;

CREATE POLICY symptom_assessments_owner
ON ientier.symptom_assessments FOR ALL
USING (patient_id = ientier.current_actor_id())
WITH CHECK (patient_id = ientier.current_actor_id());

GRANT SELECT, INSERT, UPDATE, DELETE
ON ientier.symptom_assessments
TO authenticated;

GRANT ALL
ON ientier.symptom_assessments
TO service_role;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime
    ADD TABLE ientier.symptom_assessments;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

COMMENT ON TABLE ientier.symptom_assessments IS
  'Progression et résultat privé des évaluations assistées de symptômes. Les indices enregistrés sont des compatibilités de réponses, jamais des diagnostics.';

COMMIT;
