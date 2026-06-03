-- add_nadine_zero_sales_may30_31.sql
-- ================================================================
-- WHAT / WHY
-- Nadine worked 30 & 31 May 2026 but made zero sales ("nil"). She never logged
-- them, so her last entry is 29 May and the Missing Sales tracker correctly
-- flags 30 & 31 as missing. This records two 0-sales rows so those days show as
-- "logged (no sale)" instead of missing. Store/shift mirror her recent days
-- (Terminal 3 Cairo, Morning) — adjust if she was elsewhere.
--
-- Idempotent: inserts only if the row doesn't already exist. Non-destructive.
-- Run in the Supabase SQL Editor.
-- ================================================================

insert into public.sales_entries (ba_id, ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)
select 'cde0634d-9e92-48f2-aa68-e562925c6f22', 'Nadine Taimour', 'Cairo', 'Terminal 3 Cairo', 'Morning', 0, 0, 1, d::date
from (values ('2026-05-30'), ('2026-05-31')) as v(d)
where not exists (
  select 1 from public.sales_entries s
  where s.ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'
    and s.entry_date = v.d::date
);

-- Verify (should show 30 & 31 May at 0):
select entry_date, store, shift, sales_amount
from public.sales_entries
where ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'
  and entry_date between date '2026-05-30' and date '2026-05-31'
order by entry_date;
