-- =============================================================================
-- i-ENTIER -- Couverture médicale OFATMA et éligibilité au Crédit Santé
-- =============================================================================

BEGIN;

CREATE TABLE ientier.medical_insurance_coverages (
  coverage_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id VARCHAR(128) NOT NULL
    REFERENCES ientier.patient_profiles(patient_id) ON DELETE RESTRICT,
  patient_name_snapshot VARCHAR(140) NOT NULL
    CHECK (length(btrim(patient_name_snapshot)) BETWEEN 2 AND 140),
  insurer_code VARCHAR(30) NOT NULL DEFAULT 'OFATMA'
    CHECK (insurer_code IN ('OFATMA')),
  member_number VARCHAR(80) NOT NULL DEFAULT ''
    CHECK (length(member_number) <= 80),
  card_front_path TEXT NOT NULL UNIQUE,
  card_back_path TEXT NOT NULL UNIQUE,
  card_front_mime_type VARCHAR(100) NOT NULL
    CHECK (card_front_mime_type IN ('image/jpeg','image/png','image/webp')),
  card_back_mime_type VARCHAR(100) NOT NULL
    CHECK (card_back_mime_type IN ('image/jpeg','image/png','image/webp')),
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','verified','rejected')),
  valid_from DATE,
  valid_until DATE,
  review_note VARCHAR(1000) NOT NULL DEFAULT '',
  reviewed_by VARCHAR(128)
    REFERENCES ientier.provider_profiles(provider_id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (card_front_path <> card_back_path),
  CHECK (
    status <> 'verified'
    OR (
      valid_from IS NOT NULL
      AND valid_until IS NOT NULL
      AND valid_until >= valid_from
    )
  ),
  CHECK (status <> 'rejected' OR length(btrim(review_note)) >= 5)
);

CREATE INDEX idx_medical_insurance_patient
  ON ientier.medical_insurance_coverages(patient_id, submitted_at DESC);
CREATE INDEX idx_medical_insurance_review_queue
  ON ientier.medical_insurance_coverages(status, submitted_at);
CREATE INDEX idx_medical_insurance_validity
  ON ientier.medical_insurance_coverages(patient_id, valid_until DESC)
  WHERE status = 'verified';

CREATE TRIGGER trg_medical_insurance_updated
BEFORE UPDATE ON ientier.medical_insurance_coverages
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

CREATE OR REPLACE FUNCTION ientier.current_actor_is_verified_professional()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM ientier.provider_profiles p
    WHERE p.provider_id = ientier.current_actor_id()
      AND p.account_type = 'professional'
      AND p.verification_status = 'approved'
  );
$$;

