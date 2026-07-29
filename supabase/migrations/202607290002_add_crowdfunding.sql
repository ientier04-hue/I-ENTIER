-- =============================================================================
-- i-ENTIER -- financement participatif médical vérifié
-- Dépend de 202607260001_initial_ientier_schema.sql et
-- 202607260002_supabase_integration.sql.
-- =============================================================================

BEGIN;

CREATE TABLE ientier.crowdfunding_campaigns (
  campaign_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  beneficiary_name         VARCHAR(120) NOT NULL,
  relationship_to_patient  VARCHAR(80) NOT NULL DEFAULT '',
  title                    VARCHAR(140) NOT NULL,
  story                    VARCHAR(3000) NOT NULL,
  category                 VARCHAR(30) NOT NULL,
  medical_facility         VARCHAR(180) NOT NULL DEFAULT '',
  location                 VARCHAR(160) NOT NULL,
  target_amount            NUMERIC(14, 2) NOT NULL,
  raised_amount            NUMERIC(14, 2) NOT NULL DEFAULT 0,
  contributor_count        INTEGER NOT NULL DEFAULT 0,
  currency                 VARCHAR(3) NOT NULL DEFAULT 'HTG',
  deadline                 TIMESTAMPTZ NOT NULL,
  cover_image_url          TEXT,
  status                   VARCHAR(20) NOT NULL DEFAULT 'pending',
  verification_status      ientier.verification_status NOT NULL DEFAULT 'pending',
  consent_to_publish       BOOLEAN NOT NULL DEFAULT FALSE,
  featured                 BOOLEAN NOT NULL DEFAULT FALSE,
  rejection_reason         VARCHAR(600) NOT NULL DEFAULT '',
  reviewed_at              TIMESTAMPTZ,
  published_at             TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_crowdfunding_beneficiary
    CHECK (length(btrim(beneficiary_name)) BETWEEN 2 AND 120),
  CONSTRAINT ck_crowdfunding_title
    CHECK (length(btrim(title)) BETWEEN 10 AND 140),
  CONSTRAINT ck_crowdfunding_story
    CHECK (length(btrim(story)) BETWEEN 80 AND 3000),
  CONSTRAINT ck_crowdfunding_category
    CHECK (
      category IN (
        'surgery',
        'treatment',
        'medication',
        'maternity',
        'rehabilitation',
        'emergency',
        'other'
      )
    ),
  CONSTRAINT ck_crowdfunding_location
    CHECK (length(btrim(location)) BETWEEN 2 AND 160),
  CONSTRAINT ck_crowdfunding_target
    CHECK (target_amount BETWEEN 1000 AND 100000000),
  CONSTRAINT ck_crowdfunding_raised
    CHECK (raised_amount >= 0),
  CONSTRAINT ck_crowdfunding_contributors
    CHECK (contributor_count >= 0),
  CONSTRAINT ck_crowdfunding_currency
    CHECK (currency IN ('HTG', 'USD')),
  CONSTRAINT ck_crowdfunding_status
    CHECK (
      status IN (
        'pending',
        'active',
        'funded',
        'paused',
        'rejected',
        'closed'
      )
    ),
  CONSTRAINT ck_crowdfunding_publication
    CHECK (
      status NOT IN ('active', 'funded')
      OR (
        verification_status = 'approved'
        AND consent_to_publish
        AND published_at IS NOT NULL
      )
    ),
  CONSTRAINT ck_crowdfunding_rejection
    CHECK (
      verification_status <> 'rejected'
      OR length(btrim(rejection_reason)) > 0
    )
);

COMMENT ON TABLE ientier.crowdfunding_campaigns IS
  'Campagnes médicales soumises par les patients et publiées uniquement après vérification administrative.';
COMMENT ON COLUMN ientier.crowdfunding_campaigns.raised_amount IS
  'Projection calculée exclusivement à partir des contributions confirmées.';

