-- ============================================================================
-- Add profiles.end_date and backfill it for BAs who left, from their own data.
--
-- Mirrors start_date. start_date hides a BA BEFORE they joined; end_date stops
-- counting them as "missing" AFTER they left. Historical sales are NOT touched:
-- their past entries still appear in the months they were actually working.
--
-- end_date is derived from each BA's LAST logged sales entry, so no dates are
-- guessed. Name matching mirrors normalizeBaKey() in manager.html:
-- trim -> collapse whitespace -> lowercase.
--
-- Run the sections IN ORDER. Section 1 is read-only — check its output before
-- running section 2.
-- ============================================================================


-- ── 1. INSPECT (read-only) ──────────────────────────────────────────────────
-- Confirms each name actually matches a BA profile and shows the last day they
-- logged sales. last_sales_entry is exactly what section 2 writes to end_date.
-- A NULL profile_id means the name did not match — fix the spelling before
-- running section 2, or that BA will silently be skipped.

with leavers(input_name) as (
  values ('Eman1'), ('Nouran Adel'), ('Rehab')
),
matched as (
  select l.input_name, p.id as profile_id, p.name as profile_name,
         p.team, p.start_date
  from leavers l
  left join public.profiles p
    on lower(regexp_replace(btrim(p.name), '\s+', ' ', 'g'))
     = lower(regexp_replace(btrim(l.input_name), '\s+', ' ', 'g'))
   and p.role = 'ba'
)
select
  m.input_name,
  m.profile_name,
  m.profile_id,
  m.team,
  m.start_date,
  (select max(e.entry_date) from public.sales_entries e
    where e.ba_id = m.profile_id
       or (e.ba_id is null
           and lower(regexp_replace(btrim(e.ba_name), '\s+', ' ', 'g'))
             = lower(regexp_replace(btrim(m.profile_name), '\s+', ' ', 'g')))
  ) as last_sales_entry,
  (select count(*) from public.sales_entries e
    where e.ba_id = m.profile_id
       or (e.ba_id is null
           and lower(regexp_replace(btrim(e.ba_name), '\s+', ' ', 'g'))
             = lower(regexp_replace(btrim(m.profile_name), '\s+', ' ', 'g')))
  ) as total_entries
from matched m
order by m.input_name;


-- ── 2. ADD COLUMN + BACKFILL ────────────────────────────────────────────────
-- Safe to re-run. Only touches the three named BAs, and only if they have at
-- least one sales entry to derive a date from.

alter table public.profiles
  add column if not exists end_date date;

comment on column public.profiles.end_date is
  'Last active day. The dashboard stops expecting submissions after this date. NULL = still active.';

update public.profiles p
set end_date = sub.last_sales_entry
from (
  select p2.id,
         (select max(e.entry_date) from public.sales_entries e
           where e.ba_id = p2.id
              or (e.ba_id is null
                  and lower(regexp_replace(btrim(e.ba_name), '\s+', ' ', 'g'))
                    = lower(regexp_replace(btrim(p2.name), '\s+', ' ', 'g')))
         ) as last_sales_entry
  from public.profiles p2
  where p2.role = 'ba'
    and lower(regexp_replace(btrim(p2.name), '\s+', ' ', 'g'))
        in ('eman1', 'nouran adel', 'rehab')
) sub
where p.id = sub.id
  and sub.last_sales_entry is not null;


-- ── 3. VERIFY ───────────────────────────────────────────────────────────────
-- Expect exactly the three leavers, each with an end_date in August 2026.

select id, name, team, start_date, end_date
from public.profiles
where role = 'ba' and end_date is not null
order by name;
