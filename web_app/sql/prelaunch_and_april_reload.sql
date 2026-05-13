-- =============================================================================
-- Pre-launch + April 2026 reload (trusted Excel → Supabase)
-- Run sections in Supabase SQL Editor in order. Adjust nothing unless noted.
-- =============================================================================
--
-- BEFORE ANYTHING: if policies were never applied on this project, run the
-- full repo file once (copy/paste entire file):
--   web_app/setup.sql
--
-- =============================================================================
-- 1) VERIFY row level security is ON (should show rowsecurity = true)
-- =============================================================================
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in (
    'sales_entries',
    'profiles',
    'monthly_targets',
    'ba_attendance_entries'
  )
order by tablename;

-- =============================================================================
-- 2) STAGING TABLES (hold CSV rows from Table Editor → Import)
-- =============================================================================
-- After this runs: Supabase → Table Editor → Import CSV into each staging table.
-- Sales file (repo):    web_app/normalized_april_reload_sales.csv
-- Attendance file:    web_app/normalized_april_reload_attendance.csv
-- Map columns by name; leave id / ba_id / created_at unset (defaults / null).

create table if not exists public.sales_entries_april_reload_staging (
  ba_name       text not null,
  team          text not null,
  store         text not null,
  shift         text not null,
  sales_amount  numeric(10,2) not null,
  items_sold    integer not null,
  working_days  integer not null default 1,
  entry_date    date not null
);

create table if not exists public.ba_attendance_april_reload_staging (
  ba_name    text not null,
  team       text not null,
  store      text,
  entry_date date not null,
  status     text not null,
  notes      text
);

-- =============================================================================
-- 3) TRUNCATE staging (use before each CSV import if re-trying)
-- =============================================================================
truncate table public.sales_entries_april_reload_staging;
truncate table public.ba_attendance_april_reload_staging;

-- =============================================================================
-- 4) REMOVE April IMPORT rows only (keeps BA app rows where ba_id is set)
-- =============================================================================
delete from public.sales_entries
where entry_date between '2026-04-01' and '2026-04-30'
  and ba_id is null;

delete from public.ba_attendance_entries
where entry_date between '2026-04-01' and '2026-04-30'
  and ba_id is null;

-- =============================================================================
-- 5) PAUSE — Import both CSVs into the two staging tables (Table Editor UI)
-- =============================================================================

-- =============================================================================
-- 6) MERGE staging → production (legacy rows: ba_id stays null)
-- =============================================================================
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
from public.sales_entries_april_reload_staging s
on conflict ((lower(ba_name)), entry_date, store, shift)
  where (ba_id is null)
  do nothing;
-- If Postgres errors on inference, use NOT EXISTS instead of ON CONFLICT:
-- insert ... select ... from staging s where not exists (
--   select 1 from public.sales_entries e
--   where e.ba_id is null and lower(trim(e.ba_name)) = lower(trim(s.ba_name))
--     and e.entry_date = s.entry_date::date and trim(e.store) = trim(s.store) and trim(e.shift) = trim(s.shift));

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
from public.ba_attendance_april_reload_staging a
where not exists (
  select 1
  from public.ba_attendance_entries e
  where e.entry_date = a.entry_date::date
    and e.ba_id is null
    and lower(trim(e.ba_name)) = lower(trim(a.ba_name))
    and coalesce(trim(e.store), '') = coalesce(trim(a.store), '')
    and trim(e.status) = trim(a.status)
);

-- =============================================================================
-- 7) OPTIONAL cleanup — drop staging when you are done (or truncate only)
-- =============================================================================
-- drop table if exists public.sales_entries_april_reload_staging;
-- drop table if exists public.ba_attendance_april_reload_staging;

-- =============================================================================
-- 8) QUICK sanity checks
-- =============================================================================
select count(*) as sales_april_rows
from public.sales_entries
where entry_date between '2026-04-01' and '2026-04-30';

select count(*) as attendance_april_rows
from public.ba_attendance_entries
where entry_date between '2026-04-01' and '2026-04-30';

select ba_name, sales_amount, items_sold, entry_date, store, shift
from public.sales_entries
where entry_date = '2026-04-27'
  and lower(trim(ba_name)) = 'nouran';