CREATE TABLE ientier.crowdfunding_campaign_contacts (
  campaign_id    UUID PRIMARY KEY
                 REFERENCES ientier.crowdfunding_campaigns(campaign_id)
                 ON DELETE CASCADE,
  creator_id     VARCHAR(128) NOT NULL
                 REFERENCES ientier.app_users(user_id)
                 ON DELETE RESTRICT,
  contact_phone  VARCHAR(40) NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_crowdfunding_private_phone
    CHECK (length(btrim(contact_phone)) BETWEEN 8 AND 40)
);

COMMENT ON TABLE ientier.crowdfunding_campaign_contacts IS
  'Propriétaire et téléphone privés d''une campagne, accessibles uniquement au créateur et aux administrateurs.';

CREATE TABLE ientier.crowdfunding_contributions (
  contribution_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id         UUID NOT NULL
                      REFERENCES ientier.crowdfunding_campaigns(campaign_id)
                      ON DELETE RESTRICT,
  contributor_id      VARCHAR(128) NOT NULL
                      REFERENCES ientier.app_users(user_id)
                      ON DELETE RESTRICT,
  amount              NUMERIC(14, 2) NOT NULL,
  currency            VARCHAR(3) NOT NULL,
  payment_method      VARCHAR(30) NOT NULL,
  payment_status      VARCHAR(24) NOT NULL DEFAULT 'pending_payment',
  public_name         VARCHAR(100) NOT NULL DEFAULT '',
  anonymous           BOOLEAN NOT NULL DEFAULT FALSE,
  supporter_message   VARCHAR(500) NOT NULL DEFAULT '',
  processor_reference VARCHAR(160),
  confirmed_by        VARCHAR(128)
                      REFERENCES ientier.administrators(user_id)
                      ON DELETE SET NULL,
  confirmed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_crowdfunding_contribution_amount
    CHECK (amount BETWEEN 50 AND 10000000),
  CONSTRAINT ck_crowdfunding_contribution_currency
    CHECK (currency IN ('HTG', 'USD')),
  CONSTRAINT ck_crowdfunding_payment_method
    CHECK (payment_method IN ('moncash', 'card', 'bank_transfer')),
  CONSTRAINT ck_crowdfunding_payment_status
    CHECK (
      payment_status IN (
        'pending_payment',
        'confirmed',
        'failed',
        'cancelled',
        'refunded'
      )
    ),
  CONSTRAINT ck_crowdfunding_supporter_message
    CHECK (length(supporter_message) <= 500),
  CONSTRAINT ck_crowdfunding_confirmation
    CHECK (
      payment_status <> 'confirmed'
      OR (
        confirmed_at IS NOT NULL
        AND processor_reference IS NOT NULL
        AND length(btrim(processor_reference)) > 0
      )
    )
);

COMMENT ON TABLE ientier.crowdfunding_contributions IS
  'Intentions de contribution et confirmations de paiement; aucune intention en attente ne modifie le total collecté.';

CREATE TABLE ientier.crowdfunding_campaign_reviews (
  review_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id        UUID NOT NULL
                     REFERENCES ientier.crowdfunding_campaigns(campaign_id)
                     ON DELETE RESTRICT,
  admin_id           VARCHAR(128) NOT NULL
                     REFERENCES ientier.administrators(user_id)
                     ON DELETE RESTRICT,
  previous_status    ientier.verification_status NOT NULL,
  new_status         ientier.verification_status NOT NULL,
  reason             VARCHAR(600) NOT NULL DEFAULT '',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_crowdfunding_review_decision
    CHECK (new_status IN ('approved', 'rejected')),
  CONSTRAINT ck_crowdfunding_review_reason
    CHECK (new_status <> 'rejected' OR length(btrim(reason)) > 0)
);

CREATE INDEX idx_crowdfunding_public_feed
  ON ientier.crowdfunding_campaigns
  (featured DESC, status, verification_status, deadline, created_at DESC);

CREATE INDEX idx_crowdfunding_private_creator
  ON ientier.crowdfunding_campaign_contacts (creator_id, created_at DESC);

