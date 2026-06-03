-- add_nouran_sales_may30_31.sql
-- ================================================================
-- WHAT / WHY
-- Nouran adel worked 30 & 31 May 2026 and made sales, but never logged them
-- (her last entry was 27 May; 28–29 were public holidays, 30–31 had no entry),
-- so the Missing Sales tracker correctly flagged 30 & 31 as missing. These are
-- her real figures from her WhatsApp report:
--   30/5  Seasonal Terminal  — 177 EGP, 2 items  (1 the one 74 + 1 k 103)
--   31/5  Terminal 1 Cairo   — 946 EGP, 12 items (the one/Dev/intenso/Dev p/dolce/limp)
-- Shift defaulted to Morning (not specified in report) — change if needed.
--
-- Idempotent: inserts only if no row exists for that BA+date. Non-destructive.
-- Run in the Supabase SQL Editor.
-- ================================================================

insert into public.sales_entries (ba_id, ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)
select v.ba_id::uuid, v.ba_name, v.team, v.store, v.shift, v.amount::numeric, v.items::int, 1, v.d::date
from (values
  ('cb4ccf31-c6fb-41a5-84d0-d21b22443526', 'Nouran adel', 'Cairo', 'Seasonal Terminal', 'Morning', 177, 2,  '2026-05-30'),
  ('cb4ccf31-c6fb-41a5-84d0-d21b22443526', 'Nouran adel', 'Cairo', 'Terminal 1 Cairo',  'Morning', 946, 12, '2026-05-31')
) as v(ba_id, ba_name, team, store, shift, amount, items, d)
where not exists (
  select 1 from public.sales_entries s
  where s.ba_id = v.ba_id::uuid and s.entry_date = v.d::date
);

-- Verify (should show 30 & 31 May with the amounts above):
select entry_date, store, shift, sales_amount, items_sold
from public.sales_entries
where ba_id = 'cb4ccf31-c6fb-41a5-84d0-d21b22443526'
  and entry_date between date '2026-05-30' and date '2026-05-31'
order by entry_date;
