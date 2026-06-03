-- add_eman1_leave_may26_31.sql
-- ================================================================
-- WHAT / WHY
-- Eman1 (Cairo) was on leave 26–31 May 2026. No sale or leave was recorded for
-- any of those 6 days, so the Missing Sales tracker flags them all. Add leave
-- records. Status assumed 'annual_leave' ("on leave") — change to off_day /
-- sick_leave / other if different.
--
-- Idempotent (NOT EXISTS guard, one row per date). Non-destructive.
-- Run in the Supabase SQL Editor.
-- ================================================================

insert into public.ba_attendance_entries (ba_id, ba_name, team, store, entry_date, status)
select '6b3bc2ab-7b0e-40f8-9917-b2f84a398b72', 'Eman1', 'Cairo', null, d::date, 'annual_leave'
from (values ('2026-05-26'),('2026-05-27'),('2026-05-28'),('2026-05-29'),('2026-05-30'),('2026-05-31')) as v(d)
where not exists (
  select 1 from public.ba_attendance_entries a
  where a.ba_id='6b3bc2ab-7b0e-40f8-9917-b2f84a398b72' and a.entry_date=v.d::date
);

-- Verify (should show 6 annual_leave days):
select entry_date, status
from public.ba_attendance_entries
where ba_id='6b3bc2ab-7b0e-40f8-9917-b2f84a398b72' and entry_date between date '2026-05-26' and date '2026-05-31'
order by entry_date;
