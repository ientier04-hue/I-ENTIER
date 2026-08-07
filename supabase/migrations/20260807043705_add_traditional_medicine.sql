-- I-Entier Médecine Traditionnelle
-- Registre vérifié, carnet naturel privé, prévention, orientations et sécurité.

BEGIN;

SET search_path TO ientier, public;

CREATE SCHEMA IF NOT EXISTS ientier_private;
REVOKE ALL ON SCHEMA ientier_private FROM PUBLIC, anon, authenticated;

CREATE TABLE traditional_practitioner_profiles (
  provider_id                 VARCHAR(128) PRIMARY KEY
                              REFERENCES provider_profiles(provider_id) ON DELETE CASCADE,
  experience_years            SMALLINT NOT NULL DEFAULT 0,
  practice_domains            TEXT[] NOT NULL DEFAULT '{}',
  languages                   TEXT[] NOT NULL DEFAULT '{}',
  intervention_zones          TEXT[] NOT NULL DEFAULT '{}',
  identity_status             VARCHAR(20) NOT NULL DEFAULT 'pending',
  attestation_status          VARCHAR(20) NOT NULL DEFAULT 'pending',
  validation_status           VARCHAR(20) NOT NULL DEFAULT 'pending',
  review_reason               VARCHAR(600) NOT NULL DEFAULT '',
  online_available            BOOLEAN NOT NULL DEFAULT FALSE,
  profile_verification_score  SMALLINT NOT NULL DEFAULT 0,
  patient_satisfaction_score  SMALLINT NOT NULL DEFAULT 0,
  compliance_score            SMALLINT NOT NULL DEFAULT 20,
  seniority_score             SMALLINT GENERATED ALWAYS AS (
    LEAST(15, experience_years)
  ) STORED,
  follow_up_quality_score     SMALLINT NOT NULL DEFAULT 0,
  trust_score                 SMALLINT GENERATED ALWAYS AS (
    LEAST(
      100,
      profile_verification_score
        + patient_satisfaction_score
        + compliance_score
        + LEAST(15, experience_years)
        + follow_up_quality_score
    )
  ) STORED,
  validated_by                VARCHAR(128)
                              REFERENCES administrators(user_id) ON DELETE SET NULL,
  validated_at                TIMESTAMPTZ,
  suspended_at                TIMESTAMPTZ,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_experience
    CHECK (experience_years BETWEEN 0 AND 80),
  CONSTRAINT ck_traditional_domains
    CHECK (cardinality(practice_domains) BETWEEN 1 AND 20),
  CONSTRAINT ck_traditional_languages
    CHECK (cardinality(languages) BETWEEN 1 AND 12),
  CONSTRAINT ck_traditional_zones
    CHECK (cardinality(intervention_zones) BETWEEN 1 AND 30),
  CONSTRAINT ck_traditional_identity_status
    CHECK (identity_status IN ('pending', 'verified', 'rejected')),
  CONSTRAINT ck_traditional_attestation_status
    CHECK (attestation_status IN ('pending', 'verified', 'rejected')),
  CONSTRAINT ck_traditional_validation_status
    CHECK (validation_status IN ('pending', 'approved', 'rejected', 'suspended')),
  CONSTRAINT ck_traditional_scores
    CHECK (
      profile_verification_score BETWEEN 0 AND 20
      AND patient_satisfaction_score BETWEEN 0 AND 25
      AND compliance_score BETWEEN 0 AND 20
      AND follow_up_quality_score BETWEEN 0 AND 20
    ),
  CONSTRAINT ck_traditional_review_reason
    CHECK (length(review_reason) <= 600),
  CONSTRAINT ck_traditional_approval
    CHECK (
      validation_status <> 'approved'
      OR (
        identity_status = 'verified'
        AND attestation_status = 'verified'
        AND validated_by IS NOT NULL
        AND validated_at IS NOT NULL
        AND suspended_at IS NULL
      )
    ),
  CONSTRAINT ck_traditional_suspension
    CHECK (
      (validation_status = 'suspended' AND suspended_at IS NOT NULL)
      OR (validation_status <> 'suspended' AND suspended_at IS NULL)
    )
);

COMMENT ON TABLE traditional_practitioner_profiles IS
  'Extension contrôlée d’un profil professionnel pour la médecine traditionnelle.';
COMMENT ON COLUMN traditional_practitioner_profiles.trust_score IS
  'Score explicable sur 100, somme de cinq composantes bornées.';

CREATE INDEX ix_traditional_practitioner_directory
  ON traditional_practitioner_profiles (validation_status, online_available, trust_score DESC);

