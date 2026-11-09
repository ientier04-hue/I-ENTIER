-- Parafortan injectable: one shared presentation, with a separate offer per pharmacy.
-- The prices and opening quantities are catalogue values chosen for this app.
begin;

do $add_parafortan$
declare
  medicine_uuid uuid;
  presentation_uuid uuid;
begin
  if (select count(distinct display_name) from ientier.pharmacies
      where operational_status = 'active' and public_enabled
        and display_name in ('La Delivrance Pharma', 'Pharmacie Belvédère (simulation)')) <> 2 then
    raise exception 'Les deux pharmacies attendues doivent être actives et publiées.';
  end if;

  insert into ientier.medicines (
    slug, name, laboratory, active_ingredient, category, source_url, is_published
  ) values (
    'parafortan-injectable', 'Parafortan', 'Khandelwal Laboratories',
    'Diclofénac sodique', 'Anti-inflammatoires',
    'https://www.ktzcompany.com/product/parafortan-inj/', true
  ) on conflict (slug) do nothing;

  select medicine_id into strict medicine_uuid
  from ientier.medicines where slug = 'parafortan-injectable';

  insert into ientier.medicine_variants (
    medicine_id, dosage_form, strength, pack_size
  ) values (
    medicine_uuid, 'Injectable', '75 mg/3 ml', '1 ampoule de 3 ml'
  ) on conflict (medicine_id, dosage_form, strength, pack_size) do nothing;

  select variant_id into strict presentation_uuid
  from ientier.medicine_variants
  where medicine_id = medicine_uuid and dosage_form = 'Injectable'
    and strength = '75 mg/3 ml' and pack_size = '1 ampoule de 3 ml';

  insert into ientier.pharmacy_products (
    pharmacy_id, variant_id, sku, selling_price, currency, stock_quantity,
    reorder_level, requires_prescription, is_active, is_published
  )
  select ph.pharmacy_id, presentation_uuid,
    'PARAFORTAN-' || ph.pharmacy_id,
    case when ph.display_name = 'La Delivrance Pharma' then 20 else 25 end,
    'HTG',
    case when ph.display_name = 'La Delivrance Pharma' then 10 else 8 end,
    2, true, true, true
  from ientier.pharmacies ph
  where ph.operational_status = 'active' and ph.public_enabled
    and ph.display_name in ('La Delivrance Pharma', 'Pharmacie Belvédère (simulation)')
  on conflict (pharmacy_id, variant_id) where variant_id is not null do nothing;
end;
$add_parafortan$;

commit;
