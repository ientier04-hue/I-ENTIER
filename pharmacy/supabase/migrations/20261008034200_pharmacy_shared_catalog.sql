-- Select existing published catalogue presentations; pharmacy settings only.
create or replace function ientier.sync_pharmacy_product_presentation() returns trigger
language plpgsql security invoker set search_path='' as $$
declare v record;
begin
  if new.variant_id is null then return new; end if;
  select mv.*,m.name,m.active_ingredient,m.category,m.owner_pharmacy_id,m.is_published into v
  from ientier.medicine_variants mv join ientier.medicines m using(medicine_id)
  where mv.variant_id=new.variant_id;
  if not found or (v.owner_pharmacy_id is not null and v.owner_pharmacy_id<>new.pharmacy_id and not v.is_published) then
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

create or replace function ientier_private.save_pharmacy_catalog_product(p_product jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  actor_id text:=auth.uid()::text;
  pharmacy_id_value varchar(128):=p_product->>'pharmacy_id';
  product_id_value uuid:=nullif(p_product->>'product_id','')::uuid;
  medicine_id_value uuid:=nullif(p_product->>'medicine_id','')::uuid;
  variant_id_value uuid:=nullif(p_product->>'variant_id','')::uuid;
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
  if product_id_value is not null then
    select * into old_product from ientier.pharmacy_products p where p.product_id=product_id_value and p.pharmacy_id=pharmacy_id_value for update;
    if not found then raise exception 'Produit introuvable dans cette pharmacie.'; end if;
    if old_product.variant_id is not null and not exists (
      select 1 from ientier.medicine_variants v where v.variant_id=old_product.variant_id and v.medicine_id=medicine_id_value
    ) then raise exception 'Le rattachement du médicament a changé. Actualisez le catalogue.'; end if;
  end if;
  select m.* into medicine from ientier.medicines m
  join ientier.medicine_variants v using(medicine_id)
  where v.variant_id=variant_id_value and m.medicine_id=medicine_id_value
    and (m.is_published or (old_product.product_id is not null and old_product.variant_id=v.variant_id));
  if not found then raise exception 'Sélectionnez une présentation du catalogue.'; end if;
  if old_product.product_id is not null and old_product.variant_id is distinct from variant_id_value then
    raise exception 'La présentation du produit ne peut pas être modifiée.';
  end if;
  name_value:=medicine.name;
  category_value:=medicine.category;
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
  return product_id_value;
end;
$$;

notify pgrst,'reload schema';
