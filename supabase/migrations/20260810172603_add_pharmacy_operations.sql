-- =============================================================================
-- i-ENTIER — opérations pharmacie
-- Stock, ventes, achats, commandes Patient et régulation Administration.
-- =============================================================================

BEGIN;

SET search_path TO ientier, public;

CREATE TYPE pharmacy_operational_status AS ENUM (
  'pending',
  'active',
  'suspended',
  'rejected'
);

CREATE TYPE pharmacy_stock_movement_type AS ENUM (
  'opening',
  'purchase',
  'sale',
  'adjustment',
  'return_in',
  'return_out'
);

CREATE TYPE pharmacy_purchase_status AS ENUM (
  'draft',
  'ordered',
  'received',
  'cancelled'
);

CREATE TYPE pharmacy_order_status AS ENUM (
  'pending',
  'accepted',
  'preparing',
  'ready',
  'completed',
  'cancelled'
);

CREATE TYPE pharmacy_customer_request_status AS ENUM (
  'open',
  'in_progress',
  'resolved',
  'closed'
);

CREATE TABLE pharmacies (
  pharmacy_id              VARCHAR(128) PRIMARY KEY
                           REFERENCES provider_profiles(provider_id)
                           ON DELETE CASCADE,
  display_name             VARCHAR(140) NOT NULL,
  legal_name               VARCHAR(180) NOT NULL,
  license_number           VARCHAR(120) NOT NULL,
  license_expires_on       DATE NOT NULL,
  responsible_pharmacist   VARCHAR(140) NOT NULL,
  phone                    VARCHAR(40) NOT NULL,
  email                    CITEXT NOT NULL,
  address                  VARCHAR(300) NOT NULL,
  opening_hours            VARCHAR(500) NOT NULL,
  operational_status       pharmacy_operational_status NOT NULL DEFAULT 'pending',
  public_enabled           BOOLEAN NOT NULL DEFAULT FALSE,
  regulation_note          VARCHAR(600) NOT NULL DEFAULT '',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_license UNIQUE (license_number),
  CONSTRAINT ck_pharmacy_display_name
    CHECK (length(btrim(display_name)) BETWEEN 2 AND 140),
  CONSTRAINT ck_pharmacy_legal_name
    CHECK (length(btrim(legal_name)) BETWEEN 2 AND 180),
  CONSTRAINT ck_pharmacy_license
    CHECK (length(btrim(license_number)) BETWEEN 2 AND 120),
  CONSTRAINT ck_pharmacy_responsible
    CHECK (length(btrim(responsible_pharmacist)) BETWEEN 2 AND 140),
  CONSTRAINT ck_pharmacy_phone
    CHECK (length(btrim(phone)) BETWEEN 5 AND 40),
  CONSTRAINT ck_pharmacy_email
    CHECK (length(btrim(email::TEXT)) BETWEEN 5 AND 180),
  CONSTRAINT ck_pharmacy_address
    CHECK (length(btrim(address)) BETWEEN 4 AND 300),
  CONSTRAINT ck_pharmacy_hours
    CHECK (length(btrim(opening_hours)) BETWEEN 2 AND 500),
  CONSTRAINT ck_pharmacy_public_status
    CHECK (NOT public_enabled OR operational_status = 'active'),
  CONSTRAINT ck_pharmacy_regulation_note
    CHECK (length(regulation_note) <= 600)
);

CREATE TABLE pharmacy_regulatory_reviews (
  review_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE RESTRICT,
  admin_id                 VARCHAR(128) NOT NULL
                           REFERENCES administrators(user_id) ON DELETE RESTRICT,
  old_status               pharmacy_operational_status NOT NULL,
  new_status               pharmacy_operational_status NOT NULL,
  reason                   VARCHAR(600) NOT NULL DEFAULT '',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_pharmacy_review_transition CHECK (old_status <> new_status),
  CONSTRAINT ck_pharmacy_review_reason CHECK (
    length(reason) <= 600
    AND (
      new_status = 'active'
      OR length(btrim(reason)) >= 3
    )
  )
);

CREATE INDEX ix_pharmacy_reviews_lookup
  ON pharmacy_regulatory_reviews (pharmacy_id, created_at DESC);

CREATE TABLE pharmacy_products (
  product_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE CASCADE,
  sku                      VARCHAR(80) NOT NULL,
  barcode                  VARCHAR(80) NOT NULL DEFAULT '',
  name                     VARCHAR(180) NOT NULL,
  active_ingredient        VARCHAR(180) NOT NULL DEFAULT '',
  category                 VARCHAR(120) NOT NULL,
  strength                 VARCHAR(80) NOT NULL DEFAULT '',
  dosage_form              VARCHAR(80) NOT NULL DEFAULT '',
  pack_size                VARCHAR(100) NOT NULL DEFAULT '',
  requires_prescription    BOOLEAN NOT NULL DEFAULT FALSE,
  controlled_substance     BOOLEAN NOT NULL DEFAULT FALSE,
  selling_price            NUMERIC(14,2) NOT NULL DEFAULT 0,
  purchase_price           NUMERIC(14,2) NOT NULL DEFAULT 0,
  currency                 VARCHAR(3) NOT NULL DEFAULT 'HTG',
  stock_quantity           NUMERIC(14,3) NOT NULL DEFAULT 0,
  reorder_level            NUMERIC(14,3) NOT NULL DEFAULT 0,
  is_active                BOOLEAN NOT NULL DEFAULT TRUE,
  is_published             BOOLEAN NOT NULL DEFAULT FALSE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_product_sku UNIQUE (pharmacy_id, sku),
  CONSTRAINT ck_pharmacy_product_sku
    CHECK (length(btrim(sku)) BETWEEN 1 AND 80),
  CONSTRAINT ck_pharmacy_product_name
    CHECK (length(btrim(name)) BETWEEN 2 AND 180),
  CONSTRAINT ck_pharmacy_product_category
    CHECK (length(btrim(category)) BETWEEN 2 AND 120),
  CONSTRAINT ck_pharmacy_product_prices
    CHECK (selling_price >= 0 AND purchase_price >= 0),
  CONSTRAINT ck_pharmacy_product_stock
    CHECK (stock_quantity >= 0 AND reorder_level >= 0),
  CONSTRAINT ck_pharmacy_product_currency
    CHECK (currency = upper(currency) AND length(currency) = 3)
);

CREATE INDEX ix_pharmacy_products_public
  ON pharmacy_products (pharmacy_id, is_published, is_active, name);
CREATE INDEX ix_pharmacy_products_low_stock
  ON pharmacy_products (pharmacy_id, stock_quantity, reorder_level)
  WHERE is_active = TRUE;

