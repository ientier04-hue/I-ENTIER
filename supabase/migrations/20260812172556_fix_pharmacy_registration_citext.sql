-- Ensure the SECURITY DEFINER registration function can resolve citext while
-- keeping its restricted search_path.
CREATE OR REPLACE FUNCTION ientier.register_pharmacy(
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

NOTIFY pgrst, 'reload schema';
