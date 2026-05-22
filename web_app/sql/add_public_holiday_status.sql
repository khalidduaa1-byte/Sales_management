-- BA attendance statuses: off day, annual leave, public holiday, sick leave (+ other for old Excel rows).
-- Run once in Supabase SQL Editor (safe to re-run).

alter table public.ba_attendance_entries
  drop constraint if exists ba_attendance_entries_status_check;

alter table public.ba_attendance_entries
  add constraint ba_attendance_entries_status_check
  check (status in ('off_day', 'annual_leave', 'public_holiday', 'sick_leave', 'other'));
