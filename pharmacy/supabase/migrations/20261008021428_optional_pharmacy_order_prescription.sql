-- Prescription attachment is optional; retain ownership checks for attachments supplied by other clients.
CREATE OR REPLACE FUNCTION ientier.place_pharmacy_order(p_pharmacy_id character varying, p_items jsonb, p_prescription_id character varying DEFAULT NULL::character varying, p_customer_name character varying DEFAULT ''::character varying, p_customer_phone character varying DEFAULT ''::character varying, p_note character varying DEFAULT ''::character varying)
 RETURNS character varying
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'ientier', 'pg_temp'
AS $function$
DECLARE
  actor_id VARCHAR(128) := current_actor_id();
  new_order_id UUID;
  new_order_number VARCHAR(40);
  item JSONB;
  target_product pharmacy_products%ROWTYPE;
  requested_quantity NUMERIC(14,3);
  total NUMERIC(14,2) := 0;
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

  UPDATE pharmacy_orders
  SET subtotal_amount = total,
      total_amount = total
  WHERE order_id = new_order_id;

  RETURN new_order_number;
END;
$function$
;
notify pgrst,'reload schema';
