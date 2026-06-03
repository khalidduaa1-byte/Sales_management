-- add_profiles_start_date.sql
-- ================================================================
-- WHAT / WHY
-- profiles had no notion of when a BA started, so the manager dashboard's
-- Missing Sales calendar showed every registered BA in every month — e.g.
-- Nadine (joined May 2026) appeared as "all days missing" for Jan–Apr.
--
-- This adds profiles.start_date and makes it self-maintaining:
--   1. Backfill existing BAs from their earliest sales/attendance activity
--      (Nadine -> 2026-05-01; everyone else -> their first month). BAs with no
--      activity fall back to their auth registration date.
--   2. New signups get start_date = registration date (Africa/Cairo).
--   3. If older imported history is later linked to a BA, their start_date is
--      pulled back to that earliest row.
--
-- The dashboard then hides a BA from any month before their start month.
-- Idempotent and non-destructive. Run in the Supabase SQL Editor.
-- ================================================================

-- 1. Column
alter table public.profiles add column if not exists start_date date;

-- 2. Backfill existing BAs (only where unset, so manual overrides are preserved)
with activity as (
  select ba_id, min(d) as first_d
  from (
    select ba_id, min(entry_date) as d
      from public.sales_entries where ba_id is not null group by ba_id
    union all
    select ba_id, min(entry_date) as d
      from public.ba_attendance_entries where ba_id is not null group by ba_id
  ) x
  group by ba_id
)
update public.profiles p
set start_date = coalesce(
  (select first_d from activity a where a.ba_id = p.id),
  (select u.created_at::date from auth.users u where u.id = p.id)
)
where p.role = 'ba' and p.start_date is null;

-- 3. New signups: stamp start_date at profile creation (Africa/Cairo date).
--    (The link step below pulls it earlier if imported history is attached.)
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

  insert into public.profiles (id, name, role, team, store, start_date)
  values (
    new.id,
    v_name,
    coalesce(new.raw_user_meta_data->>'role', 'ba'),
    v_team,
    nullif(trim(coalesce(new.raw_user_meta_data->>'store', '')), ''),
    (now() at time zone 'Africa/Cairo')::date
  );

  if coalesce(new.raw_user_meta_data->>'role', 'ba') = 'ba' then
    perform public.link_legacy_rows_for_profile(
      new.id,
      v_name,
      public.import_roster_name_for_profile(v_name)
    );
  end if;

  return new;
end;
$$;

-- 4. When legacy rows are linked, pull start_date back to the earliest linked row.
create or replace function public.link_legacy_rows_for_profile(
  p_user_id uuid,
  p_display_name text,
  p_import_match_name text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  n_sales int;
  n_att int;
  norm_match text;
  v_min date;
begin
  norm_match := public.normalize_ba_name(coalesce(nullif(trim(p_import_match_name), ''), p_display_name));
  if public.normalize_ba_name(p_display_name) = '' or p_user_id is null then
    return json_build_object('ok', false, 'sales_linked', 0, 'attendance_linked', 0);
  end if;

  update public.sales_entries
  set ba_id = p_user_id,
      ba_name = trim(p_display_name)
  where ba_id is null
    and public.normalize_ba_name(ba_name) = norm_match;
  get diagnostics n_sales = row_count;

  update public.ba_attendance_entries
  set ba_id = p_user_id,
      ba_name = trim(p_display_name)
  where ba_id is null
    and public.normalize_ba_name(ba_name) = norm_match;
  get diagnostics n_att = row_count;

  -- LEAST ignores NULLs; only narrows start_date when a real earlier date exists.
  select least(
    (select min(entry_date) from public.sales_entries where ba_id = p_user_id),
    (select min(entry_date) from public.ba_attendance_entries where ba_id = p_user_id)
  ) into v_min;
  if v_min is not null then
    update public.profiles
    set start_date = case when start_date is null then v_min else least(start_date, v_min) end
    where id = p_user_id;
  end if;

  return json_build_object('ok', true, 'sales_linked', n_sales, 'attendance_linked', n_att);
end;
$$;

-- Verify after running:
--   select name, team, start_date from public.profiles where role='ba' order by start_date, name;
-- Nadine Taimour should show 2026-05-01; the rest should show their first month.
