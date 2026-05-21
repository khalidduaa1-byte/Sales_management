-- =============================================================================
-- May 2026 reload (from: sales 2026 3.xlsx → sheet "may" only)
-- Run sections in Supabase SQL Editor in order.
-- =============================================================================
--
-- CSV files (import via Table Editor):
--   web_app/normalized_may_reload_sales.csv
--   web_app/normalized_may_reload_attendance.csv
--
-- =============================================================================
-- 1) STAGING TABLES
-- =============================================================================
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

-- =============================================================================
-- 2) TRUNCATE staging (re-run imports)
-- =============================================================================
truncate table public.sales_entries_may_reload_staging;
truncate table public.ba_attendance_may_reload_staging;

-- =============================================================================
-- 3) PRE-FLIGHT — see what is already in May (run before merge; deletes nothing)
-- =============================================================================
-- Rows BAs logged in the app (NEVER deleted by this script):
select count(*) as may_sales_from_ba_app
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
  and ba_id is not null;

select ba_name, entry_date, store, shift, sales_amount
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
  and ba_id is not null
order by entry_date, ba_name;

-- Old Excel import rows only (optional to replace later — not removed automatically):
select count(*) as may_sales_import_only
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
  and ba_id is null;

-- =============================================================================
-- 4) PAUSE — Import both CSVs into staging tables (Table Editor → Import)
-- =============================================================================

-- =============================================================================
-- 5) MERGE staging → production (ADD ONLY — safe with BAs using the app)
-- =============================================================================
-- Rules:
--   • Never touches rows where ba_id is set (BA app submissions).
--   • Skips a staging row if that BA already has a sale for same date + shop + shift.
--   • Skips attendance if that BA already has any May attendance row that day.
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
where not exists (
  select 1
  from public.sales_entries e
  left join public.profiles p on p.id = e.ba_id
  where e.entry_date = s.entry_date::date
    and lower(trim(coalesce(e.store, ''))) = lower(trim(s.store))
    and lower(trim(coalesce(e.shift, ''))) = lower(trim(s.shift))
    and lower(regexp_replace(trim(coalesce(p.name, e.ba_name)), '\s+', ' ', 'g'))
        = lower(regexp_replace(trim(s.ba_name), '\s+', ' ', 'g'))
)
on conflict ((lower(ba_name)), entry_date, store, shift)
  where (ba_id is null)
  do nothing;

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
where not exists (
  select 1
  from public.ba_attendance_entries e
  left join public.profiles p on p.id = e.ba_id
  where e.entry_date = a.entry_date::date
    and lower(regexp_replace(trim(coalesce(p.name, e.ba_name)), '\s+', ' ', 'g'))
        = lower(regexp_replace(trim(a.ba_name), '\s+', ' ', 'g'))
);

-- =============================================================================
-- 6) Sanity checks
-- =============================================================================
select count(*) as sales_may_rows
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31';

select count(*) as attendance_may_rows
from public.ba_attendance_entries
where entry_date between '2026-05-01' and '2026-05-31';

select team, count(*) as rows, min(entry_date) as from_d, max(entry_date) as to_d
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
group by team
order by team;

-- Row count per name (multiple rows per day if several shifts logged)
select ba_name, count(*) as shift_rows, count(distinct entry_date) as distinct_days
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
group by ba_name
order by ba_name;

-- Import (Excel) vs app — duplicate-looking names are usually here
select
  ba_name,
  case when ba_id is null then 'excel_import' else 'ba_app' end as source,
  count(*) as shift_rows,
  count(distinct entry_date) as distinct_days
from public.sales_entries
where entry_date between '2026-05-01' and '2026-05-31'
group by ba_name, case when ba_id is null then 'excel_import' else 'ba_app' end
order by ba_name, source;

-- =============================================================================
-- OPTIONAL (only if you must wipe old Excel May imports — NOT for normal use)
-- =============================================================================
-- This does NOT delete BA app rows (ba_id is not null). Uncomment only if needed:
--
-- delete from public.sales_entries
-- where entry_date between '2026-05-01' and '2026-05-31' and ba_id is null;
--
-- delete from public.ba_attendance_entries
-- where entry_date between '2026-05-01' and '2026-05-31' and ba_id is null;
