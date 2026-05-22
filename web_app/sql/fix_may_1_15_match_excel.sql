-- =============================================================================
-- FIX: May 1–15 sales must match normalized_may_reload_sales.csv (Excel)
--
-- WHY TOTALS ARE TOO HIGH
-- May was merged/imported more than once. Same shift exists twice under
-- "Mamdouh" AND "Mamdouh Mohamed" (or import ran when names did not match).
--
-- WHAT THIS DOES
-- • Deletes ALL sales + attendance for 2026-05-01 … 2026-05-15 only
-- • Re-inserts exactly from staging (your CSV copy)
-- • Re-links rows to registered BAs (ba_id) — does not change Excel amounts
-- • Dedupes same BA + date + shop + shift
-- • Leaves May 16+ untouched (app entries after Excel period)
--
-- RUN IN SUPABASE SQL EDITOR — IN ORDER. Do not skip staging import.
-- =============================================================================


-- ── STEP 0: Staging tables + fresh CSV (PAUSE after truncate) ───────────────
create table if not exists public.sales_entries_may_reload_staging (
  ba_name       text not null,
  team          text not null,
  store         text not null,
  shift         text not null,
  sales_amount  numeric(10,2) not null,
  items_sold    integer not null,
  working_days  integer not null default 1,
  entry_date    date not null
);

create table if not exists public.ba_attendance_may_reload_staging (
  ba_name    text not null,
  team       text not null,
  store      text,
  entry_date date not null,
  status     text not null,
  notes      text
);

-- Staging is EMPTY after you merged into production — that is normal.
-- Reload the Excel copy into staging (source of truth for the fix):
--   → Run entire file: web_app/sql/may_staging_seed_from_csv.sql
--   OR import both CSVs in Table Editor (see may_reload.sql).
--
-- Then confirm 209 rows:
select count(*) as staging_sales_rows
from public.sales_entries_may_reload_staging
where entry_date between '2026-05-01' and '2026-05-15';
-- Expected: 209 (if 0, run may_staging_seed_from_csv.sql first)


-- ── STEP 1: Required functions (run whole file may_fix_functions.sql first) ───
-- Or paste/run: web_app/sql/may_fix_functions.sql
-- Then re-run STEP 2+ below.


-- ── STEP 2: BEFORE — see inflation (sales_diff should NOT be 0 today) ───────
with excel as (
  select trim(ba_name) as roster_name,
    sum(sales_amount)::numeric(12,2) as excel_sales,
    count(*) as excel_rows
  from public.sales_entries_may_reload_staging
  where entry_date between '2026-05-01' and '2026-05-15'
  group by trim(ba_name)
),
db as (
  select public.entry_roster_name(e.ba_name, p.name) as roster_name,
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
full outer join db d
  on public.normalize_ba_name(e.roster_name) = public.normalize_ba_name(d.roster_name)
order by abs(coalesce(d.db_sales, 0) - coalesce(e.excel_sales, 0)) desc;


-- ── STEP 3: APPLY FIX (May 1–15 only) ───────────────────────────────────────
delete from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-15';

delete from public.ba_attendance_entries
where entry_date between '2026-05-01' and '2026-05-15';

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


-- ── STEP 4: AFTER — every sales_diff and extra_rows must be 0 ───────────────
-- (Re-run the same query as STEP 2)

with excel as (
  select trim(ba_name) as roster_name,
    sum(sales_amount)::numeric(12,2) as excel_sales,
    count(*) as excel_rows
  from public.sales_entries_may_reload_staging
  where entry_date between '2026-05-01' and '2026-05-15'
  group by trim(ba_name)
),
db as (
  select public.entry_roster_name(e.ba_name, p.name) as roster_name,
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
full outer join db d
  on public.normalize_ba_name(e.roster_name) = public.normalize_ba_name(d.roster_name)
order by roster_name;

-- Expected Excel totals May 1–15 (from CSV):
-- Mamdouh 6752 (9 rows) | Samah 9100 (15) | Mohamed 8172 (15) | Nada 4709 (13)
-- Total all BAs: 86062 across 209 rows
