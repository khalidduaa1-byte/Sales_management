-- rename_june_animation_to_702a.sql
--
-- The June pilot ran at shop 702A but was logged under the interim "HPP" label.
-- Rename BOTH the calendar event AND the already-logged June sales to the standard
-- 702A label, so names follow one format and the dashboard attributes the June
-- sales to the June event.
--
-- The store still keeps its "(animation)" tag (that's how the dashboard detects
-- animation entries) — only "HPP" becomes "702A".

-- ── Before ───────────────────────────────────────────────────────
select store, count(*) as rows, sum(sales_amount) as sales
from sales_entries
where store = 'Terminal 3 — HPP (animation)'
group by store;

-- ── 1) Rename the calendar event ─────────────────────────────────
update animation_events
   set name = 'Terminal 3 — 702A (animation)'
 where name = 'Terminal 3 — HPP (animation)';

-- ── 2) Rename the logged June sales to match ─────────────────────
-- (Safe: no 702A-labelled rows exist for those June days, so no unique clash.)
update sales_entries
   set store = 'Terminal 3 — 702A (animation)'
 where store = 'Terminal 3 — HPP (animation)';

-- ── After (rows + sales should equal the "before" totals) ────────
select store, count(*) as rows, sum(sales_amount) as sales
from sales_entries
where store = 'Terminal 3 — 702A (animation)'
group by store;