CREATE TABLE pharmacy_stock_batches (
  batch_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE CASCADE,
  product_id               UUID NOT NULL
                           REFERENCES pharmacy_products(product_id) ON DELETE CASCADE,
  lot_number               VARCHAR(100) NOT NULL,
  expires_on               DATE,
  quantity_available       NUMERIC(14,3) NOT NULL DEFAULT 0,
  unit_cost                NUMERIC(14,2) NOT NULL DEFAULT 0,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_stock_batch
    UNIQUE (pharmacy_id, product_id, lot_number),
  CONSTRAINT ck_pharmacy_batch_lot
    CHECK (length(btrim(lot_number)) BETWEEN 1 AND 100),
  CONSTRAINT ck_pharmacy_batch_values
    CHECK (quantity_available >= 0 AND unit_cost >= 0)
);

CREATE INDEX ix_pharmacy_batches_expiry
  ON pharmacy_stock_batches (pharmacy_id, expires_on)
  WHERE quantity_available > 0;

CREATE TABLE pharmacy_stock_movements (
  movement_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE RESTRICT,
  product_id               UUID NOT NULL
                           REFERENCES pharmacy_products(product_id) ON DELETE RESTRICT,
  movement_type            pharmacy_stock_movement_type NOT NULL,
  quantity_delta           NUMERIC(14,3) NOT NULL,
  quantity_after           NUMERIC(14,3) NOT NULL,
  reason                   VARCHAR(300) NOT NULL DEFAULT '',
  source_type              VARCHAR(40) NOT NULL DEFAULT '',
  source_id                VARCHAR(160) NOT NULL DEFAULT '',
  actor_id                 VARCHAR(128) NOT NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_pharmacy_movement_delta CHECK (quantity_delta <> 0),
  CONSTRAINT ck_pharmacy_movement_after CHECK (quantity_after >= 0),
  CONSTRAINT ck_pharmacy_movement_reason CHECK (length(reason) <= 300)
);

CREATE INDEX ix_pharmacy_movements_lookup
  ON pharmacy_stock_movements (pharmacy_id, product_id, created_at DESC);

CREATE TABLE pharmacy_suppliers (
  supplier_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE CASCADE,
  name                     VARCHAR(180) NOT NULL,
  contact_name             VARCHAR(140) NOT NULL DEFAULT '',
  phone                    VARCHAR(40) NOT NULL DEFAULT '',
  email                    CITEXT,
  address                  VARCHAR(300) NOT NULL DEFAULT '',
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_supplier UNIQUE (pharmacy_id, name),
  CONSTRAINT ck_pharmacy_supplier_name
    CHECK (length(btrim(name)) BETWEEN 2 AND 180)
);

CREATE TABLE pharmacy_purchase_orders (
  purchase_order_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE RESTRICT,
  supplier_id              UUID REFERENCES pharmacy_suppliers(supplier_id) ON DELETE SET NULL,
  supplier_name_snapshot   VARCHAR(180) NOT NULL,
  reference_number         VARCHAR(40) NOT NULL DEFAULT
                           ('ACH-' || upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 10))),
  status                   pharmacy_purchase_status NOT NULL DEFAULT 'ordered',
  total_amount             NUMERIC(14,2) NOT NULL DEFAULT 0,
  ordered_at               TIMESTAMPTZ,
  received_at              TIMESTAMPTZ,
  created_by               VARCHAR(128) NOT NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_purchase_reference UNIQUE (pharmacy_id, reference_number),
  CONSTRAINT ck_pharmacy_purchase_total CHECK (total_amount >= 0),
  CONSTRAINT ck_pharmacy_purchase_dates CHECK (
    received_at IS NULL OR ordered_at IS NULL OR received_at >= ordered_at
  )
);

CREATE TABLE pharmacy_purchase_items (
  purchase_item_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id        UUID NOT NULL
                           REFERENCES pharmacy_purchase_orders(purchase_order_id)
                           ON DELETE CASCADE,
  product_id               UUID NOT NULL
                           REFERENCES pharmacy_products(product_id) ON DELETE RESTRICT,
  product_name_snapshot    VARCHAR(180) NOT NULL,
  quantity                 NUMERIC(14,3) NOT NULL,
  unit_cost                NUMERIC(14,2) NOT NULL,
  line_total               NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_cost) STORED,

  CONSTRAINT ck_pharmacy_purchase_item_values
    CHECK (quantity > 0 AND unit_cost >= 0)
);

CREATE INDEX ix_pharmacy_purchase_orders
  ON pharmacy_purchase_orders (pharmacy_id, created_at DESC);

CREATE TABLE pharmacy_sales (
  sale_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE RESTRICT,
  order_id                 UUID,
  receipt_number           VARCHAR(40) NOT NULL DEFAULT
                           ('VTE-' || upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 10))),
  customer_name            VARCHAR(140) NOT NULL DEFAULT '',
  payment_method           VARCHAR(40) NOT NULL DEFAULT 'cash',
  subtotal_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
  discount_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_amount             NUMERIC(14,2) NOT NULL DEFAULT 0,
  sold_by                  VARCHAR(128) NOT NULL,
  sold_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_sale_receipt UNIQUE (pharmacy_id, receipt_number),
  CONSTRAINT ck_pharmacy_sale_amounts CHECK (
    subtotal_amount >= 0
    AND discount_amount >= 0
    AND total_amount >= 0
    AND total_amount = subtotal_amount - discount_amount
  ),
  CONSTRAINT ck_pharmacy_sale_payment CHECK (
    payment_method IN ('cash', 'mobile_money', 'card', 'insurance', 'other')
  )
);

CREATE TABLE pharmacy_sale_items (
  sale_item_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id                  UUID NOT NULL
                           REFERENCES pharmacy_sales(sale_id) ON DELETE CASCADE,
  product_id               UUID NOT NULL
                           REFERENCES pharmacy_products(product_id) ON DELETE RESTRICT,
  product_name_snapshot    VARCHAR(180) NOT NULL,
  quantity                 NUMERIC(14,3) NOT NULL,
  unit_price               NUMERIC(14,2) NOT NULL,
  line_total               NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,

  CONSTRAINT ck_pharmacy_sale_item_values
    CHECK (quantity > 0 AND unit_price >= 0)
);

CREATE INDEX ix_pharmacy_sales_lookup
  ON pharmacy_sales (pharmacy_id, sold_at DESC);

