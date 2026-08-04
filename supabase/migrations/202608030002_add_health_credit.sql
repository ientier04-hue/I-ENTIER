-- =============================================================================
-- i-ENTIER -- Crédit Santé, Score Santé Financier et accompagnement solidaire
-- =============================================================================

BEGIN;

CREATE TABLE ientier.health_credit_applications (
  application_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.patient_profiles(patient_id) ON DELETE RESTRICT,
  patient_name_snapshot VARCHAR(140) NOT NULL,
  requested_amount NUMERIC(14,2) NOT NULL CHECK (requested_amount BETWEEN 500 AND 10000000),
  medical_reason VARCHAR(2000) NOT NULL CHECK (length(btrim(medical_reason)) BETWEEN 10 AND 2000),
  monthly_income NUMERIC(14,2) NOT NULL CHECK (monthly_income >= 0),
  monthly_expenses NUMERIC(14,2) NOT NULL CHECK (monthly_expenses >= 0),
  employer VARCHAR(180) NOT NULL DEFAULT '',
  disposable_income NUMERIC(14,2) NOT NULL,
  recommended_installments SMALLINT NOT NULL CHECK (recommended_installments BETWEEN 2 AND 12),
  estimated_installment NUMERIC(14,2) NOT NULL CHECK (estimated_installment > 0),
  preliminary_score SMALLINT NOT NULL CHECK (preliminary_score BETWEEN 0 AND 100),
  validated_reference_count SMALLINT NOT NULL DEFAULT 0 CHECK (validated_reference_count BETWEEN 0 AND 5),
  status VARCHAR(30) NOT NULL DEFAULT 'pending_references'
    CHECK (status IN ('pending_references','under_review','approved','rejected','cancelled')),
  decision_reason VARCHAR(1000) NOT NULL DEFAULT '',
  reviewed_by VARCHAR(128) REFERENCES ientier.administrators(user_id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (monthly_expenses <= monthly_income * 2 + 1),
  CHECK (status <> 'rejected' OR length(btrim(decision_reason)) > 0)
);

CREATE TABLE ientier.health_credit_references (
  reference_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES ientier.health_credit_applications(application_id) ON DELETE CASCADE,
  full_name VARCHAR(140) NOT NULL CHECK (length(btrim(full_name)) BETWEEN 3 AND 140),
  phone VARCHAR(40) NOT NULL CHECK (length(btrim(phone)) BETWEEN 8 AND 40),
  relationship VARCHAR(100) NOT NULL CHECK (length(btrim(relationship)) BETWEEN 2 AND 100),
  reference_type VARCHAR(20) NOT NULL CHECK (reference_type IN ('guarantor','community')),
  validation_status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (validation_status IN ('pending','validated','rejected')),
  validation_note VARCHAR(500) NOT NULL DEFAULT '',
  validated_by VARCHAR(128) REFERENCES ientier.administrators(user_id) ON DELETE SET NULL,
  validated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (application_id, phone)
);

CREATE TABLE ientier.health_credit_documents (
  document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES ientier.health_credit_applications(application_id) ON DELETE CASCADE,
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.app_users(user_id) ON DELETE RESTRICT,
  storage_path TEXT NOT NULL UNIQUE,
  file_name VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  file_size_bytes INTEGER NOT NULL CHECK (file_size_bytes BETWEEN 1 AND 10485760),
  verification_status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending','verified','rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ientier.health_credits (
  credit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL UNIQUE REFERENCES ientier.health_credit_applications(application_id) ON DELETE RESTRICT,
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.patient_profiles(patient_id) ON DELETE RESTRICT,
  principal_amount NUMERIC(14,2) NOT NULL CHECK (principal_amount > 0),
  outstanding_balance NUMERIC(14,2) NOT NULL CHECK (outstanding_balance >= 0),
  installment_count SMALLINT NOT NULL CHECK (installment_count BETWEEN 2 AND 12),
  financial_health_score SMALLINT NOT NULL DEFAULT 100 CHECK (financial_health_score BETWEEN 0 AND 120),
  consecutive_late_payments SMALLINT NOT NULL DEFAULT 0 CHECK (consecutive_late_payments >= 0),
  status VARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','paid','suspended','defaulted')),
  access_suspended_until TIMESTAMPTZ,
  default_flagged_at TIMESTAMPTZ,
  default_justification VARCHAR(1000) NOT NULL DEFAULT '',
  activated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ientier.health_credit_installments (
  installment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_id UUID NOT NULL REFERENCES ientier.health_credits(credit_id) ON DELETE RESTRICT,
  installment_number SMALLINT NOT NULL CHECK (installment_number > 0),
  due_date DATE NOT NULL,
  amount_due NUMERIC(14,2) NOT NULL CHECK (amount_due > 0),
  amount_paid NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  status VARCHAR(20) NOT NULL DEFAULT 'upcoming'
    CHECK (status IN ('upcoming','due','partial','paid','late','waived')),
  late_penalty_applied BOOLEAN NOT NULL DEFAULT FALSE,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (credit_id, installment_number),
  CHECK (amount_paid <= amount_due)
);

CREATE TABLE ientier.health_credit_payments (
  payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_id UUID NOT NULL REFERENCES ientier.health_credits(credit_id) ON DELETE RESTRICT,
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.app_users(user_id) ON DELETE RESTRICT,
  amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  payment_method VARCHAR(30) NOT NULL CHECK (payment_method IN ('moncash','card','bank_transfer','cash_partner')),
  patient_reference VARCHAR(180) NOT NULL DEFAULT '',
  payment_status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (payment_status IN ('pending','confirmed','rejected','cancelled')),
  rejection_reason VARCHAR(500) NOT NULL DEFAULT '',
  confirmed_by VARCHAR(128) REFERENCES ientier.administrators(user_id) ON DELETE SET NULL,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (payment_status <> 'rejected' OR length(btrim(rejection_reason)) > 0)
);

CREATE TABLE ientier.health_financial_score_events (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_id UUID NOT NULL REFERENCES ientier.health_credits(credit_id) ON DELETE RESTRICT,
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.app_users(user_id) ON DELETE RESTRICT,
  previous_score SMALLINT NOT NULL CHECK (previous_score BETWEEN 0 AND 120),
  new_score SMALLINT NOT NULL CHECK (new_score BETWEEN 0 AND 120),
  variation SMALLINT NOT NULL,
  reason VARCHAR(180) NOT NULL,
  payment_id UUID REFERENCES ientier.health_credit_payments(payment_id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (new_score - previous_score = variation)
);

CREATE TABLE ientier.health_social_assessments (
  assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.patient_profiles(patient_id) ON DELETE RESTRICT,
  monthly_household_income NUMERIC(14,2) NOT NULL CHECK (monthly_household_income >= 0),
  household_size SMALLINT NOT NULL CHECK (household_size BETWEEN 1 AND 30),
  housing_status VARCHAR(20) NOT NULL CHECK (housing_status IN ('stable','precarious','homeless')),
  income_stability VARCHAR(20) NOT NULL CHECK (income_stability IN ('stable','irregular','none')),
  food_insecurity BOOLEAN NOT NULL DEFAULT FALSE,
  catastrophic_health_expense BOOLEAN NOT NULL DEFAULT FALSE,
  disability_or_dependency BOOLEAN NOT NULL DEFAULT FALSE,
  single_parent BOOLEAN NOT NULL DEFAULT FALSE,
  vulnerability_score SMALLINT NOT NULL CHECK (vulnerability_score BETWEEN 0 AND 100),
  vulnerability_level VARCHAR(20) NOT NULL CHECK (vulnerability_level IN ('low','moderate','vulnerable','critical')),
  recognized_vulnerable BOOLEAN NOT NULL,
  notes VARCHAR(1000) NOT NULL DEFAULT '',
  assessed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ientier.health_partner_centers (
  center_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(180) NOT NULL,
  address VARCHAR(300) NOT NULL,
  commune VARCHAR(120) NOT NULL,
  phone VARCHAR(40) NOT NULL DEFAULT '',
  services_summary VARCHAR(1000) NOT NULL DEFAULT '',
  low_cost BOOLEAN NOT NULL DEFAULT TRUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ientier.health_solidarity_requests (
  solidarity_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id VARCHAR(128) NOT NULL REFERENCES ientier.patient_profiles(patient_id) ON DELETE RESTRICT,
  assessment_id UUID NOT NULL REFERENCES ientier.health_social_assessments(assessment_id) ON DELETE RESTRICT,
  requested_amount NUMERIC(14,2) NOT NULL CHECK (requested_amount > 0),
  approved_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (approved_amount >= 0),
  funded_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (funded_amount >= 0),
  medical_need VARCHAR(2000) NOT NULL CHECK (length(btrim(medical_need)) BETWEEN 10 AND 2000),
  status VARCHAR(24) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','partially_funded','funded','in_care','completed','rejected')),
  partner_center_id UUID REFERENCES ientier.health_partner_centers(center_id) ON DELETE SET NULL,
  social_worker VARCHAR(140) NOT NULL DEFAULT '',
  medical_coordinator VARCHAR(140) NOT NULL DEFAULT '',
  follow_up_note VARCHAR(2000) NOT NULL DEFAULT '',
  reviewed_by VARCHAR(128) REFERENCES ientier.administrators(user_id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (funded_amount <= GREATEST(approved_amount, requested_amount)),
  CHECK (status <> 'rejected' OR length(btrim(follow_up_note)) > 0)
);

CREATE INDEX idx_health_credit_applications_queue ON ientier.health_credit_applications(status, created_at DESC);
CREATE INDEX idx_health_credit_applications_patient ON ientier.health_credit_applications(patient_id, created_at DESC);
CREATE INDEX idx_health_credit_installments_due ON ientier.health_credit_installments(status, due_date);
CREATE INDEX idx_health_credit_payments_queue ON ientier.health_credit_payments(payment_status, created_at DESC);
CREATE INDEX idx_health_score_patient ON ientier.health_financial_score_events(patient_id, created_at DESC);
CREATE INDEX idx_health_social_vulnerable ON ientier.health_social_assessments(recognized_vulnerable, assessed_at DESC);
CREATE INDEX idx_health_solidarity_queue ON ientier.health_solidarity_requests(status, created_at DESC);

CREATE TRIGGER trg_health_credit_applications_updated BEFORE UPDATE ON ientier.health_credit_applications
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_health_credits_updated BEFORE UPDATE ON ientier.health_credits
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_health_installments_updated BEFORE UPDATE ON ientier.health_credit_installments
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_health_payments_updated BEFORE UPDATE ON ientier.health_credit_payments
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_health_solidarity_updated BEFORE UPDATE ON ientier.health_solidarity_requests
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_health_score_immutable BEFORE UPDATE OR DELETE ON ientier.health_financial_score_events
FOR EACH ROW EXECUTE FUNCTION ientier.prevent_row_change();

CREATE OR REPLACE FUNCTION ientier.health_credit_risk_level(p_score INTEGER)
RETURNS VARCHAR LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_score >= 100 THEN 'excellent' WHEN p_score >= 85 THEN 'good'
              WHEN p_score >= 70 THEN 'medium' ELSE 'high' END::VARCHAR;
$$;

CREATE OR REPLACE FUNCTION ientier.submit_health_credit_application(
  p_patient_name VARCHAR, p_requested_amount NUMERIC, p_medical_reason VARCHAR,
  p_monthly_income NUMERIC, p_monthly_expenses NUMERIC, p_employer VARCHAR,
  p_references JSONB, p_documents JSONB DEFAULT '[]'::JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE
  actor_id VARCHAR(128) := ientier.current_actor_id(); new_id UUID;
  disposable NUMERIC; affordable NUMERIC; term_count INTEGER; initial_score INTEGER;
  ref JSONB; doc JSONB; reference_total INTEGER; document_total INTEGER;
  repaid_history INTEGER; default_history INTEGER;
BEGIN
  IF actor_id IS NULL THEN RAISE EXCEPTION 'Une session authentifiée est requise.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM ientier.patient_profiles WHERE patient_id = actor_id) THEN
    RAISE EXCEPTION 'Un profil patient complet est requis.';
  END IF;
  reference_total := jsonb_array_length(COALESCE(p_references, '[]'::JSONB));
  document_total := jsonb_array_length(COALESCE(p_documents, '[]'::JSONB));
  IF reference_total NOT BETWEEN 3 AND 5 THEN RAISE EXCEPTION 'Ajoutez entre 3 et 5 références.'; END IF;
  IF document_total < 1 THEN RAISE EXCEPTION 'Au moins un justificatif de revenus est requis.'; END IF;
  IF EXISTS (SELECT 1 FROM ientier.health_credits WHERE patient_id = actor_id AND status IN ('active','suspended','defaulted')) THEN
    RAISE EXCEPTION 'Un crédit non soldé existe déjà pour ce patient.';
  END IF;
  disposable := GREATEST(p_monthly_income - p_monthly_expenses, 0);
  affordable := GREATEST(disposable * 0.35, 1);
  term_count := LEAST(12, GREATEST(2, CEIL(p_requested_amount / affordable)::INTEGER));
  SELECT count(*) FILTER (WHERE status='paid'), count(*) FILTER (WHERE status IN ('defaulted','suspended'))
    INTO repaid_history, default_history
  FROM ientier.health_credits WHERE patient_id=actor_id;
  initial_score := LEAST(100, GREATEST(0,
    ROUND(25 + CASE WHEN disposable > 0 THEN 20 ELSE 0 END
      + CASE WHEN p_requested_amount / term_count <= affordable THEN 40 ELSE 0 END
      + CASE WHEN p_monthly_income > 0 AND p_monthly_expenses / NULLIF(p_monthly_income,0) <= 0.75 THEN 10 ELSE 0 END
      + LEAST(repaid_history * 5, 10) - default_history * 25)::INTEGER));
  INSERT INTO ientier.health_credit_applications (
    patient_id, patient_name_snapshot, requested_amount, medical_reason, monthly_income,
    monthly_expenses, employer, disposable_income, recommended_installments,
    estimated_installment, preliminary_score
  ) VALUES (
    actor_id, btrim(p_patient_name), p_requested_amount, btrim(p_medical_reason),
    p_monthly_income, p_monthly_expenses, btrim(COALESCE(p_employer,'')), disposable,
    term_count, ROUND(p_requested_amount / term_count, 2), initial_score
  ) RETURNING application_id INTO new_id;
  FOR ref IN SELECT value FROM jsonb_array_elements(p_references) LOOP
    INSERT INTO ientier.health_credit_references(application_id, full_name, phone, relationship, reference_type)
    VALUES (new_id, btrim(ref->>'full_name'), btrim(ref->>'phone'), btrim(ref->>'relationship'), ref->>'reference_type');
  END LOOP;
  FOR doc IN SELECT value FROM jsonb_array_elements(p_documents) LOOP
    IF split_part(doc->>'storage_path','/',1) <> actor_id THEN RAISE EXCEPTION 'Chemin de justificatif invalide.'; END IF;
    INSERT INTO ientier.health_credit_documents(application_id, patient_id, storage_path, file_name, mime_type, file_size_bytes)
    VALUES (new_id, actor_id, doc->>'storage_path', doc->>'file_name', doc->>'mime_type', (doc->>'file_size_bytes')::INTEGER);
  END LOOP;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.validate_health_credit_reference(
  p_reference_id UUID, p_admin_id VARCHAR, p_valid BOOLEAN, p_note VARCHAR DEFAULT ''
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE app_id UUID; validated_count INTEGER;
BEGIN
  IF ientier.current_actor_id() <> p_admin_id OR NOT ientier.current_actor_is_admin() THEN RAISE EXCEPTION 'Accès administrateur requis.'; END IF;
  UPDATE ientier.health_credit_references SET validation_status = CASE WHEN p_valid THEN 'validated' ELSE 'rejected' END,
    validation_note = btrim(COALESCE(p_note,'')), validated_by = p_admin_id, validated_at = CURRENT_TIMESTAMP
  WHERE reference_id = p_reference_id RETURNING application_id INTO app_id;
  IF app_id IS NULL THEN RAISE EXCEPTION 'Référence introuvable.'; END IF;
  SELECT count(*) INTO validated_count FROM ientier.health_credit_references WHERE application_id = app_id AND validation_status = 'validated';
  UPDATE ientier.health_credit_applications SET validated_reference_count = validated_count,
    status = CASE WHEN status IN ('approved','rejected','cancelled') THEN status
                  WHEN validated_count >= 3 THEN 'under_review' ELSE 'pending_references' END WHERE application_id = app_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.review_health_credit_application(
  p_application_id UUID, p_admin_id VARCHAR, p_approve BOOLEAN, p_reason VARCHAR DEFAULT ''
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE app ientier.health_credit_applications%ROWTYPE; new_credit UUID; amount_piece NUMERIC; i INTEGER; due DATE;
BEGIN
  IF ientier.current_actor_id() <> p_admin_id OR NOT ientier.current_actor_is_admin() THEN RAISE EXCEPTION 'Accès administrateur requis.'; END IF;
  SELECT * INTO app FROM ientier.health_credit_applications WHERE application_id = p_application_id FOR UPDATE;
  IF NOT FOUND OR app.status IN ('approved','rejected','cancelled') THEN RAISE EXCEPTION 'Demande indisponible.'; END IF;
  IF p_approve AND (app.validated_reference_count < 3 OR app.preliminary_score < 60) THEN RAISE EXCEPTION 'Les critères minimaux ne sont pas satisfaits.'; END IF;
  IF NOT p_approve AND btrim(COALESCE(p_reason,'')) = '' THEN RAISE EXCEPTION 'Un motif de refus est requis.'; END IF;
  UPDATE ientier.health_credit_applications SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
    decision_reason = CASE WHEN p_approve THEN '' ELSE btrim(p_reason) END, reviewed_by = p_admin_id, reviewed_at = CURRENT_TIMESTAMP
  WHERE application_id = p_application_id;
  IF NOT p_approve THEN
    INSERT INTO ientier.notifications(patient_id,title,message,type,source,source_id)
    VALUES(app.patient_id,'Demande de Crédit Santé','Votre demande n’a pas été approuvée. Consultez le motif dans Crédit Santé.','security','app',p_application_id::TEXT);
    RETURN NULL;
  END IF;
  INSERT INTO ientier.health_credits(application_id, patient_id, principal_amount, outstanding_balance, installment_count)
  VALUES(app.application_id, app.patient_id, app.requested_amount, app.requested_amount, app.recommended_installments)
  RETURNING credit_id INTO new_credit;
  amount_piece := ROUND(app.requested_amount / app.recommended_installments, 2);
  FOR i IN 1..app.recommended_installments LOOP
    due := (CURRENT_DATE + (i || ' month')::INTERVAL)::DATE;
    INSERT INTO ientier.health_credit_installments(credit_id, installment_number, due_date, amount_due)
    VALUES(new_credit, i, due, CASE WHEN i = app.recommended_installments THEN app.requested_amount - amount_piece * (i-1) ELSE amount_piece END);
    INSERT INTO ientier.notifications(patient_id,title,message,type,scheduled_at,action_label,source,source_id)
    VALUES(app.patient_id,'Échéance Crédit Santé','Votre échéance n°'||i||' arrive dans 3 jours.','reminder',due::TIMESTAMPTZ - INTERVAL '3 days','Voir l’échéancier','app',new_credit::TEXT);
    INSERT INTO ientier.notifications(patient_id,title,message,type,scheduled_at,action_label,source,source_id)
    VALUES(app.patient_id,'Suivi d’échéance','Vérifiez le statut de votre échéance n°'||i||'.','reminder',due::TIMESTAMPTZ + INTERVAL '1 day','Gérer mon crédit','app',new_credit::TEXT);
  END LOOP;
  INSERT INTO ientier.health_financial_score_events(credit_id,patient_id,previous_score,new_score,variation,reason)
  VALUES(new_credit,app.patient_id,100,100,0,'Score initial après approbation');
  INSERT INTO ientier.notifications(patient_id,title,message,type,source,source_id)
  VALUES(app.patient_id,'Crédit Santé approuvé','Vos soins peuvent être pris en charge. Votre Score Santé Financier débute à 100.','security','app',new_credit::TEXT);
  RETURN new_credit;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.submit_health_credit_payment(
  p_credit_id UUID, p_amount NUMERIC, p_payment_method VARCHAR, p_patient_reference VARCHAR DEFAULT ''
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE actor_id VARCHAR(128) := ientier.current_actor_id(); balance NUMERIC; new_id UUID;
BEGIN
  SELECT outstanding_balance INTO balance FROM ientier.health_credits WHERE credit_id=p_credit_id AND patient_id=actor_id AND status IN ('active','suspended');
  IF balance IS NULL THEN RAISE EXCEPTION 'Crédit actif introuvable.'; END IF;
  IF p_amount <= 0 OR p_amount > balance THEN RAISE EXCEPTION 'Montant de paiement invalide.'; END IF;
  INSERT INTO ientier.health_credit_payments(credit_id,patient_id,amount,payment_method,patient_reference)
  VALUES(p_credit_id,actor_id,p_amount,p_payment_method,btrim(COALESCE(p_patient_reference,''))) RETURNING payment_id INTO new_id;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.review_health_credit_payment(
  p_payment_id UUID, p_admin_id VARCHAR, p_confirm BOOLEAN, p_reason VARCHAR DEFAULT ''
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE pay ientier.health_credit_payments%ROWTYPE; credit ientier.health_credits%ROWTYPE; inst ientier.health_credit_installments%ROWTYPE;
  remaining NUMERIC; applied NUMERIC; old_score INTEGER; new_score INTEGER; change INTEGER;
  late BOOLEAN := FALSE; unpenalized_late BOOLEAN := FALSE;
BEGIN
  IF ientier.current_actor_id() <> p_admin_id OR NOT ientier.current_actor_is_admin() THEN RAISE EXCEPTION 'Accès administrateur requis.'; END IF;
  SELECT * INTO pay FROM ientier.health_credit_payments WHERE payment_id=p_payment_id FOR UPDATE;
  IF NOT FOUND OR pay.payment_status <> 'pending' THEN RAISE EXCEPTION 'Paiement indisponible.'; END IF;
  IF NOT p_confirm THEN
    IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Un motif est requis.'; END IF;
    UPDATE ientier.health_credit_payments SET payment_status='rejected', rejection_reason=btrim(p_reason), confirmed_by=p_admin_id, confirmed_at=CURRENT_TIMESTAMP WHERE payment_id=p_payment_id;
    RETURN;
  END IF;
  SELECT * INTO credit FROM ientier.health_credits WHERE credit_id=pay.credit_id FOR UPDATE;
  remaining := LEAST(pay.amount, credit.outstanding_balance);
  FOR inst IN SELECT * FROM ientier.health_credit_installments WHERE credit_id=credit.credit_id AND status NOT IN ('paid','waived') ORDER BY installment_number FOR UPDATE LOOP
    EXIT WHEN remaining <= 0;
    applied := LEAST(remaining, inst.amount_due-inst.amount_paid);
    late := late OR CURRENT_DATE > inst.due_date;
    unpenalized_late := unpenalized_late OR (CURRENT_DATE > inst.due_date AND NOT inst.late_penalty_applied);
    UPDATE ientier.health_credit_installments SET amount_paid=amount_paid+applied,
      status=CASE WHEN amount_paid+applied>=amount_due THEN 'paid' WHEN CURRENT_DATE>due_date THEN 'late' ELSE 'partial' END,
      late_penalty_applied=late_penalty_applied OR CURRENT_DATE>due_date,
      paid_at=CASE WHEN amount_paid+applied>=amount_due THEN CURRENT_TIMESTAMP ELSE paid_at END WHERE installment_id=inst.installment_id;
    remaining := remaining-applied;
  END LOOP;
  old_score := credit.financial_health_score;
  change := CASE WHEN unpenalized_late THEN -LEAST(25,5+(credit.consecutive_late_payments*5))
                 WHEN late THEN 0 ELSE CASE WHEN old_score<100 THEN 3 ELSE 1 END END;
  new_score := LEAST(120,GREATEST(0,old_score+change));
  UPDATE ientier.health_credit_payments SET payment_status='confirmed',confirmed_by=p_admin_id,confirmed_at=CURRENT_TIMESTAMP WHERE payment_id=p_payment_id;
  UPDATE ientier.health_credits SET outstanding_balance=GREATEST(0,outstanding_balance-pay.amount), financial_health_score=new_score,
    consecutive_late_payments=CASE WHEN unpenalized_late THEN consecutive_late_payments+1 WHEN late THEN consecutive_late_payments ELSE 0 END,
    status=CASE WHEN outstanding_balance-pay.amount<=0 THEN 'paid'
                WHEN unpenalized_late AND (consecutive_late_payments+1)>=3 THEN 'suspended'
                WHEN status='suspended' AND access_suspended_until>CURRENT_TIMESTAMP THEN 'suspended' ELSE 'active' END,
    access_suspended_until=CASE WHEN unpenalized_late AND (consecutive_late_payments+1)>=3 THEN CURRENT_TIMESTAMP+INTERVAL '90 days' ELSE access_suspended_until END,
    completed_at=CASE WHEN outstanding_balance-pay.amount<=0 THEN CURRENT_TIMESTAMP ELSE completed_at END WHERE credit_id=credit.credit_id;
  INSERT INTO ientier.health_financial_score_events(credit_id,patient_id,previous_score,new_score,variation,reason,payment_id)
  VALUES(credit.credit_id,pay.patient_id,old_score,new_score,new_score-old_score,CASE WHEN late THEN 'Paiement reçu en retard' ELSE 'Paiement reçu à temps' END,pay.payment_id);
END;
$$;

CREATE OR REPLACE FUNCTION ientier.refresh_health_credit_overdues(p_admin_id VARCHAR)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE affected INTEGER := 0; inst ientier.health_credit_installments%ROWTYPE;
  credit ientier.health_credits%ROWTYPE; old_score INTEGER; new_score INTEGER; score_change INTEGER;
BEGIN
  IF ientier.current_actor_id() <> p_admin_id OR NOT ientier.current_actor_is_admin() THEN RAISE EXCEPTION 'Accès administrateur requis.'; END IF;
  FOR inst IN SELECT * FROM ientier.health_credit_installments
    WHERE due_date<CURRENT_DATE AND amount_paid<amount_due AND NOT late_penalty_applied
      AND status IN ('upcoming','due','partial','late') FOR UPDATE LOOP
    SELECT * INTO credit FROM ientier.health_credits WHERE credit_id=inst.credit_id FOR UPDATE;
    old_score := credit.financial_health_score;
    score_change := -LEAST(25,5+(credit.consecutive_late_payments*5));
    new_score := GREATEST(0,old_score+score_change);
    UPDATE ientier.health_credit_installments SET status='late',late_penalty_applied=TRUE WHERE installment_id=inst.installment_id;
    UPDATE ientier.health_credits SET financial_health_score=new_score,
      consecutive_late_payments=consecutive_late_payments+1,
      status=CASE WHEN consecutive_late_payments+1>=3 THEN 'suspended' ELSE status END,
      access_suspended_until=CASE WHEN consecutive_late_payments+1>=3 THEN CURRENT_TIMESTAMP+INTERVAL '90 days' ELSE access_suspended_until END
    WHERE credit_id=credit.credit_id;
    INSERT INTO ientier.health_financial_score_events(credit_id,patient_id,previous_score,new_score,variation,reason)
    VALUES(credit.credit_id,credit.patient_id,old_score,new_score,new_score-old_score,'Échéance en retard');
    affected := affected+1;
  END LOOP;
  UPDATE ientier.health_credit_installments SET status='due' WHERE due_date=CURRENT_DATE AND status='upcoming';
  RETURN affected;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.flag_health_credit_default(
  p_credit_id UUID, p_admin_id VARCHAR, p_has_justification BOOLEAN,
  p_justification VARCHAR DEFAULT ''
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE credit ientier.health_credits%ROWTYPE; new_score INTEGER;
BEGIN
  IF ientier.current_actor_id() <> p_admin_id OR NOT ientier.current_actor_is_admin() THEN
    RAISE EXCEPTION 'Accès administrateur requis.';
  END IF;
  SELECT * INTO credit FROM ientier.health_credits WHERE credit_id=p_credit_id FOR UPDATE;
  IF NOT FOUND OR credit.status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'Crédit indisponible.'; END IF;
  IF credit.default_flagged_at IS NOT NULL THEN RAISE EXCEPTION 'Ce défaut a déjà été qualifié.'; END IF;
  IF p_has_justification AND btrim(COALESCE(p_justification,''))='' THEN
    RAISE EXCEPTION 'La justification du patient est requise.';
  END IF;
  IF p_has_justification THEN
    UPDATE ientier.health_credits SET default_justification=btrim(p_justification) WHERE credit_id=p_credit_id;
    RETURN;
  END IF;
  new_score := GREATEST(0,credit.financial_health_score-30);
  UPDATE ientier.health_credits SET financial_health_score=new_score,status='suspended',
    access_suspended_until=CURRENT_TIMESTAMP+INTERVAL '180 days',default_justification='',default_flagged_at=CURRENT_TIMESTAMP WHERE credit_id=p_credit_id;
  INSERT INTO ientier.health_financial_score_events(credit_id,patient_id,previous_score,new_score,variation,reason)
  VALUES(credit.credit_id,credit.patient_id,credit.financial_health_score,new_score,new_score-credit.financial_health_score,'Défaut de paiement sans justification');
  INSERT INTO ientier.notifications(patient_id,title,message,type,source,source_id)
  VALUES(credit.patient_id,'Accès Crédit Santé suspendu','Un défaut de paiement sans justification a entraîné une suspension temporaire. Contactez l’accompagnement i-ENTIER.','security','app',credit.credit_id::TEXT);
END;
$$;

CREATE OR REPLACE FUNCTION ientier.submit_health_social_assessment(
  p_household_income NUMERIC, p_household_size INTEGER, p_housing_status VARCHAR,
  p_income_stability VARCHAR, p_food_insecurity BOOLEAN, p_catastrophic_health_expense BOOLEAN,
  p_disability_or_dependency BOOLEAN, p_single_parent BOOLEAN, p_notes VARCHAR DEFAULT ''
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE actor_id VARCHAR(128):=ientier.current_actor_id(); score INTEGER:=0; level VARCHAR; new_id UUID;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM ientier.patient_profiles WHERE patient_id=actor_id) THEN RAISE EXCEPTION 'Profil patient requis.'; END IF;
  score := score + CASE WHEN p_household_income/GREATEST(p_household_size,1)<5000 THEN 30 WHEN p_household_income/GREATEST(p_household_size,1)<10000 THEN 18 ELSE 4 END;
  score := score + CASE p_housing_status WHEN 'homeless' THEN 25 WHEN 'precarious' THEN 14 ELSE 0 END;
  score := score + CASE p_income_stability WHEN 'none' THEN 20 WHEN 'irregular' THEN 10 ELSE 0 END;
  score := LEAST(100,score + CASE WHEN p_food_insecurity THEN 12 ELSE 0 END + CASE WHEN p_catastrophic_health_expense THEN 15 ELSE 0 END + CASE WHEN p_disability_or_dependency THEN 10 ELSE 0 END + CASE WHEN p_single_parent THEN 8 ELSE 0 END);
  level := CASE WHEN score>=75 THEN 'critical' WHEN score>=50 THEN 'vulnerable' WHEN score>=30 THEN 'moderate' ELSE 'low' END;
  INSERT INTO ientier.health_social_assessments(patient_id,monthly_household_income,household_size,housing_status,income_stability,
    food_insecurity,catastrophic_health_expense,disability_or_dependency,single_parent,vulnerability_score,vulnerability_level,recognized_vulnerable,notes)
  VALUES(actor_id,p_household_income,p_household_size,p_housing_status,p_income_stability,p_food_insecurity,p_catastrophic_health_expense,
    p_disability_or_dependency,p_single_parent,score,level,score>=50,btrim(COALESCE(p_notes,''))) RETURNING assessment_id INTO new_id;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.submit_health_solidarity_request(
  p_assessment_id UUID, p_requested_amount NUMERIC, p_medical_need VARCHAR
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
DECLARE actor_id VARCHAR(128):=ientier.current_actor_id(); new_id UUID;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM ientier.health_social_assessments WHERE assessment_id=p_assessment_id AND patient_id=actor_id AND recognized_vulnerable) THEN RAISE EXCEPTION 'Une reconnaissance de vulnérabilité est requise.'; END IF;
  INSERT INTO ientier.health_solidarity_requests(patient_id,assessment_id,requested_amount,medical_need)
  VALUES(actor_id,p_assessment_id,p_requested_amount,btrim(p_medical_need)) RETURNING solidarity_request_id INTO new_id;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.manage_health_solidarity_request(
  p_request_id UUID,p_admin_id VARCHAR,p_status VARCHAR,p_approved_amount NUMERIC,p_funded_amount NUMERIC,
  p_partner_center_id UUID,p_social_worker VARCHAR,p_medical_coordinator VARCHAR,p_follow_up_note VARCHAR
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ientier, pg_temp AS $$
BEGIN
  IF ientier.current_actor_id()<>p_admin_id OR NOT ientier.current_actor_is_admin() THEN RAISE EXCEPTION 'Accès administrateur requis.'; END IF;
  UPDATE ientier.health_solidarity_requests SET status=p_status,approved_amount=COALESCE(p_approved_amount,0),funded_amount=COALESCE(p_funded_amount,0),
    partner_center_id=p_partner_center_id,social_worker=btrim(COALESCE(p_social_worker,'')),medical_coordinator=btrim(COALESCE(p_medical_coordinator,'')),
    follow_up_note=btrim(COALESCE(p_follow_up_note,'')),reviewed_by=p_admin_id,reviewed_at=CURRENT_TIMESTAMP WHERE solidarity_request_id=p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Dossier introuvable.'; END IF;
END;
$$;

INSERT INTO ientier.health_partner_centers(name,address,commune,phone,services_summary) VALUES
('Centre de santé communautaire Saint-Martin','Delmas 18, Route de Delmas','Delmas','+509 2813-0001','Médecine générale, maternité, pharmacie sociale'),
('Clinique solidaire Espoir','Avenue Christophe, près de la place Jérémie','Port-au-Prince','+509 2813-0002','Consultations, pédiatrie et soins chroniques'),
('Centre médical communautaire du Sud','Route Nationale #2','Les Cayes','+509 2813-0003','Urgences de proximité, laboratoire et santé maternelle');

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('health-credit-documents','health-credit-documents',FALSE,10485760,ARRAY['image/jpeg','image/png','image/webp','application/pdf'])
ON CONFLICT(id) DO UPDATE SET public=FALSE,file_size_limit=EXCLUDED.file_size_limit,allowed_mime_types=EXCLUDED.allowed_mime_types;

ALTER TABLE ientier.health_credit_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_credit_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_credit_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_credits ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_credit_installments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_credit_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_financial_score_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_social_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_partner_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.health_solidarity_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY health_credit_applications_read ON ientier.health_credit_applications FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY health_credit_references_read ON ientier.health_credit_references FOR SELECT TO authenticated USING(ientier.current_actor_is_admin() OR EXISTS(SELECT 1 FROM ientier.health_credit_applications a WHERE a.application_id=health_credit_references.application_id AND a.patient_id=ientier.current_actor_id()));
CREATE POLICY health_credit_documents_read ON ientier.health_credit_documents FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY health_credits_read ON ientier.health_credits FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY health_installments_read ON ientier.health_credit_installments FOR SELECT TO authenticated USING(ientier.current_actor_is_admin() OR EXISTS(SELECT 1 FROM ientier.health_credits c WHERE c.credit_id=health_credit_installments.credit_id AND c.patient_id=ientier.current_actor_id()));
CREATE POLICY health_payments_read ON ientier.health_credit_payments FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY health_score_read ON ientier.health_financial_score_events FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY health_social_read ON ientier.health_social_assessments FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY health_centers_read ON ientier.health_partner_centers FOR SELECT TO authenticated USING(active OR ientier.current_actor_is_admin());
CREATE POLICY health_solidarity_read ON ientier.health_solidarity_requests FOR SELECT TO authenticated USING(patient_id=ientier.current_actor_id() OR ientier.current_actor_is_admin());

CREATE POLICY health_credit_storage_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='health-credit-documents' AND (storage.foldername(name))[1]=auth.uid()::TEXT);
CREATE POLICY health_credit_storage_select ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='health-credit-documents' AND ((storage.foldername(name))[1]=auth.uid()::TEXT OR ientier.current_actor_is_admin()));

GRANT SELECT ON ientier.health_credit_applications,ientier.health_credit_references,ientier.health_credit_documents,
  ientier.health_credits,ientier.health_credit_installments,ientier.health_credit_payments,ientier.health_financial_score_events,
  ientier.health_social_assessments,ientier.health_partner_centers,ientier.health_solidarity_requests TO authenticated;
GRANT ALL ON ientier.health_credit_applications,ientier.health_credit_references,ientier.health_credit_documents,
  ientier.health_credits,ientier.health_credit_installments,ientier.health_credit_payments,ientier.health_financial_score_events,
  ientier.health_social_assessments,ientier.health_partner_centers,ientier.health_solidarity_requests TO service_role;

REVOKE EXECUTE ON FUNCTION ientier.health_credit_risk_level(INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.submit_health_credit_application(VARCHAR,NUMERIC,VARCHAR,NUMERIC,NUMERIC,VARCHAR,JSONB,JSONB) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.validate_health_credit_reference(UUID,VARCHAR,BOOLEAN,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.review_health_credit_application(UUID,VARCHAR,BOOLEAN,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.submit_health_credit_payment(UUID,NUMERIC,VARCHAR,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.review_health_credit_payment(UUID,VARCHAR,BOOLEAN,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.refresh_health_credit_overdues(VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.flag_health_credit_default(UUID,VARCHAR,BOOLEAN,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.submit_health_social_assessment(NUMERIC,INTEGER,VARCHAR,VARCHAR,BOOLEAN,BOOLEAN,BOOLEAN,BOOLEAN,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.submit_health_solidarity_request(UUID,NUMERIC,VARCHAR) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION ientier.manage_health_solidarity_request(UUID,VARCHAR,VARCHAR,NUMERIC,NUMERIC,UUID,VARCHAR,VARCHAR,VARCHAR) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION ientier.health_credit_risk_level(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.submit_health_credit_application(VARCHAR,NUMERIC,VARCHAR,NUMERIC,NUMERIC,VARCHAR,JSONB,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.validate_health_credit_reference(UUID,VARCHAR,BOOLEAN,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.review_health_credit_application(UUID,VARCHAR,BOOLEAN,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.submit_health_credit_payment(UUID,NUMERIC,VARCHAR,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.review_health_credit_payment(UUID,VARCHAR,BOOLEAN,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.refresh_health_credit_overdues(VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.flag_health_credit_default(UUID,VARCHAR,BOOLEAN,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.submit_health_social_assessment(NUMERIC,INTEGER,VARCHAR,VARCHAR,BOOLEAN,BOOLEAN,BOOLEAN,BOOLEAN,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.submit_health_solidarity_request(UUID,NUMERIC,VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.manage_health_solidarity_request(UUID,VARCHAR,VARCHAR,NUMERIC,NUMERIC,UUID,VARCHAR,VARCHAR,VARCHAR) TO authenticated;

DO $$ DECLARE table_name TEXT; BEGIN
  FOREACH table_name IN ARRAY ARRAY['health_credit_applications','health_credits','health_credit_installments','health_credit_payments','health_financial_score_events','health_social_assessments','health_solidarity_requests'] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='ientier' AND tablename=table_name) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE ientier.%I',table_name);
    END IF;
  END LOOP;
END $$;

COMMIT;
