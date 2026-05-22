-- =============================================================================
-- May 1–15: make Supabase match Excel (normalized_may_reload_sales.csv)
--
-- Excel file only has 1 May – 15 May. From 16 May onward BAs may log in the app — leave those alone.
--
-- WHY DATA DRIFTED
-- After merge, ba_name became "Mamdouh Mohamed" but may_reload compared "Mamdouh",
-- so duplicate rows were added and totals inflated.
--
-- RUN ORDER (Supabase SQL Editor)
-- 1) merge_ba_accounts.sql section 1 (functions) if needed
-- 2) may_reload.sql sections 1–2 (staging tables) + import both CSVs into staging
-- 3) RECONCILE section below (read mismatches)
-- 4) FIX section (destructive for May 1–15 only) — confirm reconcile first
-- 5) Re-run link + dedupe section at bottom
-- =============================================================================

-- ── Match Excel roster name ↔ profile / linked ba_name on a row ─────────────
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


-- =============================================================================
-- RECONCILE (requires staging loaded from CSV — see may_reload.sql)
-- =============================================================================

-- A) Expected per BA/day from Excel staging (1–15 May)
select
  trim(s.ba_name) as roster_name,
  s.entry_date,
  count(*) as excel_shifts,
  sum(s.sales_amount)::numeric(12,2) as excel_sales
from public.sales_entries_may_reload_staging s
where s.entry_date between '2026-05-01' and '2026-05-15'
group by trim(s.ba_name), s.entry_date
order by roster_name, s.entry_date;

-- B) Actual per BA/day in DB (roster-normalized names)
select
  public.entry_roster_name(e.ba_name, p.name) as roster_name,
  e.entry_date,
  count(*) as db_shifts,
  sum(e.sales_amount)::numeric(12,2) as db_sales
from public.sales_entries e
left join public.profiles p on p.id = e.ba_id
where e.entry_date between '2026-05-01' and '2026-05-15'
group by 1, e.entry_date
order by 1, e.entry_date;

-- C) Per BA totals 1–15: Excel vs DB (main check)
with excel as (
  select
    trim(ba_name) as roster_name,
    sum(sales_amount)::numeric(12,2) as excel_sales,
    count(*) as excel_rows
  from public.sales_entries_may_reload_staging
  where entry_date between '2026-05-01' and '2026-05-15'
  group by trim(ba_name)
),
db as (
  select
    public.entry_roster_name(e.ba_name, p.name) as roster_name,
    sum(e.sales_amount)::numeric(12,2) as db_sales,
    count(*) as db_rows
  from public.sales_entries e
  left join public.profiles p on p.id = e.ba_id
  where e.entry_date between '2026-05-01' and '2026-05-15'
  group by 1
)
select
  coalesce(e.roster_name, d.roster_name) as roster_name,
  e.excel_sales,
  d.db_sales,
  d.db_sales - e.excel_sales as sales_diff,
  e.excel_rows,
  d.db_rows,
  d.db_rows - e.excel_rows as extra_rows
from excel e
full outer join db d on public.normalize_ba_name(e.roster_name) = public.normalize_ba_name(d.roster_name)
order by abs(coalesce(d.db_sales, 0) - coalesce(e.excel_sales, 0)) desc;

-- D) Shift-level mismatches (amount or missing/extra)
with excel as (
  select
    trim(ba_name) as roster_name,
    entry_date,
    lower(trim(store)) as store_k,
    lower(trim(shift)) as shift_k,
    sales_amount,
    items_sold
  from public.sales_entries_may_reload_staging
  where entry_date between '2026-05-01' and '2026-05-15'
),
db as (
  select
    public.entry_roster_name(e.ba_name, p.name) as roster_name,
    e.entry_date,
    lower(trim(coalesce(e.store, ''))) as store_k,
    lower(trim(coalesce(e.shift, ''))) as shift_k,
    e.sales_amount,
    e.items_sold,
    e.id
  from public.sales_entries e
  left join public.profiles p on p.id = e.ba_id
  where e.entry_date between '2026-05-01' and '2026-05-15'
)
select
  coalesce(e.roster_name, d.roster_name) as roster_name,
  coalesce(e.entry_date, d.entry_date) as entry_date,
  coalesce(e.store_k, d.store_k) as store,
  coalesce(e.shift_k, d.shift_k) as shift,
  e.sales_amount as excel_sales,
  d.sales_amount as db_sales,
  case
    when e.roster_name is null then 'extra_in_db'
    when d.roster_name is null then 'missing_in_db'
    when e.sales_amount is distinct from d.sales_amount then 'amount_mismatch'
    else 'ok'
  end as status
