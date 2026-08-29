-- add_profiles_end_date.sql
-- ================================================================
-- WHAT / WHY
-- profiles had start_date (first active day) but no notion of a BA *leaving*.
-- So a BA who resigned stayed on the dashboard forever: the Missing Sales
-- calendar showed them as "all days missing" (a full row of ✗) every month
-- after they left, and they kept counting as an active head, inflating the
-- per_ba team target for Cairo/Sharm.
--
-- This adds profiles.end_date = the BA's LAST ACTIVE DAY. NULL = still with
-- the company. The manager dashboard then:
--   * hides them from the Missing Sales calendar in months after they left,
--     and greys out the days after their last day in the month they left;
--   * stops counting them in team headcount (so per_ba targets shrink to the
--     BAs who are actually there);
--   * labels them "(left)" in the BA pickers.
--
-- IMPORTANT — their sales are NOT deleted. Those are real revenue booked in
-- the months they worked; removing them would silently change every past
-- month's team total and attainment. They stay exactly as they are, and
-- picking a past month still shows them.
--
-- Idempotent and non-destructive. Run in the Supabase SQL Editor.
-- ================================================================

-- 1. Column
alter table public.profiles add column if not exists end_date date;


-- 2. PREVIEW FIRST — do not skip this. Run step 2 on its own and read the
--    output before running step 3. It shows exactly which profiles match the
--    names below and what end_date they would get.
--
--    Confirm: one row per person, the right team, and last_activity looks like
--    a plausible final working day. If a name matches nobody (or matches two
--    people), fix the name list in step 3 before running it.
with departed(match_name) as (
  values
    ('Eman1'),
    ('Nouran Adel'),
    ('Rehab')
)
select
  p.id,
  p.name,
  p.team,
  p.start_date,
  p.end_date as current_end_date,
  greatest(
    coalesce((select max(entry_date) from public.sales_entries s where s.ba_id = p.id), '1900-01-01'),
    coalesce((select max(entry_date) from public.ba_attendance_entries a where a.ba_id = p.id), '1900-01-01')
  ) as last_activity,
  (select count(*) from public.sales_entries s where s.ba_id = p.id) as sales_rows_kept
from public.profiles p
join departed d
  on public.normalize_ba_name(p.name) = public.normalize_ba_name(d.match_name)
where p.role = 'ba'
order by p.team, p.name;


-- 3. Mark them as departed.
--    override_end: put the real last working day here if you know it (e.g.
--    '2026-07-31'::date). Leave NULL to use their last recorded activity —
--    the last day they logged a sale or a leave day, which for someone who
--    has already left is their last working day in the system.
--
--    To mark someone departed later, add a row here and re-run this step; to
--    un-mark someone (they came back), set end_date = null for them.
with departed(match_name, override_end) as (
  values
    ('Eman1',       null::date),
    ('Nouran Adel', null::date),
    ('Rehab',       null::date)
),
resolved as (
  select
    p.id,
    coalesce(
      d.override_end,
      (select max(entry_date) from public.sales_entries s where s.ba_id = p.id),
      (select max(entry_date) from public.ba_attendance_entries a where a.ba_id = p.id),
      p.start_date
    ) as end_date
  from public.profiles p
  join departed d
    on public.normalize_ba_name(p.name) = public.normalize_ba_name(d.match_name)
  where p.role = 'ba'
)
update public.profiles p
set end_date = r.end_date
from resolved r
where p.id = r.id
  and r.end_date is not null;


-- 4. Verify. Departed BAs should show an end_date; everyone still working
--    should show NULL. Count the actives per team and check it matches the
--    headcount you expect the per_ba targets to be based on.
select
  name,
  team,
  start_date,
  end_date,
  case when end_date is null then 'active' else 'left' end as status
from public.profiles
where role = 'ba'
order by end_date nulls first, team, name;

select team, count(*) as active_bas
from public.profiles
where role = 'ba' and end_date is null
group by team
order by team;

-- 5. Sanity check that nothing was deleted — these counts must be unchanged
--    from before the run. Departed BAs keep every row.
select count(*) as total_sales_rows from public.sales_entries;
select count(*) as total_attendance_rows from public.ba_attendance_entries;
