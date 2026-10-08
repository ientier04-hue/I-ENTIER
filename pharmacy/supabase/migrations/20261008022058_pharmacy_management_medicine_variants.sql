-- Pharmacy-managed medicine identities. Existing exclusive catalogues retain IDs.
alter table ientier.medicines add column owner_pharmacy_id varchar(128) references ientier.pharmacies(pharmacy_id);
create index medicines_owner_pharmacy_idx on ientier.medicines(owner_pharmacy_id);
update ientier.medicines m set owner_pharmacy_id=x.pharmacy_id
from (select v.medicine_id,min(p.pharmacy_id) as pharmacy_id
      from ientier.medicine_variants v join ientier.pharmacy_products p using(variant_id)
      group by v.medicine_id having count(distinct p.pharmacy_id)=1) x
where m.medicine_id=x.medicine_id;
create policy medicines_owner_read on ientier.medicines for select to authenticated
using(owner_pharmacy_id=(select ientier.current_actor_id()) or (select ientier.current_actor_is_admin()));
create policy medicine_variants_owner_read on ientier.medicine_variants for select to authenticated
using(exists(select 1 from ientier.medicines m where m.medicine_id=medicine_variants.medicine_id
  and (m.owner_pharmacy_id=(select ientier.current_actor_id()) or (select ientier.current_actor_is_admin()))));

-- Stream the product table in Flutter, then fetch this joined, RLS-protected view.
create view ientier.v_pharmacy_management_products with(security_invoker=true) as
select p.*,m.medicine_id,m.name as medicine_name,m.laboratory,m.owner_pharmacy_id as medicine_owner_pharmacy_id
from ientier.pharmacy_products p
left join ientier.medicine_variants v on v.variant_id=p.variant_id
left join ientier.medicines m on m.medicine_id=v.medicine_id
where p.pharmacy_id=ientier.current_actor_id() or ientier.current_actor_is_admin();
grant select on ientier.v_pharmacy_management_products to authenticated;

-- Linked rows always use canonical presentation metadata, including old clients.
create function ientier.sync_pharmacy_product_presentation() returns trigger
language plpgsql security invoker set search_path='' as $$
declare v record;
begin
  if new.variant_id is null then return new; end if;
  select mv.*,m.name,m.active_ingredient,m.category,m.owner_pharmacy_id into v
  from ientier.medicine_variants mv join ientier.medicines m using(medicine_id)
  where mv.variant_id=new.variant_id;
  if not found or (v.owner_pharmacy_id is not null and v.owner_pharmacy_id<>new.pharmacy_id) then
    raise exception 'Présentation inaccessible à cette pharmacie.';
  end if;
  new.name:=left(v.name||' · '||v.strength||' · '||v.dosage_form||' · '||v.pack_size,180);
  new.active_ingredient:=v.active_ingredient;
  new.category:=v.category;
  new.strength:=v.strength;
  new.dosage_form:=v.dosage_form;
  new.pack_size:=v.pack_size;
  return new;
end;
$$;
revoke all on function ientier.sync_pharmacy_product_presentation() from public,anon,authenticated;
create trigger pharmacy_product_presentation_sync before insert or update of variant_id,name,active_ingredient,category,strength,dosage_form,pack_size
on ientier.pharmacy_products for each row execute function ientier.sync_pharmacy_product_presentation();

