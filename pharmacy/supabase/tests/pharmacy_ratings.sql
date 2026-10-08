begin;
select set_config('test.rating_user_a', gen_random_uuid()::text, true);
select set_config('test.rating_user_b', gen_random_uuid()::text, true);
select set_config('test.rating_pharmacy', (select pharmacy_id from ientier.pharmacies where public_enabled and operational_status='active' limit 1), true);
select set_config('test.rating_count', (select count(*)::text from ientier.pharmacy_ratings where pharmacy_id=current_setting('test.rating_pharmacy')), true);
insert into auth.users(id, aud, role) values
  (current_setting('test.rating_user_a')::uuid, 'authenticated', 'authenticated'),
  (current_setting('test.rating_user_b')::uuid, 'authenticated', 'authenticated');
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('test.rating_user_a'), true);
insert into ientier.pharmacy_ratings(pharmacy_id,user_id,rating)
values(current_setting('test.rating_pharmacy'),auth.uid(),4);
insert into ientier.pharmacy_ratings(pharmacy_id,user_id,rating)
values(current_setting('test.rating_pharmacy'),auth.uid(),5)
on conflict(pharmacy_id,user_id) do update set rating=excluded.rating;
do $$ begin
  if (select count(*) from ientier.pharmacy_ratings) <> 1 then raise exception 'Duplicate rating'; end if;
  begin
    update ientier.pharmacy_ratings set rating=0 where user_id=auth.uid();
    raise exception 'Invalid rating accepted';
  exception when check_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub', current_setting('test.rating_user_b'), true);
insert into ientier.pharmacy_ratings(pharmacy_id,user_id,rating)
values(current_setting('test.rating_pharmacy'),auth.uid(),2);
do $$ declare changed integer; summary record; begin
  if (select count(*) from ientier.pharmacy_ratings) <> 1 then raise exception 'Other user ratings exposed'; end if;
  update ientier.pharmacy_ratings set rating=1 where user_id=current_setting('test.rating_user_a')::uuid;
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Other user rating modified'; end if;
  begin
    insert into ientier.pharmacy_ratings(pharmacy_id,user_id,rating)
    values(current_setting('test.rating_pharmacy'),current_setting('test.rating_user_a')::uuid,1)
    on conflict(pharmacy_id,user_id) do update set rating=excluded.rating;
    raise exception 'Forged rating accepted';
  exception when insufficient_privilege then null; end;
  select * into summary from ientier.pharmacy_rating_summaries(array[current_setting('test.rating_pharmacy')]::varchar[]);
  if summary.my_rating <> 2 or summary.rating_count <> current_setting('test.rating_count')::bigint+2 then
    raise exception 'Incorrect rating summary';
  end if;
end $$;
rollback;
