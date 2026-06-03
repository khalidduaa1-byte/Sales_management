-- add_besher_may19_ahmed_off_may29.sql
-- ================================================================
-- WHAT / WHY (two small missing-data fixes from BA reports)
--   1. Besher Nasr worked 19 May 2026 but the sale wasn't logged:
--        19/5  "shop102"  1 x The One 150ml = 143 EGP, 1 item.
--      "shop102" mapped to Hurghada russian shop (his usual granular shop);
--      shift defaulted to Morning. Adjust if it was the European shop/other shift.
--   2. Ahmed abdelaal was OFF on 29 May 2026 — no sale, no leave recorded, so the
--      Missing Sales tracker flags it. Add an off_day attendance record.
--
-- Idempotent (NOT EXISTS guards). Non-destructive. Run in the Supabase SQL Editor.
-- ================================================================

-- 1. Besher's 19 May sale
insert into public.sales_entries (ba_id, ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)
select 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2', 'Besher Nasr', 'Hurgadah', 'Hurghada russian shop', 'Morning', 143, 1, 1, date '2026-05-19'
where not exists (
  select 1 from public.sales_entries s
  where s.ba_id='cc619b38-1ed0-4b3c-b774-23a4087cc9a2' and s.entry_date=date '2026-05-19'
);

-- 2. Ahmed's 29 May off day
insert into public.ba_attendance_entries (ba_id, ba_name, team, store, entry_date, status)
select '04005d6e-eb8f-4b96-9949-88a89b8e5e6e', 'ahmed abdelaal', 'Cairo', null, date '2026-05-29', 'off_day'
where not exists (
  select 1 from public.ba_attendance_entries a
  where a.ba_id='04005d6e-eb8f-4b96-9949-88a89b8e5e6e' and a.entry_date=date '2026-05-29'
);

-- Verify:
select 'besher 19/5' as item, store, shift, sales_amount::text as val
from public.sales_entries where ba_id='cc619b38-1ed0-4b3c-b774-23a4087cc9a2' and entry_date=date '2026-05-19'
union all
select 'ahmed 29/5', status, '', ''
from public.ba_attendance_entries where ba_id='04005d6e-eb8f-4b96-9949-88a89b8e5e6e' and entry_date=date '2026-05-29';