create schema if not exists ientier_private;
revoke all on schema ientier_private from public,anon;
grant usage on schema ientier_private to authenticated,service_role;
create function ientier_private.save_pharmacy_catalog_product(p_product jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  actor_id text:=auth.uid()::text;
  pharmacy_id_value varchar(128):=p_product->>'pharmacy_id';
  product_id_value uuid:=nullif(p_product->>'product_id','')::uuid;
  medicine_id_value uuid:=nullif(p_product->>'medicine_id','')::uuid;
  variant_id_value uuid;
  old_product ientier.pharmacy_products%rowtype;
  medicine ientier.medicines%rowtype;
  name_value text:=btrim(coalesce(p_product->>'medicine_name',p_product->>'name',''));
  lab_value text:=btrim(coalesce(p_product->>'laboratory',''));
  ingredient_value text:=btrim(coalesce(p_product->>'active_ingredient',''));
  category_value text:=btrim(coalesce(p_product->>'category',''));
  form_value text:=btrim(coalesce(p_product->>'dosage_form',''));
  strength_value text:=btrim(coalesce(p_product->>'strength',''));
  pack_value text:=btrim(coalesce(p_product->>'pack_size',''));
begin
  if actor_id is null or pharmacy_id_value is null or
     (actor_id<>pharmacy_id_value and not ientier.current_actor_is_admin()) then
    raise exception 'Cette pharmacie n’appartient pas à la session.';
  end if;
  -- Serialize edits within this pharmacy; prices and stock remain per product.
  perform 1 from ientier.pharmacies ph where ph.pharmacy_id=pharmacy_id_value and ph.operational_status='active' for update;
  if not found then raise exception 'Pharmacie inactive ou introuvable.'; end if;
  if length(name_value) not between 2 and 180 or length(category_value) not between 2 and 120 or
     length(form_value)=0 or length(strength_value)=0 or length(pack_value)=0 then
    raise exception 'Nom, catégorie, forme, dosage et conditionnement sont requis.';
  end if;
  if product_id_value is not null then
    select * into old_product from ientier.pharmacy_products p where p.product_id=product_id_value and p.pharmacy_id=pharmacy_id_value for update;
    if not found then raise exception 'Produit introuvable dans cette pharmacie.'; end if;
    if old_product.variant_id is not null and not exists (
      select 1 from ientier.medicine_variants v where v.variant_id=old_product.variant_id and v.medicine_id=medicine_id_value
    ) then raise exception 'Le rattachement du médicament a changé. Actualisez le catalogue.'; end if;
  end if;
  if medicine_id_value is null then
    insert into ientier.medicines(slug,name,laboratory,active_ingredient,category,owner_pharmacy_id,is_published)
    values('pharmacy-'||gen_random_uuid()::text,name_value,lab_value,ingredient_value,category_value,pharmacy_id_value,false)
    returning * into medicine;
    medicine_id_value:=medicine.medicine_id;
  else
    select * into medicine from ientier.medicines m where m.medicine_id=medicine_id_value for update;
    if not found or (medicine.owner_pharmacy_id is not null and medicine.owner_pharmacy_id<>pharmacy_id_value) or
      (medicine.owner_pharmacy_id is null and not medicine.is_published) then
      raise exception 'Médicament inaccessible à cette pharmacie.';
    end if;
    if medicine.owner_pharmacy_id is null and
       (medicine.name,medicine.laboratory,medicine.active_ingredient,medicine.category) is distinct from
       (name_value,lab_value,ingredient_value,category_value) then
      raise exception 'L’identité de ce médicament partagé ne peut pas être modifiée.';
    end if;
    if medicine.owner_pharmacy_id=pharmacy_id_value then
      update ientier.medicines set name=name_value,laboratory=lab_value,active_ingredient=ingredient_value,category=category_value
      where medicine_id=medicine_id_value;
    end if;
  end if;
  -- Presentations are reused or created, never changed beneath another SKU.
  insert into ientier.medicine_variants(medicine_id,dosage_form,strength,pack_size)
  values(medicine_id_value,form_value,strength_value,pack_value)
  on conflict(medicine_id,dosage_form,strength,pack_size) do nothing;
  select v.variant_id into variant_id_value from ientier.medicine_variants v
  where v.medicine_id=medicine_id_value and v.dosage_form=form_value and v.strength=strength_value and v.pack_size=pack_value;
  if exists(select 1 from ientier.pharmacy_products p where p.pharmacy_id=pharmacy_id_value and p.variant_id=variant_id_value
    and p.product_id is distinct from product_id_value) then
    raise exception 'Cette présentation existe déjà dans votre catalogue.';
  end if;
  if product_id_value is null then
    insert into ientier.pharmacy_products(pharmacy_id,variant_id,sku,barcode,name,category,controlled_substance,
      selling_price,purchase_price,stock_quantity,reorder_level,is_active,is_published,requires_prescription)
    values(pharmacy_id_value,variant_id_value,btrim(p_product->>'sku'),btrim(coalesce(p_product->>'barcode','')),name_value,category_value,
      coalesce((p_product->>'controlled_substance')::boolean,false),(p_product->>'selling_price')::numeric,
      (p_product->>'purchase_price')::numeric,coalesce((p_product->>'stock_quantity')::numeric,0),
      coalesce((p_product->>'reorder_level')::numeric,0),coalesce((p_product->>'is_active')::boolean,true),
      coalesce((p_product->>'is_published')::boolean,false),false)
    returning product_id into product_id_value;
  else
    update ientier.pharmacy_products set variant_id=variant_id_value,sku=btrim(p_product->>'sku'),
      barcode=btrim(coalesce(p_product->>'barcode','')),controlled_substance=coalesce((p_product->>'controlled_substance')::boolean,false),
      selling_price=(p_product->>'selling_price')::numeric,purchase_price=(p_product->>'purchase_price')::numeric,
      reorder_level=coalesce((p_product->>'reorder_level')::numeric,0),is_active=coalesce((p_product->>'is_active')::boolean,true),
      is_published=coalesce((p_product->>'is_published')::boolean,false)
    where product_id=product_id_value;
  end if;
  -- Touch sibling rows so realtime consumers reload the shared identity too.
  update ientier.pharmacy_products p set name=p.name
  where p.pharmacy_id=pharmacy_id_value and p.product_id<>product_id_value
    and p.variant_id in(select v.variant_id from ientier.medicine_variants v where v.medicine_id=medicine_id_value);
  update ientier.medicines m set is_published=exists(
    select 1 from ientier.pharmacy_products p join ientier.medicine_variants v using(variant_id)
    where v.medicine_id=medicine_id_value and p.is_active and p.is_published)
  where m.medicine_id=medicine_id_value and m.owner_pharmacy_id=pharmacy_id_value;
  return product_id_value;
end;
$$;
revoke all on function ientier_private.save_pharmacy_catalog_product(jsonb) from public,anon;
grant execute on function ientier_private.save_pharmacy_catalog_product(jsonb) to authenticated;
create function ientier.save_pharmacy_catalog_product(p_product jsonb) returns uuid
language sql security invoker set search_path='' as $$
  select ientier_private.save_pharmacy_catalog_product(p_product);
$$;
revoke all on function ientier.save_pharmacy_catalog_product(jsonb) from public,anon;
grant execute on function ientier.save_pharmacy_catalog_product(jsonb) to authenticated;
notify pgrst,'reload schema';
