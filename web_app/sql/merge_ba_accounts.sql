-- =============================================================================
-- Merge registered BAs (profiles + ba_id) with Excel/import history
-- Run in Supabase SQL Editor AFTER May (or other) imports are loaded.
--
-- Safe to re-run. Does NOT delete rows. Does NOT remove app submissions.
-- =============================================================================

-- ── 1) Functions (same as link_ba_accounts.sql) ─────────────────────────────
create or replace function public.normalize_ba_name(raw text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(raw, '')), '\s+', ' ', 'g'));
$$;

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

grant execute on function public.normalize_ba_name(text) to anon, authenticated;
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

-- ── 3) NAME MAP — edit rows to match YOUR Supabase Auth / profiles ─────────
-- registered_name = what they typed at sign-up (profiles.name today)
-- roster_name     = name on Excel import (sales_entries with ba_id null)
create temp table ba_merge_map (
  registered_name text not null,
  roster_name     text not null
);

insert into ba_merge_map (registered_name, roster_name) values
  ('Mohamed Ahmed',   'Mohamed'),
  ('Mamdouh Mohamed', 'Mamdouh'),
  ('Nada Saad',       'Nada'),
  ('Eman salah',      'Eman1'),      -- change to Eman2 if that is the same person
  ('veronia',         'Veronia'),
  ('Samah mohamed',   'Samah'),
  ('Samah Mohamed',   'Samah');
  -- Add more rows below as needed:
  -- ('Full Name At Signup', 'ExcelName'),

-- ── 4) Apply roster names to profiles ───────────────────────────────────────
update public.profiles p
set name = m.roster_name
from ba_merge_map m
where p.role = 'ba'
  and public.normalize_ba_name(p.name) = public.normalize_ba_name(m.registered_name);

-- ── 5) Link import rows → ba_id for every registered BA ─────────────────────
do $$
declare
  r record;
  res json;
begin
  for r in
    select id, name from public.profiles where role = 'ba' order by name
  loop
    res := public.link_legacy_rows_for_profile(r.id, r.name);
    raise notice 'Linked % (id %): %', r.name, r.id, res;
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

-- ── 7) AFTER: unlinked import rows (should shrink; fix map + re-run if any) ─
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

-- ── 8) Duplicate accounts? (two logins, same person — fix manually in Auth) ─
select public.normalize_ba_name(name) as name_key,
       array_agg(name order by name) as profile_names,
       array_agg(id::text order by name) as user_ids,
       count(*) as accounts
from public.profiles
where role = 'ba'
group by public.normalize_ba_name(name)
having count(*) > 1;