CREATE TABLE traditional_practitioner_documents (
  document_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id          VARCHAR(128) NOT NULL
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE CASCADE,
  document_type        VARCHAR(30) NOT NULL,
  original_file_name   VARCHAR(220) NOT NULL,
  storage_path         VARCHAR(500) NOT NULL UNIQUE,
  mime_type            VARCHAR(100) NOT NULL,
  review_status        VARCHAR(20) NOT NULL DEFAULT 'pending',
  review_note          VARCHAR(500) NOT NULL DEFAULT '',
  reviewed_by          VARCHAR(128)
                       REFERENCES administrators(user_id) ON DELETE SET NULL,
  reviewed_at          TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_document_type
    CHECK (document_type IN ('identity', 'attestation', 'training', 'other')),
  CONSTRAINT ck_traditional_document_status
    CHECK (review_status IN ('pending', 'verified', 'rejected')),
  CONSTRAINT ck_traditional_document_name
    CHECK (length(btrim(original_file_name)) BETWEEN 1 AND 220),
  CONSTRAINT ck_traditional_document_path
    CHECK (length(btrim(storage_path)) BETWEEN 3 AND 500),
  CONSTRAINT ck_traditional_document_review
    CHECK (
      (review_status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
      OR (review_status <> 'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    )
);

CREATE INDEX ix_traditional_documents_review
  ON traditional_practitioner_documents (review_status, created_at);

CREATE TABLE natural_health_journal_entries (
  entry_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id           VARCHAR(128) NOT NULL
                       REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  practitioner_id      VARCHAR(128)
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE SET NULL,
  entry_type           VARCHAR(24) NOT NULL,
  title                VARCHAR(160) NOT NULL,
  details              VARCHAR(2000) NOT NULL DEFAULT '',
  product_name         VARCHAR(180) NOT NULL DEFAULT '',
  wellness_rating      SMALLINT,
  occurred_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_natural_journal_type
    CHECK (entry_type IN ('consultation', 'recommendation', 'natural_product', 'observation', 'wellbeing')),
  CONSTRAINT ck_natural_journal_title
    CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  CONSTRAINT ck_natural_journal_details
    CHECK (length(details) <= 2000),
  CONSTRAINT ck_natural_journal_product
    CHECK (
      (entry_type = 'natural_product' AND length(btrim(product_name)) BETWEEN 1 AND 180)
      OR (entry_type <> 'natural_product' AND product_name = '')
    ),
  CONSTRAINT ck_natural_journal_wellness
    CHECK (wellness_rating IS NULL OR wellness_rating BETWEEN 1 AND 5)
);

CREATE INDEX ix_natural_journal_patient
  ON natural_health_journal_entries (patient_id, occurred_at DESC);

CREATE TABLE natural_health_sharing_grants (
  grant_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id           VARCHAR(128) NOT NULL
                       REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  practitioner_id      VARCHAR(128) NOT NULL
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE CASCADE,
  can_view_journal     BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at           TIMESTAMPTZ,
  revoked_at           TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_natural_sharing_expiry
    CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE UNIQUE INDEX uq_natural_health_active_grant
  ON natural_health_sharing_grants (patient_id, practitioner_id)
  WHERE revoked_at IS NULL;

CREATE TABLE traditional_prevention_recommendations (
  recommendation_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id           VARCHAR(128) NOT NULL
                       REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  practitioner_id      VARCHAR(128) NOT NULL
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE RESTRICT,
  recommendation_type  VARCHAR(24) NOT NULL,
  title                VARCHAR(160) NOT NULL,
  content              VARCHAR(2000) NOT NULL,
  reminder_at          TIMESTAMPTZ,
  clinical_scope_acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_recommendation_type
    CHECK (recommendation_type IN ('prevention', 'wellbeing', 'follow_up', 'hygiene')),
  CONSTRAINT ck_traditional_recommendation_title
    CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  CONSTRAINT ck_traditional_recommendation_content
    CHECK (length(btrim(content)) BETWEEN 4 AND 2000),
  CONSTRAINT ck_traditional_recommendation_scope
    CHECK (clinical_scope_acknowledged)
);

CREATE INDEX ix_traditional_recommendations_patient
  ON traditional_prevention_recommendations (patient_id, created_at DESC);
CREATE INDEX ix_traditional_recommendations_reminders
  ON traditional_prevention_recommendations (reminder_at)
  WHERE reminder_at IS NOT NULL;

CREATE TABLE traditional_care_orientations (
  orientation_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id           VARCHAR(128) NOT NULL
                       REFERENCES patient_profiles(patient_id) ON DELETE RESTRICT,
  practitioner_id      VARCHAR(128) NOT NULL
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE RESTRICT,
  target_type          VARCHAR(24) NOT NULL,
  target_provider_id   VARCHAR(128)
                       REFERENCES provider_profiles(provider_id) ON DELETE SET NULL,
  target_name          VARCHAR(160) NOT NULL,
  reason               VARCHAR(1000) NOT NULL,
  urgency              VARCHAR(16) NOT NULL DEFAULT 'routine',
  status               VARCHAR(20) NOT NULL DEFAULT 'proposed',
  appointment_id       VARCHAR(160)
                       REFERENCES appointments(appointment_id) ON DELETE SET NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_orientation_target
    CHECK (target_type IN ('doctor', 'nurse', 'midwife', 'psychologist', 'mobile_clinic', 'hospital')),
  CONSTRAINT ck_traditional_orientation_name
    CHECK (length(btrim(target_name)) BETWEEN 2 AND 160),
  CONSTRAINT ck_traditional_orientation_reason
    CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  CONSTRAINT ck_traditional_orientation_urgency
    CHECK (urgency IN ('routine', 'priority', 'emergency')),
  CONSTRAINT ck_traditional_orientation_status
    CHECK (status IN ('proposed', 'accepted', 'booked', 'declined', 'completed'))
);

CREATE INDEX ix_traditional_orientations_patient
  ON traditional_care_orientations (patient_id, created_at DESC);
CREATE INDEX ix_traditional_orientations_practitioner
  ON traditional_care_orientations (practitioner_id, created_at DESC);

CREATE TABLE traditional_practitioner_ratings (
  rating_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id       VARCHAR(160) NOT NULL UNIQUE
                       REFERENCES appointments(appointment_id) ON DELETE CASCADE,
  patient_id           VARCHAR(128) NOT NULL
                       REFERENCES patient_profiles(patient_id) ON DELETE CASCADE,
  practitioner_id      VARCHAR(128) NOT NULL
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE CASCADE,
  satisfaction         SMALLINT NOT NULL,
  follow_up_quality    SMALLINT NOT NULL,
  comment              VARCHAR(800) NOT NULL DEFAULT '',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_rating_values
    CHECK (satisfaction BETWEEN 1 AND 5 AND follow_up_quality BETWEEN 1 AND 5),
  CONSTRAINT ck_traditional_rating_comment
    CHECK (length(comment) <= 800)
);

CREATE INDEX ix_traditional_ratings_practitioner
  ON traditional_practitioner_ratings (practitioner_id, created_at DESC);

CREATE TABLE traditional_safety_reports (
  report_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id          VARCHAR(128) NOT NULL REFERENCES app_users(user_id) ON DELETE RESTRICT,
  practitioner_id      VARCHAR(128) NOT NULL
                       REFERENCES traditional_practitioner_profiles(provider_id) ON DELETE RESTRICT,
  category             VARCHAR(32) NOT NULL,
  details              VARCHAR(1600) NOT NULL,
  credibility_status   VARCHAR(24) NOT NULL DEFAULT 'pending_review',
  resolution_status    VARCHAR(20) NOT NULL DEFAULT 'open',
  admin_note           VARCHAR(1000) NOT NULL DEFAULT '',
  reviewed_by          VARCHAR(128)
                       REFERENCES administrators(user_id) ON DELETE SET NULL,
  reviewed_at          TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_report_category
    CHECK (category IN ('dangerous_advice', 'fake_profile', 'misleading_advertising', 'inappropriate_behavior')),
  CONSTRAINT ck_traditional_report_details
    CHECK (length(btrim(details)) BETWEEN 10 AND 1600),
  CONSTRAINT ck_traditional_report_credibility
    CHECK (credibility_status IN ('pending_review', 'credible', 'not_credible')),
  CONSTRAINT ck_traditional_report_resolution
    CHECK (resolution_status IN ('open', 'investigating', 'resolved', 'dismissed')),
  CONSTRAINT ck_traditional_report_review
    CHECK (
      (credibility_status = 'pending_review' AND reviewed_by IS NULL AND reviewed_at IS NULL)
      OR (credibility_status <> 'pending_review' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    )
);

CREATE INDEX ix_traditional_reports_queue
  ON traditional_safety_reports (credibility_status, resolution_status, created_at);

CREATE TABLE traditional_prevention_content (
  content_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title                VARCHAR(180) NOT NULL,
  summary              VARCHAR(1200) NOT NULL,
  category             VARCHAR(24) NOT NULL,
  region_code          VARCHAR(80) NOT NULL DEFAULT 'HT',
  season_key           VARCHAR(40) NOT NULL DEFAULT 'all',
  priority             SMALLINT NOT NULL DEFAULT 0,
  active_from          TIMESTAMPTZ,
  active_until         TIMESTAMPTZ,
  is_published         BOOLEAN NOT NULL DEFAULT FALSE,
  reviewed_by          VARCHAR(128)
                       REFERENCES administrators(user_id) ON DELETE SET NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_traditional_content_title
    CHECK (length(btrim(title)) BETWEEN 2 AND 180),
  CONSTRAINT ck_traditional_content_summary
    CHECK (length(btrim(summary)) BETWEEN 10 AND 1200),
  CONSTRAINT ck_traditional_content_category
    CHECK (category IN ('seasonal', 'common_illness', 'hygiene', 'regional_alert')),
  CONSTRAINT ck_traditional_content_period
    CHECK (active_from IS NULL OR active_until IS NULL OR active_until >= active_from),
  CONSTRAINT ck_traditional_content_priority
    CHECK (priority BETWEEN 0 AND 100)
);

CREATE INDEX ix_traditional_prevention_feed
  ON traditional_prevention_content (is_published, region_code, priority DESC, created_at DESC);

CREATE OR REPLACE FUNCTION validate_traditional_practitioner_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM provider_profiles p
    WHERE p.provider_id = NEW.provider_id
      AND p.account_type = 'professional'
  ) THEN
    RAISE EXCEPTION 'Un profil professionnel est requis.';
  END IF;

  IF TG_OP = 'INSERT' AND NOT current_actor_is_admin() THEN
    IF NEW.provider_id <> current_actor_id()
       OR NEW.identity_status <> 'pending'
       OR NEW.attestation_status <> 'pending'
       OR NEW.validation_status <> 'pending'
       OR NEW.profile_verification_score <> 0
       OR NEW.patient_satisfaction_score <> 0
       OR NEW.compliance_score <> 20
       OR NEW.follow_up_quality_score <> 0 THEN
      RAISE EXCEPTION 'Le demandeur ne peut pas prévalider son dossier.';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND NOT current_actor_is_admin() THEN
    IF NEW.provider_id IS DISTINCT FROM OLD.provider_id
       OR NEW.identity_status IS DISTINCT FROM OLD.identity_status
       OR NEW.attestation_status IS DISTINCT FROM OLD.attestation_status
       OR NEW.validation_status IS DISTINCT FROM OLD.validation_status
       OR NEW.review_reason IS DISTINCT FROM OLD.review_reason
       OR NEW.profile_verification_score IS DISTINCT FROM OLD.profile_verification_score
       OR NEW.patient_satisfaction_score IS DISTINCT FROM OLD.patient_satisfaction_score
       OR NEW.compliance_score IS DISTINCT FROM OLD.compliance_score
       OR NEW.follow_up_quality_score IS DISTINCT FROM OLD.follow_up_quality_score
       OR NEW.validated_by IS DISTINCT FROM OLD.validated_by
       OR NEW.validated_at IS DISTINCT FROM OLD.validated_at
       OR NEW.suspended_at IS DISTINCT FROM OLD.suspended_at THEN
      RAISE EXCEPTION 'Les champs de confiance sont réservés à I-Entier.';
    END IF;
    IF OLD.validation_status = 'approved'
       AND (
         NEW.experience_years IS DISTINCT FROM OLD.experience_years
         OR NEW.practice_domains IS DISTINCT FROM OLD.practice_domains
         OR NEW.languages IS DISTINCT FROM OLD.languages
         OR NEW.intervention_zones IS DISTINCT FROM OLD.intervention_zones
       ) THEN
      RAISE EXCEPTION 'Une modification du dossier vérifié doit être examinée par I-Entier.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_traditional_document()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT current_actor_is_admin() THEN
    IF NEW.provider_id <> current_actor_id()
       OR NEW.review_status <> 'pending'
       OR NEW.reviewed_by IS NOT NULL
       OR NEW.reviewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'Le demandeur ne peut pas valider son justificatif.';
    END IF;
  ELSIF TG_OP = 'UPDATE' AND NOT current_actor_is_admin() THEN
    IF NEW.provider_id IS DISTINCT FROM OLD.provider_id
       OR NEW.document_type IS DISTINCT FROM OLD.document_type
       OR NEW.review_status IS DISTINCT FROM OLD.review_status
       OR NEW.review_note IS DISTINCT FROM OLD.review_note
       OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
       OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'La validation du justificatif est réservée à I-Entier.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_traditional_orientation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.orientation_id IS DISTINCT FROM OLD.orientation_id
       OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.practitioner_id IS DISTINCT FROM OLD.practitioner_id
       OR NEW.target_type IS DISTINCT FROM OLD.target_type
       OR NEW.target_provider_id IS DISTINCT FROM OLD.target_provider_id
       OR NEW.target_name IS DISTINCT FROM OLD.target_name
       OR NEW.reason IS DISTINCT FROM OLD.reason
       OR NEW.urgency IS DISTINCT FROM OLD.urgency
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Les données cliniques de l’orientation sont immuables.';
    END IF;
    IF current_actor_id() = OLD.patient_id
       AND NOT (
         OLD.status = 'proposed'
         AND NEW.status IN ('accepted', 'declined', 'booked')
       ) THEN
      RAISE EXCEPTION 'Cette transition d’orientation n’est pas autorisée.';
    END IF;
    IF NEW.appointment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM appointments a
         WHERE a.appointment_id = NEW.appointment_id
           AND a.patient_id = NEW.patient_id
       ) THEN
      RAISE EXCEPTION 'Le rendez-vous lié n’appartient pas au patient orienté.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION protect_traditional_recommendation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NEW.recommendation_id IS DISTINCT FROM OLD.recommendation_id
     OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
     OR NEW.practitioner_id IS DISTINCT FROM OLD.practitioner_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'L’auteur et le destinataire de la recommandation sont immuables.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ientier_private.refresh_traditional_trust_score()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  avg_satisfaction NUMERIC;
  avg_follow_up NUMERIC;
BEGIN
  SELECT AVG(satisfaction), AVG(follow_up_quality)
    INTO avg_satisfaction, avg_follow_up
  FROM traditional_practitioner_ratings
  WHERE practitioner_id = NEW.practitioner_id;

  UPDATE traditional_practitioner_profiles
  SET patient_satisfaction_score = LEAST(25, ROUND(COALESCE(avg_satisfaction, 0) * 5)::SMALLINT),
      follow_up_quality_score = LEAST(20, ROUND(COALESCE(avg_follow_up, 0) * 4)::SMALLINT)
  WHERE provider_id = NEW.practitioner_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ientier_private.notify_traditional_orientation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  practitioner_name TEXT;
BEGIN
  SELECT display_name INTO practitioner_name
  FROM provider_profiles
  WHERE provider_id = NEW.practitioner_id;

  INSERT INTO notifications (
    notification_id, patient_id, title, message, type,
    is_read, action_label, source, source_id
  ) VALUES (
    'traditional_orientation_' || NEW.orientation_id::TEXT,
    NEW.patient_id,
    CASE WHEN NEW.urgency = 'emergency'
      THEN 'Orientation urgente'
      ELSE 'Nouvelle orientation de soins'
    END,
    COALESCE(practitioner_name, 'Votre praticien')
      || ' vous oriente vers ' || NEW.target_name || '.',
    CASE WHEN NEW.urgency = 'emergency' THEN 'security'::notification_type
      ELSE 'appointment'::notification_type
    END,
    FALSE,
    'Prendre rendez-vous',
    CASE WHEN NEW.urgency = 'emergency' THEN 'security'::notification_source
      ELSE 'app'::notification_source
    END,
    NEW.orientation_id::TEXT
  )
  ON CONFLICT (notification_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ientier_private.notify_traditional_recommendation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  practitioner_name TEXT;
BEGIN
  SELECT display_name INTO practitioner_name
  FROM provider_profiles
  WHERE provider_id = NEW.practitioner_id;

  INSERT INTO notifications (
    notification_id, patient_id, title, message, type,
    is_read, scheduled_at, action_label, source, source_id
  ) VALUES (
    'traditional_recommendation_' || NEW.recommendation_id::TEXT,
    NEW.patient_id,
    CASE WHEN NEW.reminder_at IS NULL
      THEN 'Nouvelle recommandation de prévention'
      ELSE 'Rappel de prévention'
    END,
    LEFT(
      COALESCE(practitioner_name, 'Votre praticien')
        || ' : ' || NEW.title,
      300
    ),
    'reminder',
    FALSE,
    NEW.reminder_at,
    'Ouvrir mon carnet',
    'app',
    NEW.recommendation_id::TEXT
  )
  ON CONFLICT (notification_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ientier_private.suspend_credible_traditional_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NEW.credibility_status = 'credible'
     AND OLD.credibility_status IS DISTINCT FROM 'credible' THEN
    UPDATE traditional_practitioner_profiles
    SET validation_status = 'suspended',
        online_available = FALSE,
        compliance_score = 0,
        suspended_at = CURRENT_TIMESTAMP,
        review_reason = 'Suspension préventive après un signalement crédible.'
    WHERE provider_id = NEW.practitioner_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_traditional_profile_updated_at
BEFORE UPDATE ON traditional_practitioner_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_validate_traditional_profile
BEFORE INSERT OR UPDATE ON traditional_practitioner_profiles
FOR EACH ROW EXECUTE FUNCTION validate_traditional_practitioner_profile();
CREATE TRIGGER trg_validate_traditional_document
BEFORE INSERT OR UPDATE ON traditional_practitioner_documents
FOR EACH ROW EXECUTE FUNCTION validate_traditional_document();
CREATE TRIGGER trg_natural_journal_updated_at
BEFORE UPDATE ON natural_health_journal_entries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_natural_sharing_updated_at
BEFORE UPDATE ON natural_health_sharing_grants
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_traditional_recommendation_updated_at
BEFORE UPDATE ON traditional_prevention_recommendations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_protect_traditional_recommendation
BEFORE UPDATE ON traditional_prevention_recommendations
FOR EACH ROW EXECUTE FUNCTION protect_traditional_recommendation();
CREATE TRIGGER trg_traditional_orientation_updated_at
BEFORE UPDATE ON traditional_care_orientations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_validate_traditional_orientation
BEFORE UPDATE ON traditional_care_orientations
FOR EACH ROW EXECUTE FUNCTION validate_traditional_orientation();
CREATE TRIGGER trg_traditional_report_updated_at
BEFORE UPDATE ON traditional_safety_reports
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_traditional_content_updated_at
BEFORE UPDATE ON traditional_prevention_content
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_refresh_traditional_trust
AFTER INSERT OR UPDATE OF satisfaction, follow_up_quality
ON traditional_practitioner_ratings
FOR EACH ROW EXECUTE FUNCTION ientier_private.refresh_traditional_trust_score();
CREATE TRIGGER trg_notify_traditional_orientation
AFTER INSERT ON traditional_care_orientations
FOR EACH ROW EXECUTE FUNCTION ientier_private.notify_traditional_orientation();
CREATE TRIGGER trg_notify_traditional_recommendation
AFTER INSERT ON traditional_prevention_recommendations
FOR EACH ROW EXECUTE FUNCTION ientier_private.notify_traditional_recommendation();
CREATE TRIGGER trg_suspend_credible_traditional_report
AFTER UPDATE OF credibility_status ON traditional_safety_reports
FOR EACH ROW EXECUTE FUNCTION ientier_private.suspend_credible_traditional_report();

ALTER TABLE traditional_practitioner_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE traditional_practitioner_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE natural_health_journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE natural_health_sharing_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE traditional_prevention_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE traditional_care_orientations ENABLE ROW LEVEL SECURITY;
ALTER TABLE traditional_practitioner_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE traditional_safety_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE traditional_prevention_content ENABLE ROW LEVEL SECURITY;

CREATE POLICY traditional_profiles_select
ON traditional_practitioner_profiles FOR SELECT TO authenticated
USING (
  provider_id = (SELECT current_actor_id())
  OR current_actor_is_admin()
  OR (
    validation_status = 'approved'
    AND suspended_at IS NULL
    AND EXISTS (
      SELECT 1 FROM provider_profiles p
      WHERE p.provider_id = traditional_practitioner_profiles.provider_id
        AND p.verification_status = 'approved'
        AND p.is_visible = TRUE
    )
  )
);

CREATE POLICY traditional_profiles_insert
ON traditional_practitioner_profiles FOR INSERT TO authenticated
WITH CHECK (provider_id = (SELECT current_actor_id()));

CREATE POLICY traditional_profiles_update
ON traditional_practitioner_profiles FOR UPDATE TO authenticated
USING (provider_id = (SELECT current_actor_id()) OR current_actor_is_admin())
WITH CHECK (provider_id = (SELECT current_actor_id()) OR current_actor_is_admin());

CREATE POLICY traditional_documents_select
ON traditional_practitioner_documents FOR SELECT TO authenticated
USING (provider_id = (SELECT current_actor_id()) OR current_actor_is_admin());
CREATE POLICY traditional_documents_insert
ON traditional_practitioner_documents FOR INSERT TO authenticated
WITH CHECK (provider_id = (SELECT current_actor_id()));
CREATE POLICY traditional_documents_update
ON traditional_practitioner_documents FOR UPDATE TO authenticated
USING (current_actor_is_admin())
WITH CHECK (current_actor_is_admin());
CREATE POLICY traditional_documents_delete
ON traditional_practitioner_documents FOR DELETE TO authenticated
USING (provider_id = (SELECT current_actor_id()) AND review_status = 'pending');

CREATE POLICY natural_journal_select
ON natural_health_journal_entries FOR SELECT TO authenticated
USING (
  patient_id = (SELECT current_actor_id())
  OR current_actor_is_admin()
  OR EXISTS (
    SELECT 1 FROM natural_health_sharing_grants g
    WHERE g.patient_id = natural_health_journal_entries.patient_id
      AND g.practitioner_id = (SELECT current_actor_id())
      AND g.can_view_journal = TRUE
      AND g.revoked_at IS NULL
      AND (g.expires_at IS NULL OR g.expires_at > CURRENT_TIMESTAMP)
  )
);
CREATE POLICY natural_journal_owner_insert
ON natural_health_journal_entries FOR INSERT TO authenticated
WITH CHECK (patient_id = (SELECT current_actor_id()));
CREATE POLICY natural_journal_owner_update
ON natural_health_journal_entries FOR UPDATE TO authenticated
USING (patient_id = (SELECT current_actor_id()))
WITH CHECK (patient_id = (SELECT current_actor_id()));
CREATE POLICY natural_journal_owner_delete
ON natural_health_journal_entries FOR DELETE TO authenticated
USING (patient_id = (SELECT current_actor_id()));

CREATE POLICY natural_sharing_select
ON natural_health_sharing_grants FOR SELECT TO authenticated
USING (
  patient_id = (SELECT current_actor_id())
  OR practitioner_id = (SELECT current_actor_id())
  OR current_actor_is_admin()
);
CREATE POLICY natural_sharing_owner_insert
ON natural_health_sharing_grants FOR INSERT TO authenticated
WITH CHECK (patient_id = (SELECT current_actor_id()));
CREATE POLICY natural_sharing_owner_update
ON natural_health_sharing_grants FOR UPDATE TO authenticated
USING (patient_id = (SELECT current_actor_id()))
WITH CHECK (patient_id = (SELECT current_actor_id()));
CREATE POLICY natural_sharing_owner_delete
ON natural_health_sharing_grants FOR DELETE TO authenticated
USING (patient_id = (SELECT current_actor_id()));

CREATE POLICY traditional_recommendations_select
ON traditional_prevention_recommendations FOR SELECT TO authenticated
USING (
  patient_id = (SELECT current_actor_id())
  OR practitioner_id = (SELECT current_actor_id())
  OR current_actor_is_admin()
);
CREATE POLICY traditional_recommendations_practitioner_insert
ON traditional_prevention_recommendations FOR INSERT TO authenticated
WITH CHECK (
  practitioner_id = (SELECT current_actor_id())
  AND EXISTS (
    SELECT 1 FROM traditional_practitioner_profiles t
    WHERE t.provider_id = (SELECT current_actor_id())
      AND t.validation_status = 'approved'
  )
  AND EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.patient_id = traditional_prevention_recommendations.patient_id
      AND a.provider_id = (SELECT current_actor_id())
  )
);
CREATE POLICY traditional_recommendations_practitioner_update
ON traditional_prevention_recommendations FOR UPDATE TO authenticated
USING (practitioner_id = (SELECT current_actor_id()))
WITH CHECK (practitioner_id = (SELECT current_actor_id()));

CREATE POLICY traditional_orientations_select
ON traditional_care_orientations FOR SELECT TO authenticated
USING (
  patient_id = (SELECT current_actor_id())
  OR practitioner_id = (SELECT current_actor_id())
  OR current_actor_is_admin()
);
CREATE POLICY traditional_orientations_practitioner_insert
ON traditional_care_orientations FOR INSERT TO authenticated
WITH CHECK (
  practitioner_id = (SELECT current_actor_id())
  AND EXISTS (
    SELECT 1 FROM traditional_practitioner_profiles t
    WHERE t.provider_id = (SELECT current_actor_id())
      AND t.validation_status = 'approved'
  )
  AND EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.patient_id = traditional_care_orientations.patient_id
      AND a.provider_id = (SELECT current_actor_id())
  )
);
CREATE POLICY traditional_orientations_patient_update
ON traditional_care_orientations FOR UPDATE TO authenticated
USING (patient_id = (SELECT current_actor_id()))
WITH CHECK (patient_id = (SELECT current_actor_id()));
CREATE POLICY traditional_orientations_practitioner_update
ON traditional_care_orientations FOR UPDATE TO authenticated
USING (practitioner_id = (SELECT current_actor_id()))
WITH CHECK (practitioner_id = (SELECT current_actor_id()));

CREATE POLICY traditional_ratings_select
ON traditional_practitioner_ratings FOR SELECT TO authenticated
USING (
  patient_id = (SELECT current_actor_id())
  OR practitioner_id = (SELECT current_actor_id())
  OR current_actor_is_admin()
);
CREATE POLICY traditional_ratings_patient_insert
ON traditional_practitioner_ratings FOR INSERT TO authenticated
WITH CHECK (
  patient_id = (SELECT current_actor_id())
  AND EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.appointment_id = traditional_practitioner_ratings.appointment_id
      AND a.patient_id = traditional_practitioner_ratings.patient_id
      AND a.provider_id = traditional_practitioner_ratings.practitioner_id
      AND a.status = 'confirmed'
  )
);

CREATE POLICY traditional_reports_select
ON traditional_safety_reports FOR SELECT TO authenticated
USING (reporter_id = (SELECT current_actor_id()) OR current_actor_is_admin());
CREATE POLICY traditional_reports_insert
ON traditional_safety_reports FOR INSERT TO authenticated
WITH CHECK (
  reporter_id = (SELECT current_actor_id())
  AND credibility_status = 'pending_review'
  AND resolution_status = 'open'
);
CREATE POLICY traditional_reports_admin_update
ON traditional_safety_reports FOR UPDATE TO authenticated
USING (current_actor_is_admin())
WITH CHECK (current_actor_is_admin());

CREATE POLICY traditional_content_select
ON traditional_prevention_content FOR SELECT TO authenticated
USING (
  current_actor_is_admin()
  OR (
    is_published = TRUE
    AND (active_from IS NULL OR active_from <= CURRENT_TIMESTAMP)
    AND (active_until IS NULL OR active_until >= CURRENT_TIMESTAMP)
  )
);
CREATE POLICY traditional_content_admin_write
ON traditional_prevention_content FOR ALL TO authenticated
USING (current_actor_is_admin())
WITH CHECK (current_actor_is_admin());

GRANT SELECT, INSERT, UPDATE ON traditional_practitioner_profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  traditional_practitioner_documents,
  natural_health_journal_entries,
  natural_health_sharing_grants,
  traditional_prevention_recommendations,
  traditional_care_orientations
TO authenticated;
GRANT SELECT, INSERT ON traditional_practitioner_ratings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON traditional_safety_reports TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON traditional_prevention_content TO authenticated;

GRANT ALL ON
  traditional_practitioner_profiles,
  traditional_practitioner_documents,
  natural_health_journal_entries,
  natural_health_sharing_grants,
  traditional_prevention_recommendations,
  traditional_care_orientations,
  traditional_practitioner_ratings,
  traditional_safety_reports,
  traditional_prevention_content
TO service_role;

REVOKE ALL ON FUNCTION validate_traditional_practitioner_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION validate_traditional_practitioner_profile() TO authenticated, service_role;
REVOKE ALL ON FUNCTION validate_traditional_document() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION validate_traditional_document() TO authenticated, service_role;
REVOKE ALL ON FUNCTION validate_traditional_orientation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION validate_traditional_orientation() TO authenticated, service_role;
REVOKE ALL ON FUNCTION protect_traditional_recommendation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION protect_traditional_recommendation() TO authenticated, service_role;
REVOKE ALL ON FUNCTION ientier_private.refresh_traditional_trust_score() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ientier_private.notify_traditional_orientation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ientier_private.notify_traditional_recommendation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ientier_private.suspend_credible_traditional_report() FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA ientier_private TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ientier_private TO service_role;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'traditional-practitioner-documents',
  'traditional-practitioner-documents',
  FALSE,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE
SET public = FALSE,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY traditional_storage_owner_select
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'traditional-practitioner-documents'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
    OR ientier.current_actor_is_admin()
  )
);
CREATE POLICY traditional_storage_owner_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'traditional-practitioner-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
);
CREATE POLICY traditional_storage_owner_update
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'traditional-practitioner-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
)
WITH CHECK (
  bucket_id = 'traditional-practitioner-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
);
CREATE POLICY traditional_storage_owner_delete
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'traditional-practitioner-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
);