from excel e
full outer join db d on
  public.normalize_ba_name(e.roster_name) = public.normalize_ba_name(d.roster_name)
  and e.entry_date = d.entry_date
  and e.store_k = d.store_k
  and e.shift_k = d.shift_k
where e.roster_name is null
   or d.roster_name is null
   or e.sales_amount is distinct from d.sales_amount
order by roster_name, entry_date;


-- =============================================================================
-- FIX May 1–15 only (wipes those dates, reloads from staging, keeps May 16+)
-- Uncomment and run ONLY after RECONCILE shows drift.
-- =============================================================================

/*
-- 1) Remove all May 1–15 sales + attendance (May 16+ untouched)
delete from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-15';

delete from public.ba_attendance_entries
where entry_date between '2026-05-01' and '2026-05-15';

-- 2) Reload from staging (exact Excel copy)
insert into public.sales_entries (
  ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date
)
select
  trim(s.ba_name),
  trim(s.team),
  trim(s.store),
  trim(s.shift),
  s.sales_amount,
  s.items_sold,
  greatest(1, coalesce(s.working_days, 1))::integer,
  s.entry_date::date
from public.sales_entries_may_reload_staging s
where s.entry_date between '2026-05-01' and '2026-05-15';

insert into public.ba_attendance_entries (
  ba_name, team, store, entry_date, status, notes
)
select
  trim(a.ba_name),
  trim(a.team),
  nullif(trim(a.store), ''),
  a.entry_date::date,
  trim(a.status),
  nullif(a.notes, '')
from public.ba_attendance_may_reload_staging a
where a.entry_date between '2026-05-01' and '2026-05-15';

-- 3) Link to registered BAs (roster name → profile)
do $$
declare
  r record;
  m record;
  res json;
begin
  for m in
    select * from (values
      ('Mohamed Ahmed',   'Mohamed'),
      ('Mamdouh Mohamed', 'Mamdouh'),
      ('Nada Saad',       'Nada'),
      ('Emaan Salah',     'Eman1'),
      ('veronia',         'Veronia'),
      ('Samah Mohamed',   'Samah'),
      ('ahmed abdelaal',  'Ahmed'),
      ('Esraa Abdullah',  'Esraa'),
      ('Mohamed Atef',    'Atef'),
      ('Nouran adel',     'Nouran')
    ) as t(registered_name, roster_name)
  loop
    for r in
      select id, name from public.profiles
      where role = 'ba'
        and public.normalize_ba_name(name) = public.normalize_ba_name(m.registered_name)
    loop
      res := public.link_legacy_rows_for_profile(r.id, r.name, m.roster_name);
      raise notice 'Linked %: %', r.name, res;
    end loop;
  end loop;
end $$;

-- 4) Dedupe May 1–15 (same BA + date + shop + shift)
with sales_ranked as (
  select id,
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
  where entry_date between '2026-05-01' and '2026-05-15'
)
delete from public.sales_entries s using sales_ranked r
where s.id = r.id and r.rn > 1;

-- 5) ba_name on linked rows = profile display name
update public.sales_entries s
set ba_name = p.name
from public.profiles p
where s.ba_id = p.id
  and s.entry_date between '2026-05-01' and '2026-05-15'
  and trim(s.ba_name) is distinct from trim(p.name);
*/

-- =============================================================================
-- AFTER FIX — re-run reconcile query C; sales_diff and extra_rows should be 0
-- May 16+ rows (app) still present:
-- =============================================================================
select
  case when ba_id is null then 'excel' else 'app' end as source,
  count(*) as rows,
  min(entry_date) as from_d,
  max(entry_date) as to_d
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
group by 1
order by 1;
