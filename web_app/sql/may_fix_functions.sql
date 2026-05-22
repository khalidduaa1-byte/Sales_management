-- =============================================================================
-- Run this ONCE in Supabase SQL Editor before May compare / dedupe / fix scripts.
-- Creates: normalize_ba_name, import_roster_name_for_profile, entry_roster_name,
--          link_legacy_rows_for_profile, import_roster_matches_name
-- =============================================================================

create or replace function public.normalize_ba_name(raw text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(raw, '')), '\s+', ' ', 'g'));
$$;

create or replace function public.import_roster_name_for_profile(p_display_name text)
returns text
language sql
immutable
as $$
  select coalesce(
    (
      select m.roster_name
      from (
        values
          ('Mohamed Ahmed',   'Mohamed'),
          ('Mamdouh Mohamed', 'Mamdouh'),
          ('Nada Saad',       'Nada'),
          ('Emaan Salah',     'Eman1'),
          ('Eman salah',      'Eman1'),
          ('veronia',         'Veronia'),
          ('Samah mohamed',   'Samah'),
          ('Samah Mohamed',   'Samah'),
          ('ahmed abdelaal',  'Ahmed'),
          ('Esraa Abdullah',  'Esraa'),
          ('Mohamed Atef',    'Atef'),
          ('Nouran adel',     'Nouran')
      ) as m(registered_name, roster_name)
      where public.normalize_ba_name(m.registered_name) = public.normalize_ba_name(p_display_name)
      limit 1
    ),
    p_display_name
  );
$$;

create or replace function public.entry_roster_name(p_ba_name text, p_profile_name text)
returns text
language sql
stable
as $$
  select coalesce(
    nullif(public.import_roster_name_for_profile(p_profile_name), ''),
    trim(p_ba_name)
  );
$$;

create or replace function public.import_roster_matches_name(p_entry_name text, p_roster_name text)
returns boolean
language sql
immutable
as $$
  select
    public.normalize_ba_name(coalesce(p_entry_name, '')) = public.normalize_ba_name(coalesce(p_roster_name, ''))
    or public.normalize_ba_name(public.import_roster_name_for_profile(p_entry_name))
       = public.normalize_ba_name(coalesce(p_roster_name, ''));
$$;

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
begin
  norm_match := public.normalize_ba_name(coalesce(nullif(trim(p_import_match_name), ''), p_display_name));
  if norm_match = '' or p_user_id is null then
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

  return json_build_object('ok', true, 'sales_linked', n_sales, 'attendance_linked', n_att);
end;
$$;

grant execute on function public.normalize_ba_name(text) to anon, authenticated;

select public.entry_roster_name('Mamdouh Mohamed', 'Mamdouh Mohamed') as test_roster_name;
-- Expected: Mamdouh
