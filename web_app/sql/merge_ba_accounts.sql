-- =============================================================================
-- Merge registered BAs (profiles + ba_id) with Excel/import history
-- Run in Supabase SQL Editor AFTER May (or other) imports are loaded.
--
-- Safe to re-run. Removes duplicate sales/attendance rows (keeps best row per day/shift).
-- Does NOT delete unique app-only rows; only drops true duplicates after linking.
-- =============================================================================

-- ── 1) Functions (same as link_ba_accounts.sql) ─────────────────────────────
create or replace function public.normalize_ba_name(raw text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(raw, '')), '\s+', ' ', 'g'));
$$;

-- p_display_name: keep profiles.name as the BA typed at signup (unchanged).
-- p_import_match_name: Excel roster name to match import rows (defaults to display name).
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
  norm_display text;
  norm_match text;
begin
  norm_display := public.normalize_ba_name(p_display_name);
  norm_match := public.normalize_ba_name(coalesce(nullif(trim(p_import_match_name), ''), p_display_name));
  if norm_display = '' or p_user_id is null then
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
  return public.link_legacy_rows_for_profile(
    auth.uid(),
    v_name,
    public.import_roster_name_for_profile(v_name)
  );
end;
$$;

-- Excel roster short name for a profile display name (signup / full name).
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
          ('Nouran adel',     'Nouran'),
          ('Besher Nasr',     'Besher'),
          ('Basher Nasr',     'Besher'),
          ('Bisher Naser',    'Besher'),
          ('Nadine Taimour',  'Nadine')
      ) as m(registered_name, roster_name)
      where public.normalize_ba_name(m.registered_name) = public.normalize_ba_name(p_display_name)
      limit 1
    ),
    p_display_name
  );
$$;

grant execute on function public.normalize_ba_name(text) to anon, authenticated;
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

grant execute on function public.import_roster_name_for_profile(text) to authenticated;
grant execute on function public.import_roster_matches_name(p_entry_name text, p_roster_name text) to authenticated;
grant execute on function public.link_my_legacy_rows() to authenticated;

-- ── 2) BEFORE: see split (import vs app) ────────────────────────────────────
select
  ba_name,
  case when ba_id is null then 'excel_import' else 'ba_app' end as source,
  count(*) as rows
from public.sales_entries
where entry_date >= '2026-01-01'
group by ba_name, case when ba_id is null then 'excel_import' else 'ba_app' end
order by ba_name, source;

-- ── 3) NAME MAP — links Excel imports to accounts WITHOUT renaming profiles ─
-- registered_name = profiles.name (what the BA chose at signup — kept as-is)
-- roster_name     = name on Excel import rows (ba_id null) to attach to that account
create temp table ba_merge_map (
  registered_name text not null,
  roster_name     text not null
);

insert into ba_merge_map (registered_name, roster_name) values
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
  ('Nouran adel',     'Nouran'),
  ('Besher Nasr',     'Besher'),
  ('Basher Nasr',     'Besher'),
  ('Bisher Naser',    'Besher'),
  ('Nadine Taimour',  'Nadine');
  -- Add more rows below as needed:
  -- ('Full Name At Signup', 'ExcelName'),

-- ── 4) (skipped) Profiles keep the name each BA chose at signup ─────────────

-- ── 5) Link import rows → ba_id (match Excel name, display = profile name) ─
do $$
declare
  r record;
  v_roster text;
  v_match text;
  res json;
begin
  for r in
    select id, name from public.profiles where role = 'ba' order by name
  loop
    select m.roster_name into v_roster
    from ba_merge_map m
    where public.normalize_ba_name(m.registered_name) = public.normalize_ba_name(r.name)
    limit 1;
    v_match := coalesce(v_roster, public.import_roster_name_for_profile(r.name), r.name);
    res := public.link_legacy_rows_for_profile(r.id, r.name, v_match);
    raise notice 'Linked % via import name "%": %', r.name, v_match, res;
  end loop;
end $$;

-- ── 6) Align ba_name on rows already tied to a profile (app + linked import) ─
update public.sales_entries s
set ba_name = p.name
from public.profiles p
where s.ba_id = p.id
  and trim(s.ba_name) is distinct from trim(p.name);

update public.ba_attendance_entries a
set ba_name = p.name
from public.profiles p
where a.ba_id = p.id
  and trim(a.ba_name) is distinct from trim(p.name);

-- ── 7) REMOVE duplicate sales (same BA + date + shop + shift) ───────────────
-- Typical case: Excel import + BA app log for the same day after merge.
-- Keeps one row: prefers sales logged, then newest created_at.
with sales_ranked as (
  select
    id,
    row_number() over (
      partition by
        coalesce(ba_id::text, 'name:' || public.normalize_ba_name(ba_name)),
        entry_date,
        coalesce(store, ''),
        coalesce(shift, '')
      order by
        (case when coalesce(sales_amount, 0) > 0 then 1 else 0 end) desc,
        created_at desc nulls last,
        id desc
    ) as rn
  from public.sales_entries
)
delete from public.sales_entries s
using sales_ranked r
where s.id = r.id and r.rn > 1;

-- ── 8) REMOVE duplicate attendance (same BA + date) ─────────────────────────
with att_ranked as (
  select
    id,
    row_number() over (
      partition by
        coalesce(ba_id::text, 'name:' || public.normalize_ba_name(ba_name)),
        entry_date
      order by created_at desc nulls last, id desc
    ) as rn
  from public.ba_attendance_entries
)
delete from public.ba_attendance_entries a
using att_ranked r
where a.id = r.id and r.rn > 1;

-- ── 9) AFTER: unlinked import rows (should shrink; fix map + re-run if any) ─
select ba_name, team, count(*) as import_rows
from public.sales_entries
where ba_id is null
group by ba_name, team
order by ba_name;

select
  p.name as profile_name,
  p.team,
  count(s.id) filter (where s.ba_id = p.id) as linked_sales_rows,
  count(s.id) filter (where s.ba_id is null
    and public.normalize_ba_name(s.ba_name) = public.normalize_ba_name(p.name)) as still_unlinked
from public.profiles p
left join public.sales_entries s on s.ba_id = p.id or (
  s.ba_id is null and public.normalize_ba_name(s.ba_name) = public.normalize_ba_name(p.name)
)
where p.role = 'ba'
group by p.id, p.name, p.team
order by p.name;

-- ── 10) Verify: duplicate sales should be 0 ───────────────────────────────────
select
  coalesce(ba_id::text, 'name:' || public.normalize_ba_name(ba_name)) as ba_key,
  entry_date,
  store,
  shift,
  count(*) as cnt
from public.sales_entries
group by 1, entry_date, store, shift
having count(*) > 1;

-- ── 11) Duplicate logins? (two Auth users, same roster name — fix in Auth UI) ─
select public.normalize_ba_name(name) as name_key,
       array_agg(name order by name) as profile_names,
       array_agg(id::text order by name) as user_ids,
       count(*) as accounts
from public.profiles
where role = 'ba'
group by public.normalize_ba_name(name)
having count(*) > 1;
