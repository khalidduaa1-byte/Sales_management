-- =============================================================================
-- Restore Nadine's Excel history after old auth account was deleted
--
-- Deleting the old user removed her profile → CASCADE deleted all sales rows
-- that were linked to that profile (May 1–15 imports).
-- May 16+ on icloud account (cde0634d-...) should still be there.
--
-- This re-inserts May Excel rows from the original import (matches Excel).
-- UID: cde0634d-9e92-48f2-aa68-e562925c6f22 — Nadine Taimour
-- =============================================================================

-- BEFORE: what does she have now?
select
  count(*) filter (where entry_date >= '2026-05-01' and entry_date < '2026-05-16') as may_1_15,
  count(*) filter (where entry_date >= '2026-05-16' and entry_date < '2026-06-01') as may_16_plus,
  coalesce(sum(sales_amount) filter (
    where entry_date >= '2026-05-01' and entry_date < '2026-06-01'
  ), 0) as may_total
from public.sales_entries
where ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid;

insert into public.profiles (id, name, role, team, store)
values (
  'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
  'Nadine Taimour',
  'ba',
  'Cairo',
  null
)
on conflict (id) do update set
  name = excluded.name,
  role = 'ba',
  team = excluded.team;

-- May sales (Excel 1–15) — skip if that day already exists on her account
insert into public.sales_entries (
  ba_id, ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date
)
select
  'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
  'Nadine Taimour',
  v.team,
  v.store,
  v.shift,
  v.sales_amount,
  v.items_sold,
  v.working_days,
  v.entry_date::date
from (values
  ('Cairo', 'Cairo', 'Morning', 151.0, 3, 1, '2026-05-01'),
  ('Cairo', 'Cairo', 'Morning', 300.0, 3, 1, '2026-05-02'),
  ('Cairo', 'Cairo', 'Morning', 125.0, 1, 1, '2026-05-04'),
  ('Cairo', 'Cairo', 'Morning', 664.0, 7, 1, '2026-05-05'),
  ('Cairo', 'Cairo', 'Morning', 165.0, 3, 1, '2026-05-06'),
  ('Cairo', 'Cairo', 'Morning', 231.0, 2, 1, '2026-05-07'),
  ('Cairo', 'Cairo', 'Morning', 157.0, 2, 1, '2026-05-08'),
  ('Cairo', 'Cairo', 'Morning', 187.0, 2, 1, '2026-05-09'),
  ('Cairo', 'Cairo', 'Morning', 493.0, 3, 1, '2026-05-11'),
  ('Cairo', 'Cairo', 'Morning', 137.0, 3, 1, '2026-05-12'),
  ('Cairo', 'Cairo', 'Morning', 151.0, 2, 1, '2026-05-13'),
  ('Cairo', 'Cairo', 'Morning', 622.0, 3, 1, '2026-05-14')
) as v(team, store, shift, sales_amount, items_sold, working_days, entry_date)
where not exists (
  select 1 from public.sales_entries s
  where s.ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
    and s.entry_date = v.entry_date::date
    and coalesce(s.store, '') = v.store
    and coalesce(s.shift, '') = v.shift
);

-- May off days (Excel attendance)
insert into public.ba_attendance_entries (
  ba_id, ba_name, team, store, entry_date, status, notes
)
select
  'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
  'Nadine Taimour',
  v.team,
  v.store,
  v.entry_date::date,
  v.status,
  v.notes
from (values
  ('Cairo', 'Cairo', '2026-05-03', 'off_day', 'Off day'),
  ('Cairo', 'Cairo', '2026-05-10', 'off_day', 'Off day')
) as v(team, store, entry_date, status, notes)
where not exists (
  select 1 from public.ba_attendance_entries a
  where a.ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
    and a.entry_date = v.entry_date::date
);

-- AFTER
select
  count(*) filter (where entry_date >= '2026-05-01' and entry_date < '2026-05-16') as may_1_15_rows,
  count(*) filter (where entry_date >= '2026-05-16' and entry_date < '2026-06-01') as may_16_plus_rows,
  coalesce(sum(sales_amount) filter (
    where entry_date >= '2026-05-01' and entry_date < '2026-06-01'
  ), 0) as may_total
from public.sales_entries
where ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid;

-- Expect may_1_15_rows = 12, may_total ≈ 3383 for May 1-14 sales + her May 16+ app days