CREATE INDEX idx_crowdfunding_contributions_campaign
  ON ientier.crowdfunding_contributions
  (campaign_id, payment_status, created_at DESC);

CREATE INDEX idx_crowdfunding_contributions_owner
  ON ientier.crowdfunding_contributions (contributor_id, created_at DESC);

CREATE TRIGGER trg_00_crowdfunding_campaigns_updated_at
BEFORE UPDATE ON ientier.crowdfunding_campaigns
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

CREATE TRIGGER trg_00_crowdfunding_contributions_updated_at
BEFORE UPDATE ON ientier.crowdfunding_contributions
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

CREATE TRIGGER trg_crowdfunding_reviews_immutable
BEFORE UPDATE OR DELETE ON ientier.crowdfunding_campaign_reviews
FOR EACH ROW EXECUTE FUNCTION ientier.prevent_row_change();

CREATE OR REPLACE FUNCTION ientier.submit_crowdfunding_campaign(
  p_beneficiary_name VARCHAR,
  p_relationship_to_patient VARCHAR,
  p_title VARCHAR,
  p_story VARCHAR,
  p_category VARCHAR,
  p_medical_facility VARCHAR,
  p_location VARCHAR,
  p_contact_phone VARCHAR,
  p_target_amount NUMERIC,
  p_currency VARCHAR,
  p_deadline TIMESTAMPTZ,
  p_cover_image_url TEXT DEFAULT NULL,
  p_consent_to_publish BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := ientier.current_actor_id();
  new_campaign_id UUID;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Une session authentifiée est requise.';
  END IF;
  IF p_deadline <= CURRENT_TIMESTAMP + INTERVAL '1 day'
     OR p_deadline > CURRENT_TIMESTAMP + INTERVAL '1 year' THEN
    RAISE EXCEPTION 'La date de fin doit être comprise entre demain et un an.';
  END IF;
  IF NOT COALESCE(p_consent_to_publish, FALSE) THEN
    RAISE EXCEPTION 'Le consentement à la publication est requis.';
  END IF;

  INSERT INTO ientier.crowdfunding_campaigns (
    beneficiary_name,
    relationship_to_patient,
    title,
    story,
    category,
    medical_facility,
    location,
    target_amount,
    currency,
    deadline,
    cover_image_url,
    consent_to_publish
  )
  VALUES (
    btrim(p_beneficiary_name),
    btrim(COALESCE(p_relationship_to_patient, '')),
    btrim(p_title),
    btrim(p_story),
    p_category,
    btrim(COALESCE(p_medical_facility, '')),
    btrim(p_location),
    p_target_amount,
    upper(p_currency),
    p_deadline,
    NULLIF(btrim(COALESCE(p_cover_image_url, '')), ''),
    TRUE
  )
  RETURNING campaign_id INTO new_campaign_id;

  INSERT INTO ientier.crowdfunding_campaign_contacts (
    campaign_id,
    creator_id,
    contact_phone
  )
  VALUES (
    new_campaign_id,
    actor_id,
    btrim(p_contact_phone)
  );

  RETURN new_campaign_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.review_crowdfunding_campaign(
  p_campaign_id UUID,
  p_admin_id VARCHAR,
  p_new_status ientier.verification_status,
  p_reason VARCHAR DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  old_status ientier.verification_status;
  campaign_deadline TIMESTAMPTZ;
  campaign_consent BOOLEAN;
  normalized_reason VARCHAR(600) := btrim(COALESCE(p_reason, ''));
  new_review_id UUID;
BEGIN
  IF ientier.current_actor_id() IS NULL
     OR ientier.current_actor_id() <> p_admin_id
     OR NOT ientier.current_actor_is_admin() THEN
    RAISE EXCEPTION 'Accès administrateur actif requis.';
  END IF;
  IF p_new_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'La décision doit être approved ou rejected.';
  END IF;
  IF p_new_status = 'rejected' AND normalized_reason = '' THEN
    RAISE EXCEPTION 'Un motif de refus est obligatoire.';
  END IF;
  IF p_new_status = 'approved' THEN
    normalized_reason := '';
  END IF;

  SELECT verification_status, deadline, consent_to_publish
    INTO old_status, campaign_deadline, campaign_consent
  FROM ientier.crowdfunding_campaigns
  WHERE campaign_id = p_campaign_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La campagne n''existe pas.';
  END IF;
  IF old_status = p_new_status THEN
    RAISE EXCEPTION 'Cette décision est déjà appliquée.';
  END IF;
  IF p_new_status = 'approved'
     AND (NOT campaign_consent OR campaign_deadline <= CURRENT_TIMESTAMP) THEN
    RAISE EXCEPTION 'Une campagne expirée ou sans consentement ne peut pas être publiée.';
  END IF;

  UPDATE ientier.crowdfunding_campaigns
  SET verification_status = p_new_status,
      status = CASE
        WHEN p_new_status = 'approved' THEN 'active'
        ELSE 'rejected'
      END,
      rejection_reason = normalized_reason,
      reviewed_at = CURRENT_TIMESTAMP,
      published_at = CASE
        WHEN p_new_status = 'approved' THEN COALESCE(published_at, CURRENT_TIMESTAMP)
        ELSE NULL
      END
  WHERE campaign_id = p_campaign_id;

  INSERT INTO ientier.crowdfunding_campaign_reviews (
    campaign_id,
    admin_id,
    previous_status,
    new_status,
    reason
  )
  VALUES (
    p_campaign_id,
    p_admin_id,
    old_status,
    p_new_status,
    normalized_reason
  )
  RETURNING review_id INTO new_review_id;

  RETURN new_review_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.start_crowdfunding_contribution(
  p_campaign_id UUID,
  p_amount NUMERIC,
  p_payment_method VARCHAR,
  p_public_name VARCHAR DEFAULT '',
  p_anonymous BOOLEAN DEFAULT FALSE,
  p_message VARCHAR DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := ientier.current_actor_id();
  campaign_currency VARCHAR(3);
  new_contribution_id UUID;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Une session authentifiée est requise.';
  END IF;

  SELECT currency
    INTO campaign_currency
  FROM ientier.crowdfunding_campaigns
  WHERE campaign_id = p_campaign_id
    AND status = 'active'
    AND verification_status = 'approved'
    AND deadline > CURRENT_TIMESTAMP
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cette campagne n''accepte plus de contributions.';
  END IF;

  INSERT INTO ientier.crowdfunding_contributions (
    campaign_id,
    contributor_id,
    amount,
    currency,
    payment_method,
    public_name,
    anonymous,
    supporter_message
  )
  VALUES (
    p_campaign_id,
    actor_id,
    p_amount,
    campaign_currency,
    p_payment_method,
    CASE
      WHEN COALESCE(p_anonymous, FALSE) THEN ''
      ELSE btrim(COALESCE(p_public_name, ''))
    END,
    COALESCE(p_anonymous, FALSE),
    btrim(COALESCE(p_message, ''))
  )
  RETURNING contribution_id INTO new_contribution_id;

  RETURN new_contribution_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.confirm_crowdfunding_contribution(
  p_contribution_id UUID,
  p_admin_id VARCHAR,
  p_processor_reference VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  contribution_record ientier.crowdfunding_contributions%ROWTYPE;
BEGIN
  IF ientier.current_actor_id() IS NULL
     OR ientier.current_actor_id() <> p_admin_id
     OR NOT ientier.current_actor_is_admin() THEN
    RAISE EXCEPTION 'Accès administrateur actif requis.';
  END IF;
  IF length(btrim(COALESCE(p_processor_reference, ''))) < 4 THEN
    RAISE EXCEPTION 'Une référence de paiement valide est requise.';
  END IF;

  SELECT *
    INTO contribution_record
  FROM ientier.crowdfunding_contributions
  WHERE contribution_id = p_contribution_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La contribution n''existe pas.';
  END IF;
  IF contribution_record.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'Cette contribution a déjà été traitée.';
  END IF;

  UPDATE ientier.crowdfunding_contributions
  SET payment_status = 'confirmed',
      processor_reference = btrim(p_processor_reference),
      confirmed_by = p_admin_id,
      confirmed_at = CURRENT_TIMESTAMP
  WHERE contribution_id = p_contribution_id;

  UPDATE ientier.crowdfunding_campaigns
  SET raised_amount = raised_amount + contribution_record.amount,
      contributor_count = contributor_count + 1,
      status = CASE
        WHEN raised_amount + contribution_record.amount >= target_amount
          THEN 'funded'
        ELSE status
      END
  WHERE campaign_id = contribution_record.campaign_id;
END;
$$;

-- Point d'entrée réservé au service_role pour un webhook signé de prestataire.
-- Le montant et la devise reçus sont comparés à l'intention originale avant
-- toute modification du total public.
CREATE OR REPLACE FUNCTION ientier.confirm_crowdfunding_contribution_webhook(
  p_contribution_id UUID,
  p_processor_reference VARCHAR,
  p_amount NUMERIC,
  p_currency VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  contribution_record ientier.crowdfunding_contributions%ROWTYPE;
  normalized_reference VARCHAR(160) :=
    btrim(COALESCE(p_processor_reference, ''));
BEGIN
  IF length(normalized_reference) < 4 THEN
    RAISE EXCEPTION 'Une référence de paiement valide est requise.';
  END IF;

  SELECT *
    INTO contribution_record
  FROM ientier.crowdfunding_contributions
  WHERE contribution_id = p_contribution_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La contribution n''existe pas.';
  END IF;
  IF contribution_record.amount <> p_amount
     OR contribution_record.currency <> upper(p_currency) THEN
    RAISE EXCEPTION 'Le montant ou la devise ne correspond pas à l''intention.';
  END IF;
  IF contribution_record.payment_status = 'confirmed' THEN
    IF contribution_record.processor_reference = normalized_reference THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Cette contribution est déjà confirmée avec une autre référence.';
  END IF;
  IF contribution_record.payment_status <> 'pending_payment' THEN
    RAISE EXCEPTION 'Cette contribution ne peut plus être confirmée.';
  END IF;

  UPDATE ientier.crowdfunding_contributions
  SET payment_status = 'confirmed',
      processor_reference = normalized_reference,
      confirmed_at = CURRENT_TIMESTAMP
  WHERE contribution_id = p_contribution_id;

  UPDATE ientier.crowdfunding_campaigns
  SET raised_amount = raised_amount + contribution_record.amount,
      contributor_count = contributor_count + 1,
      status = CASE
        WHEN raised_amount + contribution_record.amount >= target_amount
          THEN 'funded'
        ELSE status
      END
  WHERE campaign_id = contribution_record.campaign_id;
END;
$$;

ALTER TABLE ientier.crowdfunding_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.crowdfunding_campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.crowdfunding_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.crowdfunding_campaign_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY crowdfunding_campaigns_select
ON ientier.crowdfunding_campaigns FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM ientier.crowdfunding_campaign_contacts private_campaign
    WHERE private_campaign.campaign_id =
          crowdfunding_campaigns.campaign_id
      AND private_campaign.creator_id = ientier.current_actor_id()
  )
  OR ientier.current_actor_is_admin()
  OR (
    status IN ('active', 'funded')
    AND verification_status = 'approved'
    AND consent_to_publish
    AND deadline > CURRENT_TIMESTAMP
  )
);

CREATE POLICY crowdfunding_campaign_contacts_select
ON ientier.crowdfunding_campaign_contacts FOR SELECT
TO authenticated
USING (
  creator_id = ientier.current_actor_id()
  OR ientier.current_actor_is_admin()
);

CREATE POLICY crowdfunding_campaigns_admin_update
ON ientier.crowdfunding_campaigns FOR UPDATE
TO authenticated
USING (ientier.current_actor_is_admin())
WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY crowdfunding_contributions_select
ON ientier.crowdfunding_contributions FOR SELECT
TO authenticated
USING (
  contributor_id = ientier.current_actor_id()
  OR ientier.current_actor_is_admin()
  OR EXISTS (
    SELECT 1
    FROM ientier.crowdfunding_campaign_contacts private_campaign
    WHERE private_campaign.campaign_id =
          crowdfunding_contributions.campaign_id
      AND private_campaign.creator_id = ientier.current_actor_id()
  )
);

CREATE POLICY crowdfunding_reviews_admin_select
ON ientier.crowdfunding_campaign_reviews FOR SELECT
TO authenticated
USING (ientier.current_actor_is_admin());

GRANT SELECT ON ientier.crowdfunding_campaigns TO authenticated;
GRANT SELECT ON ientier.crowdfunding_campaign_contacts TO authenticated;
GRANT SELECT ON ientier.crowdfunding_contributions TO authenticated;
GRANT SELECT ON ientier.crowdfunding_campaign_reviews TO authenticated;
GRANT ALL ON
  ientier.crowdfunding_campaigns,
  ientier.crowdfunding_campaign_contacts,
  ientier.crowdfunding_contributions,
  ientier.crowdfunding_campaign_reviews
TO service_role;

REVOKE ALL ON FUNCTION ientier.submit_crowdfunding_campaign(
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR,
  NUMERIC, VARCHAR, TIMESTAMPTZ, TEXT, BOOLEAN
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION ientier.submit_crowdfunding_campaign(
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR,
  NUMERIC, VARCHAR, TIMESTAMPTZ, TEXT, BOOLEAN
) TO authenticated;

REVOKE ALL ON FUNCTION ientier.review_crowdfunding_campaign(
  UUID, VARCHAR, ientier.verification_status, VARCHAR
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION ientier.review_crowdfunding_campaign(
  UUID, VARCHAR, ientier.verification_status, VARCHAR
) TO authenticated;

REVOKE ALL ON FUNCTION ientier.start_crowdfunding_contribution(
  UUID, NUMERIC, VARCHAR, VARCHAR, BOOLEAN, VARCHAR
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION ientier.start_crowdfunding_contribution(
  UUID, NUMERIC, VARCHAR, VARCHAR, BOOLEAN, VARCHAR
) TO authenticated;

REVOKE ALL ON FUNCTION ientier.confirm_crowdfunding_contribution(
  UUID, VARCHAR, VARCHAR
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION ientier.confirm_crowdfunding_contribution(
  UUID, VARCHAR, VARCHAR
) TO authenticated;

REVOKE ALL ON FUNCTION ientier.confirm_crowdfunding_contribution_webhook(
  UUID, VARCHAR, NUMERIC, VARCHAR
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ientier.confirm_crowdfunding_contribution_webhook(
  UUID, VARCHAR, NUMERIC, VARCHAR
) TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'ientier'
      AND tablename = 'crowdfunding_campaigns'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE ientier.crowdfunding_campaigns;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'ientier'
      AND tablename = 'crowdfunding_contributions'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE ientier.crowdfunding_contributions;
  END IF;
END;
$$;

INSERT INTO ientier.health_service_catalog (
  service_key,
  title,
  summary,
  image_path,
  background_color,
  accent_color,
  action_label,
  external_url,
  sort_order
)
VALUES (
  'crowdfunding',
  'Financement solidaire',
  'Mobilisez la communauté pour financer des soins',
  '',
  '#E9F8F3',
  '#087A5B',
  'Découvrir',
  NULL,
  25
)
ON CONFLICT (service_key) DO UPDATE
SET title = EXCLUDED.title,
    summary = EXCLUDED.summary,
    image_path = EXCLUDED.image_path,
    background_color = EXCLUDED.background_color,
    accent_color = EXCLUDED.accent_color,
    action_label = EXCLUDED.action_label,
    external_url = EXCLUDED.external_url,
    sort_order = EXCLUDED.sort_order;

COMMIT;
