-- =============================================================================
-- Confirm email manually (Rehab, Nadine, Yasmin, etc.) so they can sign in
-- Run in Supabase SQL Editor. Requires permission to update auth.users.
-- =============================================================================

-- A) Who is still waiting? (email_confirmed_at null)
select
  u.id as user_id,
  u.email,
  u.created_at::date as signed_up,
  u.email_confirmed_at,
  u.raw_user_meta_data->>'name' as signup_name,
  u.raw_user_meta_data->>'team' as signup_team,
  p.id is not null as has_profile
from auth.users u
left join public.profiles p on p.id = u.id
where u.email_confirmed_at is null
order by u.created_at desc;

-- B) Confirm by roster name on signup (edit list if needed)
update auth.users u
set email_confirmed_at = coalesce(u.email_confirmed_at, now())
where u.email_confirmed_at is null
  and (
    public.normalize_ba_name(coalesce(u.raw_user_meta_data->>'name', '')) in (
      public.normalize_ba_name('Nadine'),
      public.normalize_ba_name('Rehab'),
      public.normalize_ba_name('Yasmin'),
      public.normalize_ba_name('Besher'),
      public.normalize_ba_name('Besher Nasr')
    )
    -- or add exact emails:
    -- or u.email in ('someone@example.com', 'other@example.com')
  );

-- C) Confirm ALL unconfirmed BAs (only if you want everyone through at once)
-- update auth.users u
-- set email_confirmed_at = coalesce(u.email_confirmed_at, now())
-- where u.email_confirmed_at is null
--   and coalesce(u.raw_user_meta_data->>'role', 'ba') = 'ba';

-- D) Ensure profile exists for newly confirmed users (trigger may have run; safe to re-run)
insert into public.profiles (id, name, role, team, store)
select
  u.id,
  trim(coalesce(u.raw_user_meta_data->>'name', 'Unknown')),
  coalesce(u.raw_user_meta_data->>'role', 'ba'),
  nullif(trim(coalesce(u.raw_user_meta_data->>'team', '')), ''),
  nullif(trim(coalesce(u.raw_user_meta_data->>'store', '')), '')
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
  and u.email_confirmed_at is not null
  and coalesce(u.raw_user_meta_data->>'role', 'ba') = 'ba';

-- E) Link Excel imports (roster short name = signup name for Nadine/Rehab/Yasmin)
do $$
declare
  r record;
  v_match text;
  res json;
begin
  for r in
    select p.id, p.name
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.role = 'ba'
      and u.email_confirmed_at is not null
      and public.normalize_ba_name(p.name) in (
        public.normalize_ba_name('Nadine'),
        public.normalize_ba_name('Rehab'),
        public.normalize_ba_name('Yasmin')
      )
  loop
    v_match := public.import_roster_name_for_profile(r.name);
    res := public.link_legacy_rows_for_profile(r.id, r.name, v_match);
    raise notice 'Linked % via "%": %', r.name, v_match, res;
  end loop;
end $$;

-- F) AFTER — should show confirmed = true
select u.email, u.email_confirmed_at is not null as confirmed,
  p.name, p.team,
  (select count(*) from public.sales_entries s where s.ba_id = p.id) as linked_sales
from auth.users u
join public.profiles p on p.id = u.id
where public.normalize_ba_name(p.name) in (
  public.normalize_ba_name('Nadine'),
  public.normalize_ba_name('Rehab'),
  public.normalize_ba_name('Yasmin')
)
order by p.name;
