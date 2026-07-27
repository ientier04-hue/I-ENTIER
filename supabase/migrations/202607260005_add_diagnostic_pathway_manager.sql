-- =============================================================================
-- i-ENTIER -- catalogue administrable des parcours d'évaluation assistée
-- =============================================================================

BEGIN;

CREATE TABLE ientier.diagnostic_pathway_versions (
  version_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pathway_id             VARCHAR(80) NOT NULL,
  version_number         INTEGER NOT NULL,
  status                 VARCHAR(24) NOT NULL DEFAULT 'draft',
  definition             JSONB NOT NULL,
  change_note            VARCHAR(500) NOT NULL DEFAULT '',
  created_by             VARCHAR(128)
                         REFERENCES ientier.app_users(user_id) ON DELETE SET NULL,
  updated_by             VARCHAR(128)
                         REFERENCES ientier.app_users(user_id) ON DELETE SET NULL,
  published_by           VARCHAR(128)
                         REFERENCES ientier.app_users(user_id) ON DELETE SET NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_at           TIMESTAMPTZ,

  CONSTRAINT uq_diagnostic_pathway_version
    UNIQUE (pathway_id, version_number),
  CONSTRAINT ck_diagnostic_pathway_identity
    CHECK (length(btrim(pathway_id)) BETWEEN 1 AND 80),
  CONSTRAINT ck_diagnostic_pathway_version_number
    CHECK (version_number >= 1),
  CONSTRAINT ck_diagnostic_pathway_status
    CHECK (status IN ('draft', 'published', 'archived')),
  CONSTRAINT ck_diagnostic_pathway_definition
    CHECK (jsonb_typeof(definition) = 'object'),
  CONSTRAINT ck_diagnostic_pathway_definition_identity
    CHECK (pathway_id = definition ->> 'id'),
  CONSTRAINT ck_diagnostic_pathway_publication
    CHECK (
      (status = 'published' AND published_at IS NOT NULL)
      OR status <> 'published'
    ),
  CONSTRAINT ck_diagnostic_pathway_change_note
    CHECK (length(change_note) <= 500)
);

CREATE UNIQUE INDEX uq_diagnostic_pathway_one_draft
  ON ientier.diagnostic_pathway_versions (pathway_id)
  WHERE status = 'draft';

CREATE UNIQUE INDEX uq_diagnostic_pathway_one_published
  ON ientier.diagnostic_pathway_versions (pathway_id)
  WHERE status = 'published';

CREATE INDEX ix_diagnostic_pathway_status
  ON ientier.diagnostic_pathway_versions
  (status, pathway_id, version_number DESC);

CREATE TABLE ientier.diagnostic_pathway_audit (
  audit_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pathway_id             VARCHAR(80) NOT NULL,
  version_id             UUID
                         REFERENCES ientier.diagnostic_pathway_versions(version_id)
                         ON DELETE SET NULL,
  action                 VARCHAR(40) NOT NULL,
  actor_id               VARCHAR(128)
                         REFERENCES ientier.app_users(user_id) ON DELETE SET NULL,
  change_note            VARCHAR(500) NOT NULL DEFAULT '',
  definition_snapshot    JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_diagnostic_audit_action
    CHECK (action IN ('created', 'updated', 'published', 'archived', 'deleted')),
  CONSTRAINT ck_diagnostic_audit_snapshot
    CHECK (jsonb_typeof(definition_snapshot) = 'object')
);

CREATE INDEX ix_diagnostic_pathway_audit_lookup
  ON ientier.diagnostic_pathway_audit (pathway_id, created_at DESC);

CREATE TRIGGER trg_00_diagnostic_pathway_versions_updated_at
BEFORE UPDATE ON ientier.diagnostic_pathway_versions
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

CREATE OR REPLACE FUNCTION ientier.validate_diagnostic_definition(
  p_definition JSONB
)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SET search_path = ientier, public, pg_temp
AS $$
DECLARE
  question JSONB;
  option_item JSONB;
  question_ids TEXT[] := ARRAY[]::TEXT[];
  option_ids TEXT[];
  question_id TEXT;
  option_id TEXT;
  next_question_id TEXT;
