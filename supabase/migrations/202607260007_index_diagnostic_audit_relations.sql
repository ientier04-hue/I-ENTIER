-- Index de support des relations du gestionnaire de parcours diagnostiques.

BEGIN;

CREATE INDEX ix_diagnostic_versions_created_by
  ON ientier.diagnostic_pathway_versions (created_by);

CREATE INDEX ix_diagnostic_versions_updated_by
  ON ientier.diagnostic_pathway_versions (updated_by);

CREATE INDEX ix_diagnostic_versions_published_by
  ON ientier.diagnostic_pathway_versions (published_by);

CREATE INDEX ix_diagnostic_audit_version
  ON ientier.diagnostic_pathway_audit (version_id);

CREATE INDEX ix_diagnostic_audit_actor
  ON ientier.diagnostic_pathway_audit (actor_id);

COMMIT;
