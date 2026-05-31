-- =============================================================================
-- Link Besher Nasr (beshernasr6@gmail.com)
-- UID: cc619b38-1ed0-4b3c-b774-23a4087cc9a2
--
-- If still_unlinked stays 107: unique index blocks UPDATE when he already
-- logged the same day in the app. This script removes import duplicates first.
-- Run the WHOLE file in one go (Supabase SQL Editor → Run).
-- =============================================================================

-- DIAG: unlinked import rows vs rows already on his account (overlap = conflict)
select
  (select count(*) from public.sales_entries
   where ba_id is null
     and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher')) as unlinked_import,
  (select count(*) from public.sales_entries
   where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid) as already_on_account,
  (select count(*) from public.sales_entries s
   where s.ba_id is null
     and public.normalize_ba_name(s.ba_name) = public.normalize_ba_name('Besher')
     and exists (
       select 1 from public.sales_entries o
       where o.ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
         and o.entry_date = s.entry_date
         and coalesce(o.store, '') = coalesce(s.store, '')
         and coalesce(o.shift, '') = coalesce(s.shift, '')
     )) as import_rows_blocked_by_unique_index;

-- Profile
insert into public.profiles (id, name, role, team, store)
values (
  'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
  'Besher Nasr',
  'ba',
  'Hurgadah',
  null
)
on conflict (id) do update set
  name = excluded.name,
  role = 'ba',
  team = coalesce(nullif(trim(public.profiles.team), ''), excluded.team);

-- Step 1: Drop import rows that duplicate a day he already logged in the app
-- (keeps app row; removes conflicting Excel row so UPDATE can succeed)
delete from public.sales_entries s
where s.ba_id is null
  and public.normalize_ba_name(s.ba_name) = public.normalize_ba_name('Besher')
  and exists (
    select 1 from public.sales_entries o
    where o.ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
      and o.entry_date = s.entry_date
      and coalesce(o.store, '') = coalesce(s.store, '')
      and coalesce(o.shift, '') = coalesce(s.shift, '')
  );

-- Step 2: Link remaining import rows
update public.sales_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');

-- Attendance: same pattern
delete from public.ba_attendance_entries a
where a.ba_id is null
  and public.normalize_ba_name(a.ba_name) = public.normalize_ba_name('Besher')
  and exists (
    select 1 from public.ba_attendance_entries o
    where o.ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
      and o.entry_date = a.entry_date
  );

update public.ba_attendance_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');

-- Step 3: Dedupe anything left (same BA + date + store + shift)
with sales_ranked as (
  select id,
    row_number() over (
      partition by ba_id, entry_date, coalesce(store, ''), coalesce(shift, '')
      order by
        (case when coalesce(sales_amount, 0) > 0 then 1 else 0 end) desc,
        created_at desc nulls last, id desc
    ) as rn
  from public.sales_entries
  where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
)
delete from public.sales_entries s using sales_ranked r
where s.id = r.id and r.rn > 1;

with att_ranked as (
  select id,
    row_number() over (
      partition by ba_id, entry_date
      order by created_at desc nulls last, id desc
    ) as rn
  from public.ba_attendance_entries
  where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
)
delete from public.ba_attendance_entries a using att_ranked r
where a.id = r.id and r.rn > 1;

-- AFTER
select
  count(*) filter (where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid) as linked_sales,
  coalesce(sum(sales_amount) filter (
    where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
      and entry_date >= '2026-05-01' and entry_date < '2026-06-01'
  ), 0) as may_total
from public.sales_entries;

select count(*) as still_unlinked_besher_sales
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');

-- If still > 0, run this alone and paste the error message:
-- update public.sales_entries
-- set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
-- where id = (select id from public.sales_entries where ba_id is null
--   and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher') limit 1);