CREATE OR REPLACE FUNCTION ientier.submit_medical_insurance_coverage(
  p_patient_name VARCHAR,
  p_member_number VARCHAR,
  p_card_front_path TEXT,
  p_card_back_path TEXT,
  p_card_front_mime_type VARCHAR,
  p_card_back_mime_type VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := ientier.current_actor_id();
  new_id UUID;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Une session patient authentifiée est requise.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ientier.patient_profiles WHERE patient_id = actor_id
  ) THEN
    RAISE EXCEPTION 'Un profil patient complet est requis.';
  END IF;
  IF length(btrim(COALESCE(p_patient_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Le nom du patient est requis.';
  END IF;
  IF split_part(p_card_front_path, '/', 1) <> actor_id
     OR split_part(p_card_back_path, '/', 1) <> actor_id THEN
    RAISE EXCEPTION 'Chemin de carte d''assurance invalide.';
  END IF;
  IF p_card_front_path = p_card_back_path THEN
    RAISE EXCEPTION 'Le recto et le verso doivent être deux images distinctes.';
  END IF;
  IF p_card_front_mime_type NOT IN ('image/jpeg','image/png','image/webp')
     OR p_card_back_mime_type NOT IN ('image/jpeg','image/png','image/webp') THEN
    RAISE EXCEPTION 'Format de carte non accepté.';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = 'insurance-cards' AND name = p_card_front_path
  ) OR NOT EXISTS (
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = 'insurance-cards' AND name = p_card_back_path
  ) THEN
    RAISE EXCEPTION 'Les images recto et verso doivent être téléversées avant la soumission.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM ientier.medical_insurance_coverages c
    WHERE c.patient_id = actor_id
      AND c.insurer_code = 'OFATMA'
      AND (
        c.status = 'pending'
        OR (c.status = 'verified' AND c.valid_until >= CURRENT_DATE)
      )
  ) THEN
    RAISE EXCEPTION 'Une couverture OFATMA active ou en cours de validation existe déjà.';
  END IF;

  INSERT INTO ientier.medical_insurance_coverages (
    patient_id,
    patient_name_snapshot,
    insurer_code,
    member_number,
    card_front_path,
    card_back_path,
    card_front_mime_type,
    card_back_mime_type
  ) VALUES (
    actor_id,
    btrim(p_patient_name),
    'OFATMA',
    btrim(COALESCE(p_member_number, '')),
    p_card_front_path,
    p_card_back_path,
    p_card_front_mime_type,
    p_card_back_mime_type
  ) RETURNING coverage_id INTO new_id;

  UPDATE ientier.patient_profiles
  SET insurance = 'OFATMA'
  WHERE patient_id = actor_id;

  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.review_medical_insurance_coverage(
  p_coverage_id UUID,
  p_approve BOOLEAN,
  p_reason VARCHAR DEFAULT '',
  p_valid_until DATE DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := ientier.current_actor_id();
  coverage ientier.medical_insurance_coverages%ROWTYPE;
BEGIN
  IF actor_id IS NULL OR NOT ientier.current_actor_is_verified_professional() THEN
    RAISE EXCEPTION 'Un profil professionnel vérifié est requis.';
  END IF;
  IF p_approve AND (p_valid_until IS NULL OR p_valid_until < CURRENT_DATE) THEN
    RAISE EXCEPTION 'La date de fin de validité doit être aujourd''hui ou ultérieure.';
  END IF;
  IF NOT p_approve AND length(btrim(COALESCE(p_reason, ''))) < 5 THEN
    RAISE EXCEPTION 'Un motif de refus d''au moins 5 caractères est requis.';
  END IF;

  SELECT * INTO coverage
  FROM ientier.medical_insurance_coverages
  WHERE coverage_id = p_coverage_id
  FOR UPDATE;

  IF NOT FOUND OR coverage.status <> 'pending' THEN
    RAISE EXCEPTION 'Cette demande de couverture n''est plus disponible.';
  END IF;
  IF coverage.patient_id = actor_id THEN
    RAISE EXCEPTION 'Un professionnel ne peut pas valider sa propre couverture.';
  END IF;

  UPDATE ientier.medical_insurance_coverages
  SET status = CASE WHEN p_approve THEN 'verified' ELSE 'rejected' END,
      valid_from = CASE WHEN p_approve THEN CURRENT_DATE ELSE NULL END,
      valid_until = CASE WHEN p_approve THEN p_valid_until ELSE NULL END,
      review_note = CASE
        WHEN p_approve THEN btrim(COALESCE(p_reason, ''))
        ELSE btrim(p_reason)
      END,
      reviewed_by = actor_id,
      reviewed_at = CURRENT_TIMESTAMP
  WHERE coverage_id = p_coverage_id;

  INSERT INTO ientier.notifications(
    patient_id, title, message, type, action_label, source, source_id
  ) VALUES (
    coverage.patient_id,
    CASE WHEN p_approve THEN 'Couverture OFATMA validée' ELSE 'Carte OFATMA à reprendre' END,
    CASE
      WHEN p_approve THEN 'Votre couverture est valide jusqu''au ' || to_char(p_valid_until, 'DD/MM/YYYY') || '. Vous êtes maintenant éligible au Crédit Santé.'
      ELSE 'Votre carte d''assurance n''a pas pu être validée. Consultez le motif et soumettez de nouvelles images.'
    END,
    'security',
    'Voir ma couverture',
    'app',
    p_coverage_id::TEXT
  );
END;
$$;

CREATE OR REPLACE FUNCTION ientier.enforce_valid_insurance_for_health_credit()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM ientier.medical_insurance_coverages c
    WHERE c.patient_id = NEW.patient_id
      AND c.status = 'verified'
      AND c.valid_from <= CURRENT_DATE
      AND c.valid_until >= CURRENT_DATE
  ) THEN
    RAISE EXCEPTION 'Une couverture OFATMA valide est requise pour accéder au Crédit Santé.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_health_credit_application_requires_insurance
BEFORE INSERT ON ientier.health_credit_applications
FOR EACH ROW EXECUTE FUNCTION ientier.enforce_valid_insurance_for_health_credit();

CREATE TRIGGER trg_health_credit_activation_requires_insurance
BEFORE INSERT ON ientier.health_credits
FOR EACH ROW EXECUTE FUNCTION ientier.enforce_valid_insurance_for_health_credit();

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES(
  'insurance-cards',
  'insurance-cards',
  FALSE,
  8388608,
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT(id) DO UPDATE
SET public = FALSE,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

ALTER TABLE ientier.medical_insurance_coverages ENABLE ROW LEVEL SECURITY;

CREATE POLICY medical_insurance_patient_read
ON ientier.medical_insurance_coverages
FOR SELECT TO authenticated
USING (patient_id = ientier.current_actor_id());

CREATE POLICY medical_insurance_professional_read
ON ientier.medical_insurance_coverages
FOR SELECT TO authenticated
USING (ientier.current_actor_is_verified_professional());

CREATE POLICY insurance_cards_patient_insert
ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'insurance-cards'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::TEXT)
);

CREATE POLICY insurance_cards_patient_select
ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'insurance-cards'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid()::TEXT)
    OR ientier.current_actor_is_verified_professional()
  )
);

CREATE POLICY insurance_cards_patient_delete
ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'insurance-cards'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::TEXT)
  AND NOT EXISTS (
    SELECT 1
    FROM ientier.medical_insurance_coverages c
    WHERE c.card_front_path = name OR c.card_back_path = name
  )
);

GRANT SELECT ON ientier.medical_insurance_coverages TO authenticated;
GRANT ALL ON ientier.medical_insurance_coverages TO service_role;

REVOKE ALL ON FUNCTION ientier.current_actor_is_verified_professional()
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION ientier.submit_medical_insurance_coverage(
  VARCHAR,VARCHAR,TEXT,TEXT,VARCHAR,VARCHAR
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION ientier.review_medical_insurance_coverage(
  UUID,BOOLEAN,VARCHAR,DATE
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION ientier.enforce_valid_insurance_for_health_credit()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION ientier.current_actor_is_verified_professional()
  TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.submit_medical_insurance_coverage(
  VARCHAR,VARCHAR,TEXT,TEXT,VARCHAR,VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.review_medical_insurance_coverage(
  UUID,BOOLEAN,VARCHAR,DATE
) TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'ientier'
      AND tablename = 'medical_insurance_coverages'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE ientier.medical_insurance_coverages;
  END IF;
END $$;

COMMIT;
