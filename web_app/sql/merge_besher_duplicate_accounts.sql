-- =============================================================================
-- Merge duplicate Besher accounts → keep ONE account
--
-- KEEP (use this login):  Besher Nasr — beshernasr6@gmail.com
--   cc619b38-1ed0-4b3c-b774-23a4087cc9a2
--
-- MERGE FROM (delete in Auth after SQL):  Bisher Naser — beshososojojo@gmail.com
--   642bd078-5f67-49d9-922d-26a2c710f831
--
-- Run entire file in Supabase SQL Editor.
-- After success: Authentication → Users → delete beshososojojo@gmail.com
-- =============================================================================

-- BEFORE: what each account has
select 'KEEP' as which, u.email, p.name, p.team,
  (select count(*) from public.sales_entries s where s.ba_id = u.id) as sales,
  (select count(*) from public.ba_attendance_entries a where a.ba_id = u.id) as attendance
from auth.users u
left join public.profiles p on p.id = u.id
where u.id in (
  'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
  '642bd078-5f67-49d9-922d-26a2c710f831'::uuid
)
order by which;

select count(*) as unlinked_besher_sales
from public.sales_entries
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher', 'bisher');

-- Canonical profile (keeper)
insert into public.profiles (id, name, role, team, store)
values (
  'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
  'Besher Nasr',
  'ba',
  'Hurgadah',
  null
)
on conflict (id) do update set
  name = 'Besher Nasr',
  role = 'ba',
  team = coalesce(nullif(trim(public.profiles.team), ''), 'Hurgadah');

-- Remove duplicate-account rows that would clash on same day (keeper row wins)
delete from public.sales_entries s
where s.ba_id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid
  and exists (
    select 1 from public.sales_entries k
    where k.ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
      and k.entry_date = s.entry_date
      and coalesce(k.store, '') = coalesce(s.store, '')
      and coalesce(k.shift, '') = coalesce(s.shift, '')
  );

delete from public.ba_attendance_entries a
where a.ba_id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid
  and exists (
    select 1 from public.ba_attendance_entries k
    where k.ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
      and k.entry_date = a.entry_date
  );

-- Move everything left on duplicate → keeper
update public.sales_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid;

update public.ba_attendance_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid;

-- Link any Excel rows still unlinked (roster name Besher)
update public.sales_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher', 'bisher');

update public.ba_attendance_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher', 'bisher');

-- Dedupe sales (same day + shop + shift)
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

-- Remove orphan profile on duplicate (optional; Auth user delete is separate)
delete from public.profiles
where id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid;

-- AFTER
select 'KEEP' as which, u.email, p.name,
  count(s.id) as sales,
  coalesce(sum(s.sales_amount) filter (
    where s.entry_date >= '2026-05-01' and s.entry_date < '2026-06-01'
  ), 0) as may_total
from auth.users u
join public.profiles p on p.id = u.id
left join public.sales_entries s on s.ba_id = p.id
where u.id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
group by u.email, p.name;

select count(*) as sales_still_on_duplicate
from public.sales_entries
where ba_id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid;

select u.email, u.id
from auth.users u
where u.id = '642bd078-5f67-49d9-922d-26a2c710f831'::uuid;
-- ^ After merge: delete this user in Supabase Auth UI