CREATE TABLE pharmacy_orders (
  order_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number             VARCHAR(40) NOT NULL DEFAULT
                           ('CMD-' || upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 10))),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE RESTRICT,
  patient_id               VARCHAR(128) NOT NULL
                           REFERENCES patient_profiles(patient_id) ON DELETE RESTRICT,
  prescription_id          VARCHAR(160)
                           REFERENCES prescriptions(prescription_id) ON DELETE SET NULL,
  customer_name            VARCHAR(140) NOT NULL DEFAULT '',
  customer_phone           VARCHAR(40) NOT NULL DEFAULT '',
  status                   pharmacy_order_status NOT NULL DEFAULT 'pending',
  subtotal_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_amount             NUMERIC(14,2) NOT NULL DEFAULT 0,
  note                     VARCHAR(500) NOT NULL DEFAULT '',
  responded_at             TIMESTAMPTZ,
  ready_at                 TIMESTAMPTZ,
  completed_at             TIMESTAMPTZ,
  cancelled_at             TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_pharmacy_order_number UNIQUE (order_number),
  CONSTRAINT ck_pharmacy_order_amounts
    CHECK (subtotal_amount >= 0 AND total_amount >= 0),
  CONSTRAINT ck_pharmacy_order_note CHECK (length(note) <= 500)
);

ALTER TABLE pharmacy_sales
  ADD CONSTRAINT fk_pharmacy_sale_order
  FOREIGN KEY (order_id) REFERENCES pharmacy_orders(order_id) ON DELETE SET NULL;

CREATE TABLE pharmacy_order_items (
  order_item_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                 UUID NOT NULL
                           REFERENCES pharmacy_orders(order_id) ON DELETE CASCADE,
  product_id               UUID NOT NULL
                           REFERENCES pharmacy_products(product_id) ON DELETE RESTRICT,
  product_name_snapshot    VARCHAR(180) NOT NULL,
  quantity                 NUMERIC(14,3) NOT NULL,
  unit_price               NUMERIC(14,2) NOT NULL,
  requires_prescription    BOOLEAN NOT NULL DEFAULT FALSE,
  line_total               NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,

  CONSTRAINT ck_pharmacy_order_item_values
    CHECK (quantity > 0 AND unit_price >= 0)
);

CREATE INDEX ix_pharmacy_orders_pharmacy
  ON pharmacy_orders (pharmacy_id, status, created_at DESC);
CREATE INDEX ix_pharmacy_orders_patient
  ON pharmacy_orders (patient_id, created_at DESC);

CREATE TABLE pharmacy_customer_requests (
  request_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id              VARCHAR(128) NOT NULL
                           REFERENCES pharmacies(pharmacy_id) ON DELETE RESTRICT,
  patient_id               VARCHAR(128)
                           REFERENCES patient_profiles(patient_id) ON DELETE SET NULL,
  order_id                 UUID REFERENCES pharmacy_orders(order_id) ON DELETE SET NULL,
  patient_name_snapshot    VARCHAR(140) NOT NULL DEFAULT '',
  subject                  VARCHAR(160) NOT NULL,
  message                  VARCHAR(1500) NOT NULL,
  status                   pharmacy_customer_request_status NOT NULL DEFAULT 'open',
  resolution_note          VARCHAR(1000) NOT NULL DEFAULT '',
  resolved_at              TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_pharmacy_request_subject
    CHECK (length(btrim(subject)) BETWEEN 2 AND 160),
  CONSTRAINT ck_pharmacy_request_message
    CHECK (length(btrim(message)) BETWEEN 2 AND 1500),
  CONSTRAINT ck_pharmacy_request_resolution
    CHECK (length(resolution_note) <= 1000)
);

CREATE INDEX ix_pharmacy_requests_lookup
  ON pharmacy_customer_requests (pharmacy_id, status, created_at DESC);

-- Horodatage, champs régulés et journaux immuables.
CREATE TRIGGER trg_pharmacies_updated_at
BEFORE UPDATE ON pharmacies
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_products_updated_at
BEFORE UPDATE ON pharmacy_products
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_batches_updated_at
BEFORE UPDATE ON pharmacy_stock_batches
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_suppliers_updated_at
BEFORE UPDATE ON pharmacy_suppliers
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_purchases_updated_at
BEFORE UPDATE ON pharmacy_purchase_orders
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_orders_updated_at
BEFORE UPDATE ON pharmacy_orders
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_requests_updated_at
BEFORE UPDATE ON pharmacy_customer_requests
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacy_reviews_immutable
BEFORE UPDATE OR DELETE ON pharmacy_regulatory_reviews
FOR EACH ROW EXECUTE FUNCTION prevent_row_change();

CREATE TRIGGER trg_pharmacy_movements_immutable
BEFORE UPDATE OR DELETE ON pharmacy_stock_movements
FOR EACH ROW EXECUTE FUNCTION prevent_row_change();

CREATE OR REPLACE FUNCTION protect_pharmacy_regulation_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NOT current_actor_is_admin() AND (
    NEW.operational_status IS DISTINCT FROM OLD.operational_status
    OR NEW.public_enabled IS DISTINCT FROM OLD.public_enabled
    OR NEW.regulation_note IS DISTINCT FROM OLD.regulation_note
    OR NEW.license_number IS DISTINCT FROM OLD.license_number
    OR NEW.license_expires_on IS DISTINCT FROM OLD.license_expires_on
  ) THEN
    RAISE EXCEPTION 'Ces champs sont réservés à la régulation administrative.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_pharmacy_regulation_fields
BEFORE UPDATE ON pharmacies
FOR EACH ROW EXECUTE FUNCTION protect_pharmacy_regulation_fields();

CREATE OR REPLACE FUNCTION protect_pharmacy_stock_quantity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.stock_quantity IS DISTINCT FROM OLD.stock_quantity
     AND COALESCE(current_setting('ientier.pharmacy_stock_context', TRUE), '') <> 'allowed' THEN
    RAISE EXCEPTION 'Le stock doit être modifié par une opération atomique.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_pharmacy_stock_quantity
BEFORE UPDATE ON pharmacy_products
FOR EACH ROW EXECUTE FUNCTION protect_pharmacy_stock_quantity();

