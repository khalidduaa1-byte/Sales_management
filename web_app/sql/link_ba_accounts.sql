-- ================================================================
-- Link BA signups to existing imported sales (ba_id was null)
-- Run once in Supabase SQL Editor (safe to re-run)
-- ================================================================

-- Same spelling rules as the manager dashboard (trim, collapse spaces, lowercase).
create or replace function public.normalize_ba_name(raw text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(raw, '')), '\s+', ' ', 'g'));
$$;

-- Attach legacy import rows to a profile by normalized name match.
create or replace function public.link_legacy_rows_for_profile(p_user_id uuid, p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  n_sales int;
  n_att int;
  norm text;
begin
  norm := public.normalize_ba_name(p_name);
  if norm = '' or p_user_id is null then
    return json_build_object('ok', false, 'sales_linked', 0, 'attendance_linked', 0);
  end if;

  update public.sales_entries
  set ba_id = p_user_id,
      ba_name = trim(p_name)
  where ba_id is null
    and public.normalize_ba_name(ba_name) = norm;
  get diagnostics n_sales = row_count;

  update public.ba_attendance_entries
  set ba_id = p_user_id,
      ba_name = trim(p_name)
  where ba_id is null
    and public.normalize_ba_name(ba_name) = norm;
  get diagnostics n_att = row_count;

  return json_build_object('ok', true, 'sales_linked', n_sales, 'attendance_linked', n_att);
end;
$$;

-- Called from the BA app after login (fixes accounts created before this migration).
create or replace function public.link_my_legacy_rows()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  select name into v_name from public.profiles where id = auth.uid();
  if v_name is null then
    return json_build_object('ok', false, 'error', 'no_profile');
  end if;
  return public.link_legacy_rows_for_profile(auth.uid(), v_name);
end;
$$;

-- Names from imports not yet claimed by a registered BA (for the Register dropdown).
create or replace function public.get_registration_ba_names()
returns table (ba_name text, team text)
language sql
security definer
stable
set search_path = public
as $$
  select distinct on (public.normalize_ba_name(n.ba_name))
    trim(n.ba_name) as ba_name,
    trim(n.team) as team
  from (
    select ba_name, team from public.sales_entries where ba_id is null
    union all
    select ba_name, team from public.ba_attendance_entries where ba_id is null
  ) n
  where trim(coalesce(n.ba_name, '')) <> ''
    and trim(coalesce(n.team, '')) <> ''
    and not exists (
      select 1 from public.profiles p
      where p.role = 'ba'
        and public.normalize_ba_name(p.name) = public.normalize_ba_name(n.ba_name)
    )
  order by public.normalize_ba_name(ba_name);
$$;

-- Signup trigger: create profile + link historical rows for that name.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_team text;
begin
  v_name := trim(coalesce(new.raw_user_meta_data->>'name', 'Unknown'));
  v_team := nullif(trim(coalesce(new.raw_user_meta_data->>'team', '')), '');

  insert into public.profiles (id, name, role, team, store)
  values (
    new.id,
    v_name,
    coalesce(new.raw_user_meta_data->>'role', 'ba'),
    v_team,
    nullif(trim(coalesce(new.raw_user_meta_data->>'store', '')), '')
  );

  if coalesce(new.raw_user_meta_data->>'role', 'ba') = 'ba' then
    perform public.link_legacy_rows_for_profile(new.id, v_name);
  end if;

  return new;
end;
$$;

grant execute on function public.normalize_ba_name(text) to anon, authenticated;
grant execute on function public.get_registration_ba_names() to anon, authenticated;
grant execute on function public.link_my_legacy_rows() to authenticated;

-- One-time: link everyone who already registered (re-run anytime).
do $$
declare
  r record;
  res json;
begin
  for r in select id, name from public.profiles where role = 'ba'
  loop
    res := public.link_legacy_rows_for_profile(r.id, r.name);
    raise notice 'Profile % (%): %', r.name, r.id, res;
  end loop;
end $$;