DO $$
DECLARE
  table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'traditional_practitioner_profiles',
    'traditional_practitioner_documents',
    'natural_health_journal_entries',
    'natural_health_sharing_grants',
    'traditional_prevention_recommendations',
    'traditional_care_orientations',
    'traditional_practitioner_ratings',
    'traditional_safety_reports',
    'traditional_prevention_content'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'ientier'
        AND tablename = table_name
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE ientier.%I',
        table_name
      );
    END IF;
  END LOOP;
END;
$$;

INSERT INTO traditional_prevention_content (
  title, summary, category, region_code, season_key, priority, is_published
) VALUES
  (
    'Chaleur et hydratation sûre',
    'Buvez régulièrement de l’eau potable, recherchez l’ombre et consultez rapidement en cas de confusion, malaise ou perte de connaissance.',
    'seasonal', 'HT', 'hot-season', 90, TRUE
  ),
  (
    'Hygiène des mains au quotidien',
    'Lavez-vous les mains avec de l’eau propre et du savon avant de cuisiner ou de manger et après les toilettes.',
    'hygiene', 'HT', 'all', 75, TRUE
  ),
  (
    'Diarrhée : reconnaître les signes d’alerte',
    'Une grande faiblesse, l’impossibilité de boire, du sang dans les selles ou des signes de déshydratation nécessitent une évaluation médicale rapide.',
    'common_illness', 'HT', 'all', 85, TRUE
  );

INSERT INTO health_service_catalog (
  service_key, title, summary, image_path, background_color,
  accent_color, action_label, sort_order, active
) VALUES (
  'medecine-traditionnelle',
  'Médecine Traditionnelle',
  'Prévention et bien-être avec des praticiens vérifiés',
  '',
  '#E7F5EC',
  '#18794E',
  'Découvrir',
  125,
  TRUE
)
ON CONFLICT (service_key) DO UPDATE
SET title = EXCLUDED.title,
    summary = EXCLUDED.summary,
    image_path = EXCLUDED.image_path,
    background_color = EXCLUDED.background_color,
    accent_color = EXCLUDED.accent_color,
    action_label = EXCLUDED.action_label,
    sort_order = EXCLUDED.sort_order,
    active = EXCLUDED.active;

COMMIT;