CREATE OR REPLACE FUNCTION log_initial_pharmacy_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
BEGIN
  IF NEW.stock_quantity > 0 THEN
    INSERT INTO pharmacy_stock_movements (
      pharmacy_id,
      product_id,
      movement_type,
      quantity_delta,
      quantity_after,
      reason,
      source_type,
      source_id,
      actor_id
    )
    VALUES (
      NEW.pharmacy_id,
      NEW.product_id,
      'opening',
      NEW.stock_quantity,
      NEW.stock_quantity,
      'Stock initial',
      'product',
      NEW.product_id::TEXT,
      COALESCE(current_actor_id(), 'system')
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_initial_pharmacy_stock
AFTER INSERT ON pharmacy_products
FOR EACH ROW EXECUTE FUNCTION log_initial_pharmacy_stock();

CREATE OR REPLACE FUNCTION register_pharmacy(
  p_owner_id VARCHAR,
  p_display_name VARCHAR,
  p_legal_name VARCHAR,
  p_license_number VARCHAR,
  p_license_expires_on DATE,
  p_responsible_pharmacist VARCHAR,
  p_phone VARCHAR,
  p_email VARCHAR,
  p_address VARCHAR,
  p_opening_hours VARCHAR,
  p_description VARCHAR
)
RETURNS VARCHAR(128)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  existing_profile provider_profiles%ROWTYPE;
BEGIN
  IF actor_id IS NULL OR actor_id <> p_owner_id THEN
    RAISE EXCEPTION 'Le propriétaire déclaré ne correspond pas à la session.';
  END IF;
  IF p_license_expires_on IS NULL OR p_license_expires_on <= CURRENT_DATE THEN
    RAISE EXCEPTION 'La licence doit être valide après la date du jour.';
  END IF;
  IF EXISTS (SELECT 1 FROM pharmacies WHERE pharmacy_id = actor_id) THEN
    RAISE EXCEPTION 'Une pharmacie est déjà liée à ce compte.';
  END IF;

  SELECT * INTO existing_profile
  FROM provider_profiles
  WHERE provider_id = actor_id;

  IF FOUND THEN
    IF existing_profile.account_type <> 'institution'
       OR lower(existing_profile.category) NOT LIKE '%pharm%' THEN
      RAISE EXCEPTION 'Ce compte possède déjà un autre profil professionnel.';
    END IF;
  ELSE
    INSERT INTO provider_profiles (
      provider_id,
      account_type,
      display_name,
      category,
      registration_number,
      contact_person,
      workplace,
      phone,
      email,
      address,
      description,
      qualifications,
      services_summary,
      schedule_summary,
      available,
      is_visible,
      verification_status,
      rejection_reason,
      terms_accepted
    )
    VALUES (
      actor_id,
      'institution',
      btrim(p_display_name),
      'Pharmacie',
      btrim(p_license_number),
      btrim(p_responsible_pharmacist),
      btrim(p_legal_name),
      btrim(p_phone),
      btrim(p_email)::public.CITEXT,
      btrim(p_address),
      btrim(p_description),
      'Pharmacien responsable : ' || btrim(p_responsible_pharmacist),
      'Dispensation, conseil pharmaceutique, commandes et service clientèle',
      btrim(p_opening_hours),
      TRUE,
      FALSE,
      'pending',
      '',
      TRUE
    );
  END IF;

  INSERT INTO pharmacies (
    pharmacy_id,
    display_name,
    legal_name,
    license_number,
    license_expires_on,
    responsible_pharmacist,
    phone,
    email,
    address,
    opening_hours
  )
  VALUES (
    actor_id,
    btrim(p_display_name),
    btrim(p_legal_name),
    btrim(p_license_number),
    p_license_expires_on,
    btrim(p_responsible_pharmacist),
    btrim(p_phone),
    btrim(p_email)::public.CITEXT,
    btrim(p_address),
    btrim(p_opening_hours)
  );

  RETURN actor_id;
END;
$$;

CREATE OR REPLACE FUNCTION review_pharmacy(
  p_pharmacy_id VARCHAR,
  p_admin_id VARCHAR,
  p_new_status pharmacy_operational_status,
  p_reason VARCHAR DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  old_status pharmacy_operational_status;
  normalized_reason VARCHAR(600) := btrim(COALESCE(p_reason, ''));
  new_review_id UUID;
BEGIN
  IF actor_id IS NULL OR actor_id <> p_admin_id OR NOT current_actor_is_admin() THEN
    RAISE EXCEPTION 'Accès administrateur actif requis.';
  END IF;
  IF p_new_status = 'pending' THEN
    RAISE EXCEPTION 'Une décision finale ou une suspension est requise.';
  END IF;
  IF p_new_status IN ('suspended', 'rejected') AND length(normalized_reason) < 3 THEN
    RAISE EXCEPTION 'Un motif précis est requis.';
  END IF;

  SELECT operational_status INTO old_status
  FROM pharmacies
  WHERE pharmacy_id = p_pharmacy_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cette pharmacie n’existe pas.';
  END IF;
  IF old_status = p_new_status THEN
    RAISE EXCEPTION 'Ce statut est déjà appliqué.';
  END IF;
  IF old_status = 'pending' AND p_new_status = 'suspended' THEN
    RAISE EXCEPTION 'Une pharmacie en attente ne peut pas être suspendue.';
  END IF;

  UPDATE pharmacies
  SET operational_status = p_new_status,
      public_enabled = p_new_status = 'active',
      regulation_note = CASE
        WHEN p_new_status = 'active' THEN ''
        ELSE normalized_reason
      END
  WHERE pharmacy_id = p_pharmacy_id;

  UPDATE provider_profiles
  SET verification_status = CASE
        WHEN p_new_status = 'rejected' THEN 'rejected'::verification_status
        ELSE 'approved'::verification_status
      END,
      rejection_reason = CASE
        WHEN p_new_status = 'rejected' THEN normalized_reason
        ELSE ''
      END,
      is_visible = p_new_status = 'active',
      available = p_new_status = 'active'
  WHERE provider_id = p_pharmacy_id;

  INSERT INTO pharmacy_regulatory_reviews (
    pharmacy_id,
    admin_id,
    old_status,
    new_status,
    reason
  )
  VALUES (
    p_pharmacy_id,
    p_admin_id,
    old_status,
    p_new_status,
    normalized_reason
  )
  RETURNING review_id INTO new_review_id;

  RETURN new_review_id;
END;
$$;

CREATE OR REPLACE FUNCTION adjust_pharmacy_stock(
  p_pharmacy_id VARCHAR,
  p_product_id UUID,
  p_quantity_delta NUMERIC,
  p_reason VARCHAR
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  current_quantity NUMERIC(14,3);
  new_quantity NUMERIC(14,3);
BEGIN
  IF actor_id IS NULL OR (
    actor_id <> p_pharmacy_id AND NOT current_actor_is_admin()
  ) THEN
    RAISE EXCEPTION 'Cette pharmacie n’appartient pas à la session.';
  END IF;
  IF p_quantity_delta IS NULL OR p_quantity_delta = 0 THEN
    RAISE EXCEPTION 'La variation doit être non nulle.';
  END IF;
  IF length(btrim(COALESCE(p_reason, ''))) < 3 THEN
    RAISE EXCEPTION 'Un motif précis est requis.';
  END IF;

  SELECT stock_quantity INTO current_quantity
  FROM pharmacy_products
  WHERE product_id = p_product_id
    AND pharmacy_id = p_pharmacy_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Produit introuvable.';
  END IF;

  new_quantity := current_quantity + p_quantity_delta;
  IF new_quantity < 0 THEN
    RAISE EXCEPTION 'Le stock ne peut pas devenir négatif.';
  END IF;

  PERFORM set_config('ientier.pharmacy_stock_context', 'allowed', TRUE);
  UPDATE pharmacy_products
  SET stock_quantity = new_quantity
  WHERE product_id = p_product_id;

  INSERT INTO pharmacy_stock_movements (
    pharmacy_id,
    product_id,
    movement_type,
    quantity_delta,
    quantity_after,
    reason,
    source_type,
    source_id,
    actor_id
  )
  VALUES (
    p_pharmacy_id,
    p_product_id,
    'adjustment',
    p_quantity_delta,
    new_quantity,
    btrim(p_reason),
    'manual_adjustment',
    '',
    actor_id
  );

  RETURN new_quantity;
END;
$$;

CREATE OR REPLACE FUNCTION record_pharmacy_sale(
  p_pharmacy_id VARCHAR,
  p_items JSONB,
  p_customer_name VARCHAR DEFAULT '',
  p_payment_method VARCHAR DEFAULT 'cash'
)
RETURNS VARCHAR(40)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  new_sale_id UUID;
  new_receipt VARCHAR(40);
  item JSONB;
  target_product pharmacy_products%ROWTYPE;
  requested_quantity NUMERIC(14,3);
  new_quantity NUMERIC(14,3);
  subtotal NUMERIC(14,2) := 0;
  item_count INTEGER := 0;
BEGIN
  IF actor_id IS NULL OR actor_id <> p_pharmacy_id THEN
    RAISE EXCEPTION 'Cette pharmacie n’appartient pas à la session.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pharmacies
    WHERE pharmacy_id = p_pharmacy_id
      AND operational_status = 'active'
  ) THEN
    RAISE EXCEPTION 'La pharmacie doit être active pour enregistrer une vente.';
  END IF;
  IF p_payment_method NOT IN ('cash', 'mobile_money', 'card', 'insurance', 'other') THEN
    RAISE EXCEPTION 'Mode de paiement invalide.';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La vente doit contenir au moins un produit.';
  END IF;

  INSERT INTO pharmacy_sales (
    pharmacy_id,
    customer_name,
    payment_method,
    sold_by
  )
  VALUES (
    p_pharmacy_id,
    btrim(COALESCE(p_customer_name, '')),
    p_payment_method,
    actor_id
  )
  RETURNING sale_id, receipt_number INTO new_sale_id, new_receipt;

  PERFORM set_config('ientier.pharmacy_stock_context', 'allowed', TRUE);

  FOR item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    requested_quantity := NULLIF(item ->> 'quantity', '')::NUMERIC;
    IF requested_quantity IS NULL OR requested_quantity <= 0 THEN
      RAISE EXCEPTION 'Chaque quantité vendue doit être positive.';
    END IF;

    SELECT * INTO target_product
    FROM pharmacy_products
    WHERE product_id = (item ->> 'product_id')::UUID
      AND pharmacy_id = p_pharmacy_id
      AND is_active = TRUE
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Un produit de la vente est introuvable ou inactif.';
    END IF;
    IF target_product.stock_quantity < requested_quantity THEN
      RAISE EXCEPTION 'Stock insuffisant pour %.', target_product.name;
    END IF;

    new_quantity := target_product.stock_quantity - requested_quantity;
    UPDATE pharmacy_products
    SET stock_quantity = new_quantity
    WHERE product_id = target_product.product_id;

    INSERT INTO pharmacy_sale_items (
      sale_id,
      product_id,
      product_name_snapshot,
      quantity,
      unit_price
    )
    VALUES (
      new_sale_id,
      target_product.product_id,
      target_product.name,
      requested_quantity,
      target_product.selling_price
    );

    INSERT INTO pharmacy_stock_movements (
      pharmacy_id,
      product_id,
      movement_type,
      quantity_delta,
      quantity_after,
      reason,
      source_type,
      source_id,
      actor_id
    )
    VALUES (
      p_pharmacy_id,
      target_product.product_id,
      'sale',
      -requested_quantity,
      new_quantity,
      'Vente ' || new_receipt,
      'sale',
      new_sale_id::TEXT,
      actor_id
    );

    subtotal := subtotal + (requested_quantity * target_product.selling_price);
    item_count := item_count + 1;
  END LOOP;

  IF item_count = 0 THEN
    RAISE EXCEPTION 'La vente doit contenir au moins un produit.';
  END IF;

  UPDATE pharmacy_sales
  SET subtotal_amount = subtotal,
      total_amount = subtotal
  WHERE sale_id = new_sale_id;

  RETURN new_receipt;
END;
$$;

CREATE OR REPLACE FUNCTION create_pharmacy_purchase(
  p_pharmacy_id VARCHAR,
  p_supplier_name VARCHAR,
  p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  new_purchase_id UUID;
  item JSONB;
  target_product pharmacy_products%ROWTYPE;
  requested_quantity NUMERIC(14,3);
  requested_cost NUMERIC(14,2);
  total NUMERIC(14,2) := 0;
  item_count INTEGER := 0;
BEGIN
  IF actor_id IS NULL OR actor_id <> p_pharmacy_id THEN
    RAISE EXCEPTION 'Cette pharmacie n’appartient pas à la session.';
  END IF;
  IF length(btrim(COALESCE(p_supplier_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Le fournisseur est requis.';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Le bon d’achat doit contenir au moins un produit.';
  END IF;

  INSERT INTO pharmacy_purchase_orders (
    pharmacy_id,
    supplier_name_snapshot,
    status,
    ordered_at,
    created_by
  )
  VALUES (
    p_pharmacy_id,
    btrim(p_supplier_name),
    'ordered',
    CURRENT_TIMESTAMP,
    actor_id
  )
  RETURNING purchase_order_id INTO new_purchase_id;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    requested_quantity := NULLIF(item ->> 'quantity', '')::NUMERIC;
    requested_cost := NULLIF(item ->> 'unit_cost', '')::NUMERIC;
    IF requested_quantity IS NULL OR requested_quantity <= 0
       OR requested_cost IS NULL OR requested_cost < 0 THEN
      RAISE EXCEPTION 'Quantité ou coût d’achat invalide.';
    END IF;

    SELECT * INTO target_product
    FROM pharmacy_products
    WHERE product_id = (item ->> 'product_id')::UUID
      AND pharmacy_id = p_pharmacy_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Un produit du bon d’achat est introuvable.';
    END IF;

    INSERT INTO pharmacy_purchase_items (
      purchase_order_id,
      product_id,
      product_name_snapshot,
      quantity,
      unit_cost
    )
    VALUES (
      new_purchase_id,
      target_product.product_id,
      target_product.name,
      requested_quantity,
      requested_cost
    );

    total := total + (requested_quantity * requested_cost);
    item_count := item_count + 1;
  END LOOP;

  IF item_count = 0 THEN
    RAISE EXCEPTION 'Le bon d’achat doit contenir au moins un produit.';
  END IF;

  UPDATE pharmacy_purchase_orders
  SET total_amount = total
  WHERE purchase_order_id = new_purchase_id;

  RETURN new_purchase_id;
END;
$$;

CREATE OR REPLACE FUNCTION receive_pharmacy_purchase(
  p_purchase_order_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  target_purchase pharmacy_purchase_orders%ROWTYPE;
  target_item pharmacy_purchase_items%ROWTYPE;
  current_quantity NUMERIC(14,3);
  new_quantity NUMERIC(14,3);
BEGIN
  SELECT * INTO target_purchase
  FROM pharmacy_purchase_orders
  WHERE purchase_order_id = p_purchase_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bon d’achat introuvable.';
  END IF;
  IF actor_id IS NULL OR actor_id <> target_purchase.pharmacy_id THEN
    RAISE EXCEPTION 'Ce bon d’achat appartient à une autre pharmacie.';
  END IF;
  IF target_purchase.status <> 'ordered' THEN
    RAISE EXCEPTION 'Seul un achat commandé peut être réceptionné.';
  END IF;

  PERFORM set_config('ientier.pharmacy_stock_context', 'allowed', TRUE);

  FOR target_item IN
    SELECT * FROM pharmacy_purchase_items
    WHERE purchase_order_id = p_purchase_order_id
    ORDER BY purchase_item_id
  LOOP
    SELECT stock_quantity INTO current_quantity
    FROM pharmacy_products
    WHERE product_id = target_item.product_id
      AND pharmacy_id = target_purchase.pharmacy_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Un produit du bon n’existe plus.';
    END IF;

    new_quantity := current_quantity + target_item.quantity;
    UPDATE pharmacy_products
    SET stock_quantity = new_quantity,
        purchase_price = target_item.unit_cost
    WHERE product_id = target_item.product_id;

    INSERT INTO pharmacy_stock_movements (
      pharmacy_id,
      product_id,
      movement_type,
      quantity_delta,
      quantity_after,
      reason,
      source_type,
      source_id,
      actor_id
    )
    VALUES (
      target_purchase.pharmacy_id,
      target_item.product_id,
      'purchase',
      target_item.quantity,
      new_quantity,
      'Réception ' || target_purchase.reference_number,
      'purchase',
      target_purchase.purchase_order_id::TEXT,
      actor_id
    );
  END LOOP;

  UPDATE pharmacy_purchase_orders
  SET status = 'received',
      received_at = CURRENT_TIMESTAMP
  WHERE purchase_order_id = p_purchase_order_id;

  RETURN p_purchase_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION place_pharmacy_order(
  p_pharmacy_id VARCHAR,
  p_items JSONB,
  p_prescription_id VARCHAR DEFAULT NULL,
  p_customer_name VARCHAR DEFAULT '',
  p_customer_phone VARCHAR DEFAULT '',
  p_note VARCHAR DEFAULT ''
)
RETURNS VARCHAR(40)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  new_order_id UUID;
  new_order_number VARCHAR(40);
  item JSONB;
  target_product pharmacy_products%ROWTYPE;
  requested_quantity NUMERIC(14,3);
  total NUMERIC(14,2) := 0;
  prescription_required BOOLEAN := FALSE;
  item_count INTEGER := 0;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM patient_profiles WHERE patient_id = actor_id
  ) THEN
    RAISE EXCEPTION 'Un dossier patient connecté est requis.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pharmacies
    WHERE pharmacy_id = p_pharmacy_id
      AND operational_status = 'active'
      AND public_enabled = TRUE
  ) THEN
    RAISE EXCEPTION 'Cette pharmacie n’accepte pas de commandes.';
  END IF;
  IF p_prescription_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM prescriptions
    WHERE prescription_id = p_prescription_id
      AND patient_id = actor_id
      AND status = 'available'
  ) THEN
    RAISE EXCEPTION 'Cette ordonnance n’appartient pas au patient connecté.';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La commande doit contenir au moins un produit.';
  END IF;

  INSERT INTO pharmacy_orders (
    pharmacy_id,
    patient_id,
    prescription_id,
    customer_name,
    customer_phone,
    note
  )
  VALUES (
    p_pharmacy_id,
    actor_id,
    p_prescription_id,
    btrim(COALESCE(p_customer_name, '')),
    btrim(COALESCE(p_customer_phone, '')),
    btrim(COALESCE(p_note, ''))
  )
  RETURNING order_id, order_number INTO new_order_id, new_order_number;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    requested_quantity := NULLIF(item ->> 'quantity', '')::NUMERIC;
    IF requested_quantity IS NULL OR requested_quantity <= 0 THEN
      RAISE EXCEPTION 'Chaque quantité commandée doit être positive.';
    END IF;

    SELECT * INTO target_product
    FROM pharmacy_products
    WHERE product_id = (item ->> 'product_id')::UUID
      AND pharmacy_id = p_pharmacy_id
      AND is_active = TRUE
      AND is_published = TRUE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Un produit n’est plus disponible à la commande.';
    END IF;
    IF target_product.stock_quantity < requested_quantity THEN
      RAISE EXCEPTION 'Quantité indisponible pour %.', target_product.name;
    END IF;

    prescription_required :=
      prescription_required OR target_product.requires_prescription;

    INSERT INTO pharmacy_order_items (
      order_id,
      product_id,
      product_name_snapshot,
      quantity,
      unit_price,
      requires_prescription
    )
    VALUES (
      new_order_id,
      target_product.product_id,
      target_product.name,
      requested_quantity,
      target_product.selling_price,
      target_product.requires_prescription
    );

    total := total + (requested_quantity * target_product.selling_price);
    item_count := item_count + 1;
  END LOOP;

  IF item_count = 0 THEN
    RAISE EXCEPTION 'La commande doit contenir au moins un produit.';
  END IF;
  IF prescription_required AND p_prescription_id IS NULL THEN
    RAISE EXCEPTION 'Une ordonnance est requise pour cette commande.';
  END IF;

  UPDATE pharmacy_orders
  SET subtotal_amount = total,
      total_amount = total
  WHERE order_id = new_order_id;

  RETURN new_order_number;
END;
$$;

CREATE OR REPLACE FUNCTION update_pharmacy_order_status(
  p_order_id UUID,
  p_new_status pharmacy_order_status
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  target_order pharmacy_orders%ROWTYPE;
BEGIN
  SELECT * INTO target_order
  FROM pharmacy_orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commande introuvable.';
  END IF;
  IF actor_id IS NULL OR (
    actor_id <> target_order.pharmacy_id AND NOT current_actor_is_admin()
  ) THEN
    RAISE EXCEPTION 'Cette commande appartient à une autre pharmacie.';
  END IF;
  IF NOT (
    (target_order.status = 'pending' AND p_new_status IN ('accepted', 'cancelled'))
    OR (target_order.status = 'accepted' AND p_new_status IN ('preparing', 'cancelled'))
    OR (target_order.status = 'preparing' AND p_new_status IN ('ready', 'cancelled'))
    OR (target_order.status = 'ready' AND p_new_status = 'completed')
  ) THEN
    RAISE EXCEPTION 'Transition de commande invalide.';
  END IF;

  UPDATE pharmacy_orders
  SET status = p_new_status,
      responded_at = CASE
        WHEN p_new_status = 'accepted' THEN CURRENT_TIMESTAMP
        ELSE responded_at
      END,
      ready_at = CASE
        WHEN p_new_status = 'ready' THEN CURRENT_TIMESTAMP
        ELSE ready_at
      END,
      completed_at = CASE
        WHEN p_new_status = 'completed' THEN CURRENT_TIMESTAMP
        ELSE completed_at
      END,
      cancelled_at = CASE
        WHEN p_new_status = 'cancelled' THEN CURRENT_TIMESTAMP
        ELSE cancelled_at
      END
  WHERE order_id = p_order_id;

  RETURN p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION create_pharmacy_customer_request(
  p_pharmacy_id VARCHAR,
  p_subject VARCHAR,
  p_message VARCHAR,
  p_order_id UUID DEFAULT NULL,
  p_patient_name VARCHAR DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  new_request_id UUID;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM patient_profiles WHERE patient_id = actor_id
  ) THEN
    RAISE EXCEPTION 'Un dossier patient connecté est requis.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pharmacies
    WHERE pharmacy_id = p_pharmacy_id
      AND operational_status = 'active'
      AND public_enabled = TRUE
  ) THEN
    RAISE EXCEPTION 'Cette pharmacie n’est pas disponible.';
  END IF;
  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pharmacy_orders
    WHERE order_id = p_order_id
      AND patient_id = actor_id
      AND pharmacy_id = p_pharmacy_id
  ) THEN
    RAISE EXCEPTION 'Cette commande n’appartient pas au patient connecté.';
  END IF;

  INSERT INTO pharmacy_customer_requests (
    pharmacy_id,
    patient_id,
    order_id,
    patient_name_snapshot,
    subject,
    message
  )
  VALUES (
    p_pharmacy_id,
    actor_id,
    p_order_id,
    btrim(COALESCE(p_patient_name, '')),
    btrim(p_subject),
    btrim(p_message)
  )
  RETURNING request_id INTO new_request_id;

  RETURN new_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION update_pharmacy_request_status(
  p_request_id UUID,
  p_new_status pharmacy_customer_request_status
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, pg_temp
AS $$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  target_request pharmacy_customer_requests%ROWTYPE;
BEGIN
  SELECT * INTO target_request
  FROM pharmacy_customer_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Demande client introuvable.';
  END IF;
  IF actor_id IS NULL OR (
    actor_id <> target_request.pharmacy_id AND NOT current_actor_is_admin()
  ) THEN
    RAISE EXCEPTION 'Cette demande appartient à une autre pharmacie.';
  END IF;

  UPDATE pharmacy_customer_requests
  SET status = p_new_status,
      resolved_at = CASE
        WHEN p_new_status IN ('resolved', 'closed') THEN CURRENT_TIMESTAMP
        ELSE NULL
      END
  WHERE request_id = p_request_id;

  RETURN p_request_id;
END;
$$;

-- Vues partagées : catalogue Patient et régulation Administration.
CREATE VIEW v_public_pharmacy_products
WITH (security_barrier = TRUE, security_invoker = TRUE)
AS
SELECT
  p.product_id,
  p.pharmacy_id,
  ph.display_name AS pharmacy_name,
  ph.address AS pharmacy_address,
  ph.phone AS pharmacy_phone,
  ph.opening_hours,
  p.sku,
  p.barcode,
  p.name,
  p.active_ingredient,
  p.category,
  p.strength,
  p.dosage_form,
  p.pack_size,
  p.requires_prescription,
  p.selling_price,
  p.currency,
  p.stock_quantity,
  p.updated_at
FROM pharmacy_products p
JOIN pharmacies ph ON ph.pharmacy_id = p.pharmacy_id
WHERE ph.operational_status = 'active'
  AND ph.public_enabled = TRUE
  AND p.is_active = TRUE
  AND p.is_published = TRUE
  AND p.stock_quantity > 0;

COMMENT ON VIEW v_public_pharmacy_products IS
  'Catalogue de médicaments publié par les pharmacies actives pour l’application Patient.';

CREATE VIEW v_pharmacy_admin_overview
WITH (security_barrier = TRUE, security_invoker = TRUE)
AS
SELECT
  ph.pharmacy_id,
  ph.display_name,
  ph.legal_name,
  ph.license_number,
  ph.license_expires_on,
  ph.responsible_pharmacist,
  ph.phone,
  ph.email,
  ph.address,
  ph.opening_hours,
  ph.operational_status,
  ph.public_enabled,
  ph.regulation_note,
  ph.created_at,
  ph.updated_at,
  (ph.license_expires_on < CURRENT_DATE) AS license_expired,
  (
    SELECT count(*)
    FROM pharmacy_products pp
    WHERE pp.pharmacy_id = ph.pharmacy_id
      AND pp.is_active = TRUE
  ) AS product_count,
  (
    SELECT count(*)
    FROM pharmacy_products pp
    WHERE pp.pharmacy_id = ph.pharmacy_id
      AND pp.is_active = TRUE
      AND pp.stock_quantity <= pp.reorder_level
  ) AS low_stock_count,
  (
    SELECT count(*)
    FROM pharmacy_orders po
    WHERE po.pharmacy_id = ph.pharmacy_id
      AND po.status IN ('pending', 'accepted', 'preparing', 'ready')
  ) AS open_order_count,
  (
    SELECT COALESCE(sum(ps.total_amount), 0)
    FROM pharmacy_sales ps
    WHERE ps.pharmacy_id = ph.pharmacy_id
      AND ps.sold_at >= date_trunc('month', CURRENT_TIMESTAMP)
  ) AS month_sales_total
FROM pharmacies ph;

COMMENT ON VIEW v_pharmacy_admin_overview IS
  'Indicateurs de conformité et d’activité réservés aux administrateurs i-ENTIER.';

-- Sécurité ligne par ligne.
ALTER TABLE pharmacies ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_regulatory_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_stock_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_purchase_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_customer_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY pharmacies_select
ON pharmacies FOR SELECT
TO authenticated
USING (
  pharmacy_id = current_actor_id()
  OR current_actor_is_admin()
  OR (operational_status = 'active' AND public_enabled = TRUE)
);

CREATE POLICY pharmacy_reviews_select
ON pharmacy_regulatory_reviews FOR SELECT
TO authenticated
USING (
  current_actor_is_admin()
  OR pharmacy_id = current_actor_id()
);

CREATE POLICY pharmacy_products_select
ON pharmacy_products FOR SELECT
TO authenticated
USING (
  pharmacy_id = current_actor_id()
  OR current_actor_is_admin()
  OR (
    is_active = TRUE
    AND is_published = TRUE
    AND EXISTS (
      SELECT 1
      FROM pharmacies ph
      WHERE ph.pharmacy_id = pharmacy_products.pharmacy_id
        AND ph.operational_status = 'active'
        AND ph.public_enabled = TRUE
    )
  )
);

CREATE POLICY pharmacy_products_insert
ON pharmacy_products FOR INSERT
TO authenticated
WITH CHECK (
  pharmacy_id = current_actor_id()
  AND EXISTS (
    SELECT 1 FROM pharmacies ph
    WHERE ph.pharmacy_id = pharmacy_products.pharmacy_id
      AND ph.operational_status = 'active'
  )
);

CREATE POLICY pharmacy_products_update
ON pharmacy_products FOR UPDATE
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
)
WITH CHECK (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_products_delete
ON pharmacy_products FOR DELETE
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_batches_owner
ON pharmacy_stock_batches FOR ALL
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
)
WITH CHECK (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_movements_select
ON pharmacy_stock_movements FOR SELECT
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_suppliers_owner
ON pharmacy_suppliers FOR ALL
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
)
WITH CHECK (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_purchases_select
ON pharmacy_purchase_orders FOR SELECT
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_purchase_items_select
ON pharmacy_purchase_items FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM pharmacy_purchase_orders po
    WHERE po.purchase_order_id = pharmacy_purchase_items.purchase_order_id
      AND (
        po.pharmacy_id = current_actor_id()
        OR current_actor_is_admin()
      )
  )
);

CREATE POLICY pharmacy_sales_select
ON pharmacy_sales FOR SELECT
TO authenticated
USING (
  pharmacy_id = current_actor_id() OR current_actor_is_admin()
);

CREATE POLICY pharmacy_sale_items_select
ON pharmacy_sale_items FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM pharmacy_sales s
    WHERE s.sale_id = pharmacy_sale_items.sale_id
      AND (
        s.pharmacy_id = current_actor_id()
        OR current_actor_is_admin()
      )
  )
);

