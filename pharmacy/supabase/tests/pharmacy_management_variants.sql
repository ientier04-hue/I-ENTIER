-- Integration assertions run as the pharmacy role; every change rolls back.
begin;
select set_config('request.jwt.claim.sub',(select pharmacy_id from ientier.pharmacies where display_name='La Delivrance Pharma'),true);
set local role authenticated;
do $$
declare
  ph text:=auth.uid()::text;
  payload jsonb;
  first_id uuid;
  second_id uuid;
  med_id uuid;
  v_id uuid;
  denied boolean:=false;
begin
  payload:=jsonb_build_object('pharmacy_id',ph,'sku','TEST-'||gen_random_uuid(),'medicine_name','Test catalogue transactionnel',
    'laboratory','Test labo','active_ingredient','Test','category','Test','dosage_form','Comprimé','strength','500 mg','pack_size','20 comprimés',
    'selling_price',10.5,'purchase_price',4.25,'stock_quantity',5,'reorder_level',2,'is_active',true,'is_published',true);
  first_id:=ientier.save_pharmacy_catalog_product(payload);
  select medicine_id,variant_id into med_id,v_id from ientier.v_pharmacy_management_products where product_id=first_id;
  if med_id is null or v_id is null then raise exception 'FAIL: missing catalogue links'; end if;
  if not exists(select 1 from ientier.v_public_medicine_products where product_id=first_id and strength='500 mg' and selling_price=10.5) then
    raise exception 'FAIL: patient view not synchronized'; end if;
  payload:=payload||jsonb_build_object('product_id',first_id,'medicine_id',med_id,'strength','250 mg','stock_quantity',999);
  perform ientier.save_pharmacy_catalog_product(payload);
  if not exists(select 1 from ientier.v_public_medicine_products where product_id=first_id and strength='250 mg' and stock_quantity=5) then
    raise exception 'FAIL: changed dosage or preserved stock'; end if;
  if not exists(select 1 from ientier.medicine_variants where variant_id=v_id and strength='500 mg') then
    raise exception 'FAIL: mutated an existing shared presentation'; end if;
  payload:=(payload-'product_id')||jsonb_build_object('sku','TEST-'||gen_random_uuid(),'dosage_form','Sirop','strength','120 mg/5 ml','pack_size','60 ml','stock_quantity',3);
  second_id:=ientier.save_pharmacy_catalog_product(payload);
  payload:=payload||jsonb_build_object('product_id',second_id,'medicine_name','Test identité modifiée');
  perform ientier.save_pharmacy_catalog_product(payload);
  if (select count(*) from ientier.v_public_medicine_products where medicine_id=med_id and name='Test identité modifiée')<>2 then
    raise exception 'FAIL: sibling identity not synchronized'; end if;
  begin
    perform ientier.save_pharmacy_catalog_product((payload-'product_id')||jsonb_build_object('sku','TEST-'||gen_random_uuid()));
  exception when raise_exception then denied:=sqlerrm like '%existe déjà%'; end;
  if not denied then raise exception 'FAIL: duplicate presentation accepted'; end if;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  denied:=false;
  begin perform ientier.save_pharmacy_catalog_product(payload);
  exception when raise_exception then denied:=sqlerrm like '%appartient%'; end;
  if not denied then raise exception 'FAIL: foreign pharmacy mutation accepted'; end if;
  if exists(select 1 from ientier.v_pharmacy_management_products where product_id=first_id) then
    raise exception 'FAIL: foreign pharmacy inventory exposed'; end if;
end;
$$;
rollback;
