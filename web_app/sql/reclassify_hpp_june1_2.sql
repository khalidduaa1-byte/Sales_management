-- reclassify_hpp_june1_2.sql
-- ================================================================
-- WHAT / WHY
-- The HPP animation spot (inside Terminal 3, Cairo) ran from 1 June 2026, but
-- the separate "Terminal 3 — HPP (animation)" shop option wasn't live in the BA
-- app yet, so Cairo BAs logged their podium sales under "Terminal 3 Cairo".
-- These 4 rows were confirmed against the BAs' WhatsApp reports (exact amount +
-- item count match) to be podium/HPP sales, not regular Terminal 3.
--
-- This moves only those 4 rows to the HPP store value so HPP is tracked
-- separately. Amounts/items/dates are unchanged. Reversible. Non-destructive.
-- Run in the Supabase SQL Editor.
-- ================================================================

-- BEFORE: confirm exactly these 4 rows (should return 4)
select p.name, s.entry_date, s.shift, s.store, s.sales_amount, s.items_sold
from public.sales_entries s join public.profiles p on p.id = s.ba_id
where s.store = 'Terminal 3 Cairo'
  and (
       (s.ba_id = 'dab26185-e934-4aba-9975-b1c32f05cd64' and s.entry_date = '2026-06-01' and s.shift = 'Morning'   and s.sales_amount = 486)  -- Mary 1/6
    or (s.ba_id = 'e4c01ac2-907a-4d44-ba2e-df852bbc13fa' and s.entry_date = '2026-06-01' and s.shift = 'Morning'   and s.sales_amount = 491)  -- Eman2 1/6
    or (s.ba_id = 'e4c01ac2-907a-4d44-ba2e-df852bbc13fa' and s.entry_date = '2026-06-02' and s.shift = 'Morning'   and s.sales_amount = 460)  -- Eman2 2/6
    or (s.ba_id = 'c58f6589-27a3-4b7f-92a6-bf6665366b8e' and s.entry_date = '2026-06-02' and s.shift = 'Afternoon' and s.sales_amount = 1056) -- Nada 2/6
  );

-- APPLY
update public.sales_entries s
set store = 'Terminal 3 — HPP (animation)'
where s.store = 'Terminal 3 Cairo'
  and (
       (s.ba_id = 'dab26185-e934-4aba-9975-b1c32f05cd64' and s.entry_date = '2026-06-01' and s.shift = 'Morning'   and s.sales_amount = 486)
    or (s.ba_id = 'e4c01ac2-907a-4d44-ba2e-df852bbc13fa' and s.entry_date = '2026-06-01' and s.shift = 'Morning'   and s.sales_amount = 491)
    or (s.ba_id = 'e4c01ac2-907a-4d44-ba2e-df852bbc13fa' and s.entry_date = '2026-06-02' and s.shift = 'Morning'   and s.sales_amount = 460)
    or (s.ba_id = 'c58f6589-27a3-4b7f-92a6-bf6665366b8e' and s.entry_date = '2026-06-02' and s.shift = 'Afternoon' and s.sales_amount = 1056)
  );

-- AFTER: should now show 4 rows under the HPP store
select p.name, s.entry_date, s.shift, s.store, s.sales_amount
from public.sales_entries s join public.profiles p on p.id = s.ba_id
where s.store = 'Terminal 3 — HPP (animation)'
order by s.entry_date, p.name;