CREATE POLICY pharmacy_orders_select
ON pharmacy_orders FOR SELECT
TO authenticated
USING (
  patient_id = current_actor_id()
  OR pharmacy_id = current_actor_id()
  OR current_actor_is_admin()
);

CREATE POLICY pharmacy_order_items_select
ON pharmacy_order_items FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM pharmacy_orders o
    WHERE o.order_id = pharmacy_order_items.order_id
      AND (
        o.patient_id = current_actor_id()
        OR o.pharmacy_id = current_actor_id()
        OR current_actor_is_admin()
      )
  )
);

CREATE POLICY pharmacy_requests_select
ON pharmacy_customer_requests FOR SELECT
TO authenticated
USING (
  patient_id = current_actor_id()
  OR pharmacy_id = current_actor_id()
  OR current_actor_is_admin()
);

-- Privilèges Data API explicites (requis par les nouveaux réglages Supabase).
GRANT USAGE ON TYPE
  pharmacy_operational_status,
  pharmacy_stock_movement_type,
  pharmacy_purchase_status,
  pharmacy_order_status,
  pharmacy_customer_request_status
TO authenticated, service_role;

GRANT SELECT ON
  pharmacies,
  pharmacy_regulatory_reviews,
  pharmacy_stock_movements,
  pharmacy_purchase_orders,
  pharmacy_purchase_items,
  pharmacy_sales,
  pharmacy_sale_items,
  pharmacy_orders,
  pharmacy_order_items,
  pharmacy_customer_requests,
  v_public_pharmacy_products,
  v_pharmacy_admin_overview
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  pharmacy_products,
  pharmacy_stock_batches,
  pharmacy_suppliers
