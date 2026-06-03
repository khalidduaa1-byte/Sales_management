-- add_atef_sale_may28.sql
-- ================================================================
-- WHAT / WHY
-- Mohamed Atef's 28 May 2026 sale was never logged (he was unable to save in the
-- app at the time; his last entry is 27 May). His 26 & 27 May entries are already
-- correct in the DB and were NOT modified. This adds only the missing 28 May day:
--   28/5  Terminal 1  — 647 EGP, 6 items (King 116 + The one 122 + The one 135
--                       + mini 61 + mini 56 + The only one 157).
-- Shift = Afternoon (matches his other Terminal 1 days). Adjust if different.
--
-- Idempotent (NOT EXISTS guard). Non-destructive. Run in the Supabase SQL Editor.
-- ================================================================

insert into public.sales_entries (ba_id, ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)
select '7b7f1204-88a9-4721-85ea-89a0c30ca6e1', 'Mohamed Atef', 'Cairo', 'Terminal 1 Cairo', 'Afternoon', 647, 6, 1, date '2026-05-28'
where not exists (
  select 1 from public.sales_entries s
  where s.ba_id='7b7f1204-88a9-4721-85ea-89a0c30ca6e1' and s.entry_date=date '2026-05-28'
);

-- Verify (should show 26, 27 unchanged + new 28):
select entry_date, store, shift, sales_amount, items_sold
from public.sales_entries
where ba_id='7b7f1204-88a9-4721-85ea-89a0c30ca6e1'
  and entry_date between date '2026-05-26' and date '2026-05-28'
order by entry_date;
