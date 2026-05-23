-- =============================================================================
-- Manager fix: remove wrong leave days for Esraa (edit UUID / dates as needed)
-- Run in Supabase SQL Editor after add_ba_delete_attendance_policy.sql
-- =============================================================================

-- Find Esraa attendance in May (adjust month if needed)
select a.id, a.entry_date, a.status, a.notes, p.name, u.email
from public.ba_attendance_entries a
left join public.profiles p on p.id = a.ba_id
left join auth.users u on u.id = a.ba_id
where public.normalize_ba_name(coalesce(p.name, a.ba_name)) like '%esraa%'
  and a.entry_date >= '2026-05-01' and a.entry_date < '2026-06-01'
order by a.entry_date;

-- Delete specific wrong days (paste ids from query above, or by date range)
-- delete from public.ba_attendance_entries
-- where ba_id = 'PASTE-ESRAA-USER-UUID'::uuid
--   and entry_date in ('2026-05-XX', '2026-05-YY');