TO authenticated;

GRANT ALL ON
  pharmacies,
  pharmacy_regulatory_reviews,
  pharmacy_products,
  pharmacy_stock_batches,
  pharmacy_stock_movements,
  pharmacy_suppliers,
  pharmacy_purchase_orders,
  pharmacy_purchase_items,
  pharmacy_sales,
  pharmacy_sale_items,
  pharmacy_orders,
  pharmacy_order_items,
  pharmacy_customer_requests
TO service_role;

REVOKE EXECUTE ON FUNCTION register_pharmacy(
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR,
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION review_pharmacy(
  VARCHAR, VARCHAR, pharmacy_operational_status, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION adjust_pharmacy_stock(
  VARCHAR, UUID, NUMERIC, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION record_pharmacy_sale(
  VARCHAR, JSONB, VARCHAR, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION create_pharmacy_purchase(
  VARCHAR, VARCHAR, JSONB
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION receive_pharmacy_purchase(UUID)
  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION place_pharmacy_order(
  VARCHAR, JSONB, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION update_pharmacy_order_status(
  UUID, pharmacy_order_status
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION create_pharmacy_customer_request(
  VARCHAR, VARCHAR, VARCHAR, UUID, VARCHAR
) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION update_pharmacy_request_status(
  UUID, pharmacy_customer_request_status
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION register_pharmacy(
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR,
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION review_pharmacy(
  VARCHAR, VARCHAR, pharmacy_operational_status, VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION adjust_pharmacy_stock(
  VARCHAR, UUID, NUMERIC, VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION record_pharmacy_sale(
  VARCHAR, JSONB, VARCHAR, VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION create_pharmacy_purchase(
  VARCHAR, VARCHAR, JSONB
) TO authenticated;
GRANT EXECUTE ON FUNCTION receive_pharmacy_purchase(UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION place_pharmacy_order(
  VARCHAR, JSONB, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION update_pharmacy_order_status(
  UUID, pharmacy_order_status
) TO authenticated;
GRANT EXECUTE ON FUNCTION create_pharmacy_customer_request(
  VARCHAR, VARCHAR, VARCHAR, UUID, VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION update_pharmacy_request_status(
  UUID, pharmacy_customer_request_status
) TO authenticated;

DO $$
DECLARE
  relation_name TEXT;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[
    'pharmacies',
    'pharmacy_products',
    'pharmacy_purchase_orders',
    'pharmacy_sales',
    'pharmacy_orders',
    'pharmacy_customer_requests'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'ientier'
        AND tablename = relation_name
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE ientier.%I',
        relation_name
      );
    END IF;
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
