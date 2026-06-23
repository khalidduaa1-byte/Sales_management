-- reallocate_sharm_animation_jun20_21.sql
--
-- PROBLEM
--   Sharm BAs logged combined sales on 20 & 21 Jun before the separate animation
--   card existed, so their regular "Sharm Sheikh" entries ALREADY include the
--   animation portion. We must NOT add animation entries on top (that double-counts).
--
-- FIX (reallocation, not addition)
--   For each BA/day, MOVE the animation portion out of the regular entry into a
--   "Sharm Sheikh — A (animation)" entry. The day's total is unchanged — it's just
--   relabeled. Run the steps in order; STEP 2 must show all "ok" before STEP 3.
--
-- NOTE ON DATES
--   The Sharm animation runs 21–30 Jun. So 20 Jun sales are purely regular shop
--   sales — do NOT split those. Only reallocate 21 Jun (and any later days the BAs
--   logged combined before the animation card was live).


-- ── STEP 0: see what's currently logged (diagnostic, no changes) ──
select p.name as ba, s.entry_date, s.shift, s.store, s.sales_amount, s.items_sold
from sales_entries s
join profiles p on p.id = s.ba_id
where s.team = 'Sharm' and s.entry_date in ('2026-06-20', '2026-06-21')
order by p.name, s.entry_date, s.shift;


-- ── STEP 1: fill in the ANIMATION portion per BA / day / shift ────
-- One row per BA per affected (date, shift). amount + PCs = the animation part only.
-- (Use the exact registered name as shown in STEP 0.)
create temp table _anim_adj (
  ba_name      text,
  entry_date   date,
  shift        text,
  anim_amount  numeric(12,2),
  anim_pcs     integer
);

insert into _anim_adj (ba_name, entry_date, shift, anim_amount, anim_pcs) values
  -- EDIT THESE — examples, replace with the real split:
  ('REPLACE WITH BA NAME', '2026-06-21', 'Morning', 0.00, 0)
  -- , ('Another BA',       '2026-06-20', 'Evening', 500.00, 4)
;


-- ── STEP 2: validation — every row MUST say 'ok' before STEP 3 ────
select a.ba_name, a.entry_date, a.shift, a.anim_amount, a.anim_pcs,
  case
    when p.id is null                     then '❌ BA name not found in Sharm'
    when s.id is null                     then '❌ no regular "Sharm Sheikh" entry for that date/shift'
    when s.sales_amount < a.anim_amount   then '❌ animation amount > logged amount'
    when s.items_sold   < a.anim_pcs      then '❌ animation PCs > logged PCs'
    else '✅ ok'
  end as check,
  s.sales_amount as logged_amount, s.items_sold as logged_pcs
from _anim_adj a
left join profiles p
  on lower(trim(p.name)) = lower(trim(a.ba_name)) and p.team = 'Sharm'
left join sales_entries s
  on s.ba_id = p.id and s.entry_date = a.entry_date and s.shift = a.shift and s.store = 'Sharm Sheikh';


-- ── STEP 3: do the move (run only after STEP 2 is all ✅) ─────────
-- 3a. Subtract the animation portion from the regular Sharm entry.
update sales_entries s
set sales_amount = s.sales_amount - a.anim_amount,
    items_sold   = s.items_sold   - a.anim_pcs
from _anim_adj a
join profiles p on lower(trim(p.name)) = lower(trim(a.ba_name)) and p.team = 'Sharm'
where s.ba_id = p.id and s.entry_date = a.entry_date and s.shift = a.shift
  and s.store = 'Sharm Sheikh';

-- 3b. Create (or top up) the animation entry with that same portion.
insert into sales_entries (ba_id, ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)
select p.id, p.name, 'Sharm', 'Sharm Sheikh — A (animation)', a.shift, a.anim_amount, a.anim_pcs, 1, a.entry_date
from _anim_adj a
join profiles p on lower(trim(p.name)) = lower(trim(a.ba_name)) and p.team = 'Sharm'
on conflict (ba_id, entry_date, store, shift)
  do update set sales_amount = excluded.sales_amount, items_sold = excluded.items_sold;


-- ── STEP 3 check: day totals must be UNCHANGED vs STEP 0 ──────────
-- Regular + animation combined, per BA per day — compare to STEP 0's amounts.
select p.name as ba, s.entry_date,
       sum(s.sales_amount) as total_amount_after,
       sum(s.items_sold)   as total_pcs_after
from sales_entries s
join profiles p on p.id = s.ba_id
where s.team = 'Sharm' and s.entry_date in ('2026-06-20', '2026-06-21')
group by p.name, s.entry_date
order by p.name, s.entry_date;

drop table _anim_adj;
