alter table ientier.pharmacies add column photo_url text;

create table ientier.pharmacy_ratings (
  pharmacy_id varchar(128) not null references ientier.pharmacies(pharmacy_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  primary key (pharmacy_id, user_id)
);
create index pharmacy_ratings_user_idx on ientier.pharmacy_ratings(user_id);
alter table ientier.pharmacy_ratings enable row level security;
grant select, insert, update on ientier.pharmacy_ratings to authenticated;
create policy pharmacy_ratings_read_own on ientier.pharmacy_ratings for select to authenticated
  using (user_id = (select auth.uid()));
create policy pharmacy_ratings_insert_own on ientier.pharmacy_ratings for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from ientier.pharmacies ph where ph.pharmacy_id = pharmacy_ratings.pharmacy_id
      and ph.public_enabled and ph.operational_status = 'active'
  ));
create policy pharmacy_ratings_update_own on ientier.pharmacy_ratings for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and exists (
    select 1 from ientier.pharmacies ph where ph.pharmacy_id = pharmacy_ratings.pharmacy_id
      and ph.public_enabled and ph.operational_status = 'active'
  ));

-- Expose aggregates only; reviewer identities remain private under RLS.
create function ientier_private.pharmacy_rating_summaries(p_pharmacy_ids varchar[])
returns table (pharmacy_id varchar, average_rating numeric, rating_count bigint, my_rating smallint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Session requise.'; end if;
  return query
    select ph.pharmacy_id, round(avg(r.rating), 1), count(r.rating),
      max(r.rating) filter (where r.user_id = auth.uid())
    from ientier.pharmacies ph
    left join ientier.pharmacy_ratings r on r.pharmacy_id = ph.pharmacy_id
    where ph.pharmacy_id = any(p_pharmacy_ids)
      and ph.public_enabled and ph.operational_status = 'active'
    group by ph.pharmacy_id;
end;
$$;
revoke all on function ientier_private.pharmacy_rating_summaries(varchar[]) from public, anon, authenticated;
grant execute on function ientier_private.pharmacy_rating_summaries(varchar[]) to authenticated;
create function ientier.pharmacy_rating_summaries(p_pharmacy_ids varchar[])
returns table (pharmacy_id varchar, average_rating numeric, rating_count bigint, my_rating smallint)
language sql stable security invoker set search_path = '' as $$
  select * from ientier_private.pharmacy_rating_summaries(p_pharmacy_ids);
$$;
revoke all on function ientier.pharmacy_rating_summaries(varchar[]) from public, anon, authenticated;
grant execute on function ientier.pharmacy_rating_summaries(varchar[]) to authenticated;
