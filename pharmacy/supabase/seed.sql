-- Optional simulation data. Run after the I-ENTIER and pharmacy migrations.
begin;
set local search_path = ientier, public;

do $seed$
declare
  demo_id constant text := 'simulation-pharmacie-belvedere';
  demo_name constant text := 'Pharmacie Belvédère (simulation)';
  demo_license constant text := 'SIM-BELVEDERE-02';
  demo_email constant text := 'belvedere@example.invalid';
  demo_phone constant text := '+509 0000 0000';
  demo_address constant text := 'Rue de la Simulation, Pétion-Ville';
  demo_hours constant text := 'Lun–sam 8 h à 18 h';
  offer record;
  presentation uuid;
begin
  -- The simulated owner has no login and is separate from every Auth identity.
  insert into app_users (user_id, display_name, auth_provider)
  values (demo_id, demo_name, 'simulation')
  on conflict (user_id) do nothing;

  insert into provider_profiles (
    provider_id, account_type, display_name, category, registration_number,
    phone, email, address, description, services_summary, schedule_summary, terms_accepted
  ) values (
    demo_id, 'institution', demo_name, 'Pharmacie', demo_license,
    demo_phone, demo_email, demo_address, 'Pharmacie de simulation',
    'Retrait sur place', demo_hours, true
  ) on conflict (provider_id) do nothing;

  insert into pharmacies (
    pharmacy_id, display_name, legal_name, license_number, license_expires_on,
    responsible_pharmacist, phone, email, address, opening_hours,
    operational_status, public_enabled, delivery_available, latitude, longitude
  ) values (
    demo_id, demo_name, demo_name, demo_license, date '2099-12-31',
    'Responsable de simulation', demo_phone, demo_email, demo_address, demo_hours,
    'active', true, false, 18.512, -72.286
  ) on conflict (pharmacy_id) do nothing;

  for offer in
    select * from (values
      ('4c-analgine',    'Comprimé',   '500 mg',      '20 comprimés',  790, 24),
      ('4c-analgine',    'Sirop',      '160 mg/5 ml', '120 ml',        760,  8),
      ('4c-pediaphen',   'Sirop',      '160 mg/5 ml', '120 ml',        920, 15),
      ('4c-pediaphen',   'Gouttes',    '100 mg/ml',   '15 ml',         950,  3),
      ('4c-flaxan',      'Comprimé',   '500 mg',      '20 comprimés',  990, 10),
      ('4c-flaxan',      'Suspension', '125 mg/5 ml', '60 ml',         820,  0),
      ('4c-paracetamol', 'Comprimé',   '500 mg',      '100 comprimés', 625, 20),
      ('4c-paracetamol', 'Sirop',      '120 mg/5 ml', '60 ml',         650, 12)
    ) as inventory(slug, form, strength, pack, price, quantity)
  loop
    -- A missing reference aborts the seed instead of publishing a partial catalogue.
    select v.variant_id into strict presentation
    from medicine_variants v join medicines m using (medicine_id)
    where m.slug = offer.slug and m.is_published and v.dosage_form = offer.form
      and v.strength = offer.strength and v.pack_size = offer.pack;

    -- The presentation trigger fills the product description and the stock trigger
    -- records the opening movement. Replaying the seed preserves subsequent sales.
    insert into pharmacy_products (
      pharmacy_id, variant_id, sku, selling_price, currency, stock_quantity,
      reorder_level, requires_prescription, is_active, is_published
    ) values (
      demo_id, presentation, 'SIM-' || presentation, offer.price, 'HTG',
      offer.quantity, 5, true, true, true
    ) on conflict (pharmacy_id, variant_id) where variant_id is not null do nothing;
  end loop;
end;
$seed$;
commit;
