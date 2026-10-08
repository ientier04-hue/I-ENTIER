-- Shared medicine identity -> valid presentations -> each pharmacy's price/stock.
-- Existing product IDs and order API remain unchanged.
create table ientier.medicines (
  medicine_id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null check (length(trim(name)) between 2 and 180),
  laboratory text not null default '',
  active_ingredient text not null default '',
  category text not null,
  image_url text,
  source_url text,
  is_published boolean not null default false
);
create table ientier.medicine_variants (
  variant_id uuid primary key default gen_random_uuid(),
  medicine_id uuid not null references ientier.medicines(medicine_id),
  dosage_form text not null check (length(trim(dosage_form)) > 0),
  strength text not null check (length(trim(strength)) > 0),
  pack_size text not null check (length(trim(pack_size)) > 0),
  unique (medicine_id, dosage_form, strength, pack_size)
);
alter table ientier.pharmacy_products add column variant_id uuid references ientier.medicine_variants(variant_id);
create index pharmacy_products_variant_idx on ientier.pharmacy_products(variant_id);
create unique index pharmacy_products_pharmacy_variant_idx on ientier.pharmacy_products(pharmacy_id,variant_id) where variant_id is not null;
alter table ientier.medicines enable row level security;
alter table ientier.medicine_variants enable row level security;
grant select on ientier.medicines,ientier.medicine_variants to authenticated;
grant all on ientier.medicines,ientier.medicine_variants to service_role;
create policy medicines_read on ientier.medicines for select to authenticated using (is_published);
create policy medicine_variants_read on ientier.medicine_variants for select to authenticated
using (exists (select 1 from ientier.medicines m where m.medicine_id=medicine_variants.medicine_id and m.is_published));

-- Separate view keeps the original in-stock-only API compatible with other clients.
create view ientier.v_public_medicine_products with (security_invoker=true) as
select p.product_id,p.pharmacy_id,ph.display_name as pharmacy_name,
  coalesce(m.name,p.name) as name,coalesce(m.active_ingredient,p.active_ingredient) as active_ingredient,
  coalesce(m.category,p.category) as category,coalesce(v.pack_size,p.pack_size) as pack_size,
  p.selling_price,p.currency,p.stock_quantity,p.requires_prescription,
  m.medicine_id,p.variant_id,m.laboratory,m.slug as medicine_slug,m.image_url,m.source_url,
  coalesce(v.strength,p.strength) as strength,coalesce(v.dosage_form,p.dosage_form) as dosage_form
from ientier.pharmacy_products p
join ientier.pharmacies ph on ph.pharmacy_id=p.pharmacy_id
left join ientier.medicine_variants v on v.variant_id=p.variant_id
left join ientier.medicines m on m.medicine_id=v.medicine_id
where ph.operational_status='active' and ph.public_enabled and p.is_active and p.is_published
  and (p.variant_id is null or m.is_published);
grant select on ientier.v_public_medicine_products to authenticated;

-- Official 4C catalogue checked 2026-10-07. These are presentation examples,
-- not medical dosing instructions. Prices are catalogue references, not confirmed
-- pharmacy sale prices; stock stays zero until the pharmacy verifies its inventory.
insert into ientier.medicines(slug,name,laboratory,active_ingredient,category,image_url,source_url,is_published) values
('4c-analgine','Analgine','Laboratoires 4C','Acétaminophène','Douleur et fièvre','https://laboratoires4c.com/images/dyn_th/ck_produits_26_1.png','https://laboratoires4c.com/fr/resultat-produit/?id=26',true),
('4c-pediaphen','Pediaphen','Laboratoires 4C','Acétaminophène','Pédiatrie','https://laboratoires4c.com/images/dyn_th/ck_produits_91_1.jpg','https://laboratoires4c.com/fr/resultat-produit/?id=91',true),
('4c-flaxan','Flaxan','Laboratoires 4C','Naproxène','Anti-inflammatoires','https://laboratoires4c.com/images/dyn_th/ck_produits_86_1.jpg','https://laboratoires4c.com/fr/resultat-produit/?id=86',true),
('4c-paracetamol','Paracétamol 4C','Laboratoires 4C','Paracétamol','Douleur et fièvre','https://laboratoires4c.com/images/dyn_th/ck_produits_16_1.jpg','https://laboratoires4c.com/fr/resultat-produit/?id=16',true)
on conflict(slug) do nothing;

insert into ientier.medicine_variants(medicine_id,dosage_form,strength,pack_size)
select m.medicine_id,s.form,s.strength,s.pack from (values
('4c-analgine','Comprimé','500 mg','20 comprimés'),
('4c-analgine','Comprimé','500 mg','170 comprimés'),
('4c-analgine','Sirop','160 mg/5 ml','120 ml'),
('4c-analgine','Gouttes','100 mg/ml','15 ml'),
('4c-pediaphen','Sirop','160 mg/5 ml','120 ml'),
('4c-pediaphen','Gouttes','100 mg/ml','15 ml'),
('4c-flaxan','Comprimé','250 mg','20 comprimés'),
('4c-flaxan','Comprimé','500 mg','20 comprimés'),
('4c-flaxan','Suspension','125 mg/5 ml','60 ml'),
('4c-paracetamol','Comprimé','100 mg','100 comprimés'),
('4c-paracetamol','Comprimé','500 mg','100 comprimés'),
('4c-paracetamol','Sirop','120 mg/5 ml','60 ml')
) s(slug,form,strength,pack) join ientier.medicines m on m.slug=s.slug
on conflict(medicine_id,dosage_form,strength,pack_size) do nothing;

-- Resolve the existing pharmacy by its business name; no generated IDs in seed.
insert into ientier.pharmacy_products(pharmacy_id,sku,name,active_ingredient,category,strength,dosage_form,pack_size,requires_prescription,selling_price,currency,stock_quantity,is_active,is_published,variant_id)
select ph.pharmacy_id,'4C-'||v.variant_id::text,m.name||' · '||v.strength||' · '||v.dosage_form,
  m.active_ingredient,m.category,v.strength,v.dosage_form,v.pack_size,
  true, -- conservative until pharmacy verifies local dispensing status
  case
    when m.slug='4c-analgine' then case when v.dosage_form='Sirop' then 800 when v.dosage_form='Gouttes' then 815 when v.pack_size='170 comprimés' then 2100 else 830 end
    when m.slug='4c-pediaphen' then case when v.dosage_form='Sirop' then 965 else 990 end
    when m.slug='4c-flaxan' then case when v.dosage_form='Suspension' then 860 when v.strength='500 mg' then 1015 else 0 end
    when m.slug='4c-paracetamol' and v.dosage_form='Sirop' then 680
    else 0 end,
  'HTG',0,true,true,v.variant_id
from ientier.medicine_variants v join ientier.medicines m using(medicine_id)
join ientier.pharmacies ph on ph.display_name='La Delivrance Pharma'
where m.slug in ('4c-analgine','4c-pediaphen','4c-flaxan','4c-paracetamol')
on conflict do nothing;
notify pgrst,'reload schema';