BEGIN
  IF jsonb_typeof(p_definition) <> 'object' THEN
    RAISE EXCEPTION 'La définition doit être un objet JSON.'
      USING ERRCODE = '22023';
  END IF;
  IF length(btrim(COALESCE(p_definition ->> 'id', ''))) < 1
     OR length(btrim(COALESCE(p_definition ->> 'title', ''))) < 1 THEN
    RAISE EXCEPTION 'Le parcours doit avoir un identifiant et un titre.'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_definition -> 'questions') <> 'array'
     OR jsonb_array_length(p_definition -> 'questions') < 1 THEN
    RAISE EXCEPTION 'Le parcours doit contenir au moins une question.'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_definition -> 'possibilities') <> 'array'
     OR jsonb_array_length(p_definition -> 'possibilities') < 1 THEN
    RAISE EXCEPTION 'Le parcours doit contenir au moins un résultat possible.'
      USING ERRCODE = '22023';
  END IF;

  FOR question IN
    SELECT value FROM jsonb_array_elements(p_definition -> 'questions')
  LOOP
    question_id := btrim(COALESCE(question ->> 'id', ''));
    IF question_id = '' OR btrim(COALESCE(question ->> 'prompt', '')) = '' THEN
      RAISE EXCEPTION 'Chaque question doit avoir un identifiant et un texte.'
        USING ERRCODE = '22023';
    END IF;
    IF question_id = ANY(question_ids) THEN
      RAISE EXCEPTION 'Identifiant de question dupliqué : %', question_id
        USING ERRCODE = '22023';
    END IF;
    question_ids := array_append(question_ids, question_id);
  END LOOP;

  FOR question IN
    SELECT value FROM jsonb_array_elements(p_definition -> 'questions')
  LOOP
    question_id := question ->> 'id';
    IF jsonb_typeof(question -> 'options') <> 'array'
       OR jsonb_array_length(question -> 'options') < 2 THEN
      RAISE EXCEPTION 'La question % doit proposer au moins deux choix.', question_id
        USING ERRCODE = '22023';
    END IF;
    option_ids := ARRAY[]::TEXT[];
    FOR option_item IN
      SELECT value FROM jsonb_array_elements(question -> 'options')
    LOOP
      option_id := btrim(COALESCE(option_item ->> 'id', ''));
      IF option_id = '' OR btrim(COALESCE(option_item ->> 'label', '')) = '' THEN
        RAISE EXCEPTION 'Chaque choix de % doit avoir un identifiant et un libellé.', question_id
          USING ERRCODE = '22023';
      END IF;
      IF option_id = ANY(option_ids) THEN
        RAISE EXCEPTION 'Choix dupliqué dans % : %', question_id, option_id
          USING ERRCODE = '22023';
      END IF;
      option_ids := array_append(option_ids, option_id);
      next_question_id := NULLIF(btrim(COALESCE(option_item ->> 'nextQuestionId', '')), '');
      IF next_question_id IS NOT NULL
         AND NOT (next_question_id = ANY(question_ids)) THEN
        RAISE EXCEPTION 'La branche % de % vise une question inexistante.', option_id, question_id
          USING ERRCODE = '22023';
      END IF;
      IF next_question_id = question_id THEN
        RAISE EXCEPTION 'Une question ne peut pas pointer vers elle-même : %', question_id
          USING ERRCODE = '22023';
      END IF;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.guard_diagnostic_pathway_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'published' THEN
    PERFORM ientier.validate_diagnostic_definition(NEW.definition);
    IF NEW.published_at IS NULL THEN
      RAISE EXCEPTION 'Une version publiée doit avoir une date de publication.'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_10_guard_diagnostic_pathway_version
BEFORE INSERT OR UPDATE OF status, definition, published_at
ON ientier.diagnostic_pathway_versions
FOR EACH ROW EXECUTE FUNCTION ientier.guard_diagnostic_pathway_version();

CREATE OR REPLACE FUNCTION ientier.audit_diagnostic_pathway_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
DECLARE
  audit_action VARCHAR(40);
  audit_row ientier.diagnostic_pathway_versions%ROWTYPE;
BEGIN
  audit_row := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  audit_action := CASE
    WHEN TG_OP = 'INSERT' THEN 'created'
    WHEN TG_OP = 'DELETE' THEN 'deleted'
    WHEN NEW.status = 'published' AND OLD.status <> 'published' THEN 'published'
    WHEN NEW.status = 'archived' AND OLD.status <> 'archived' THEN 'archived'
    ELSE 'updated'
  END;

  INSERT INTO ientier.diagnostic_pathway_audit (
    pathway_id,
    version_id,
    action,
    actor_id,
    change_note,
    definition_snapshot
  )
  VALUES (
    audit_row.pathway_id,
    CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE audit_row.version_id END,
    audit_action,
    ientier.current_actor_id(),
    audit_row.change_note,
    audit_row.definition
  );
  RETURN audit_row;
