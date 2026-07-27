-- Fige l'arbre et sa version au début d'une évaluation afin qu'une publication
-- administrative ultérieure ne modifie jamais un parcours déjà commencé.

BEGIN;

ALTER TABLE ientier.symptom_assessments
  ADD COLUMN pathway_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD CONSTRAINT ck_symptom_assessment_pathway_snapshot
    CHECK (jsonb_typeof(pathway_snapshot) = 'object');

COMMENT ON COLUMN ientier.symptom_assessments.pathway_snapshot IS
  'Instantané privé de la définition utilisée au démarrage, nécessaire à une reprise cohérente après publication d’une nouvelle version.';

COMMIT;
