-- Allow active administrators to review OFATMA requests while preserving a
-- separate audit trail from professional reviews.

BEGIN;

ALTER TABLE ientier.medical_insurance_coverages
  ADD COLUMN reviewed_by_admin VARCHAR(128)
    REFERENCES ientier.administrators(user_id) ON DELETE SET NULL;

ALTER TABLE ientier.medical_insurance_coverages
  ADD CONSTRAINT ck_medical_insurance_single_reviewer
  CHECK (reviewed_by IS NULL OR reviewed_by_admin IS NULL);

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
  actor_is_admin BOOLEAN := ientier.current_actor_is_admin();
  actor_is_professional BOOLEAN :=
    ientier.current_actor_is_verified_professional();
  coverage ientier.medical_insurance_coverages%ROWTYPE;
BEGIN
  IF actor_id IS NULL OR NOT (actor_is_admin OR actor_is_professional) THEN
    RAISE EXCEPTION 'Un administrateur actif ou un professionnel vérifié est requis.';
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
    RAISE EXCEPTION 'Une personne ne peut pas valider sa propre couverture.';
  END IF;

  UPDATE ientier.medical_insurance_coverages
  SET status = CASE WHEN p_approve THEN 'verified' ELSE 'rejected' END,
      valid_from = CASE WHEN p_approve THEN CURRENT_DATE ELSE NULL END,
      valid_until = CASE WHEN p_approve THEN p_valid_until ELSE NULL END,
      review_note = CASE
        WHEN p_approve THEN btrim(COALESCE(p_reason, ''))
        ELSE btrim(p_reason)
      END,
      reviewed_by = CASE WHEN actor_is_admin THEN NULL ELSE actor_id END,
      reviewed_by_admin = CASE WHEN actor_is_admin THEN actor_id ELSE NULL END,
      reviewed_at = CURRENT_TIMESTAMP
  WHERE coverage_id = p_coverage_id;

  INSERT INTO ientier.notifications(
    patient_id, title, message, type, action_label, source, source_id
  ) VALUES (
    coverage.patient_id,
    CASE
      WHEN p_approve THEN 'Couverture OFATMA validée'
      ELSE 'Carte OFATMA à reprendre'
    END,
    CASE
      WHEN p_approve THEN
        'Votre couverture est valide jusqu''au '
        || to_char(p_valid_until, 'DD/MM/YYYY')
        || '. Vous êtes maintenant éligible au Crédit Santé.'
      ELSE
        'Votre carte d''assurance n''a pas pu être validée. Consultez le motif et soumettez de nouvelles images.'
    END,
    'security',
    'Voir ma couverture',
    'app',
    p_coverage_id::TEXT
  );
END;
$$;

REVOKE ALL ON FUNCTION ientier.review_medical_insurance_coverage(
  UUID,BOOLEAN,VARCHAR,DATE
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION ientier.review_medical_insurance_coverage(
  UUID,BOOLEAN,VARCHAR,DATE
) TO authenticated;

COMMIT;