END;
$$;

CREATE TRIGGER trg_90_audit_diagnostic_pathway_change
AFTER INSERT OR UPDATE OR DELETE ON ientier.diagnostic_pathway_versions
FOR EACH ROW EXECUTE FUNCTION ientier.audit_diagnostic_pathway_change();

CREATE OR REPLACE FUNCTION ientier.publish_diagnostic_pathway(
  p_version_id UUID,
  p_admin_id VARCHAR(128),
  p_change_note TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, auth, public, pg_temp
AS $$
DECLARE
  target ientier.diagnostic_pathway_versions%ROWTYPE;
BEGIN
  IF ientier.current_actor_id() IS NULL
     OR ientier.current_actor_id() <> p_admin_id
     OR NOT ientier.current_actor_is_admin() THEN
    RAISE EXCEPTION 'Accès administrateur requis.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO target
  FROM ientier.diagnostic_pathway_versions
  WHERE version_id = p_version_id
  FOR UPDATE;

  IF NOT FOUND OR target.status <> 'draft' THEN
    RAISE EXCEPTION 'Seul un brouillon existant peut être publié.'
      USING ERRCODE = '22023';
  END IF;
  IF target.pathway_id <> target.definition ->> 'id' THEN
    RAISE EXCEPTION 'L’identifiant du parcours ne correspond pas à sa définition.'
      USING ERRCODE = '22023';
  END IF;

  PERFORM ientier.validate_diagnostic_definition(target.definition);

  UPDATE ientier.diagnostic_pathway_versions
  SET status = 'archived',
      updated_by = p_admin_id
  WHERE pathway_id = target.pathway_id
    AND status = 'published';

  UPDATE ientier.diagnostic_pathway_versions
  SET status = 'published',
      change_note = left(btrim(COALESCE(p_change_note, '')), 500),
      published_by = p_admin_id,
      published_at = CURRENT_TIMESTAMP,
      updated_by = p_admin_id
  WHERE version_id = p_version_id;

END;
$$;

ALTER TABLE ientier.diagnostic_pathway_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.diagnostic_pathway_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY diagnostic_versions_select
ON ientier.diagnostic_pathway_versions FOR SELECT
USING (status = 'published' OR ientier.current_actor_is_admin());

CREATE POLICY diagnostic_versions_admin_insert
ON ientier.diagnostic_pathway_versions FOR INSERT
WITH CHECK (ientier.current_actor_is_admin() AND status = 'draft');

CREATE POLICY diagnostic_versions_admin_update
ON ientier.diagnostic_pathway_versions FOR UPDATE
USING (ientier.current_actor_is_admin() AND status = 'draft')
WITH CHECK (ientier.current_actor_is_admin() AND status = 'draft');

CREATE POLICY diagnostic_versions_admin_delete
ON ientier.diagnostic_pathway_versions FOR DELETE
USING (ientier.current_actor_is_admin() AND status = 'draft');

CREATE POLICY diagnostic_audit_admin_select
ON ientier.diagnostic_pathway_audit FOR SELECT
USING (ientier.current_actor_is_admin());

GRANT SELECT ON ientier.diagnostic_pathway_versions TO authenticated;
GRANT INSERT, UPDATE, DELETE
ON ientier.diagnostic_pathway_versions TO authenticated;
GRANT SELECT ON ientier.diagnostic_pathway_audit TO authenticated;
GRANT ALL ON
  ientier.diagnostic_pathway_versions,
  ientier.diagnostic_pathway_audit
TO service_role;

GRANT EXECUTE ON FUNCTION
  ientier.publish_diagnostic_pathway(UUID, VARCHAR, TEXT)
TO authenticated;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime
    ADD TABLE ientier.diagnostic_pathway_versions;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

COMMENT ON TABLE ientier.diagnostic_pathway_versions IS
  'Versions brouillon, publiées et archivées des arbres d’évaluation assistée. Les patients ne peuvent lire que les versions publiées.';

COMMENT ON TABLE ientier.diagnostic_pathway_audit IS
  'Journal des publications et changements structurants du gestionnaire de parcours.';

COMMIT;
