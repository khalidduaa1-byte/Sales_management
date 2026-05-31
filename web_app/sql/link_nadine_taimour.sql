-- =============================================================================
-- Link Nadine Taimour only — Excel roster name "Nadine" (Cairo)
-- Email: nadinetaimour39@icloud.com
-- UID:  cde0634d-9e92-48f2-aa68-e562925c6f22
-- Run entire file in Supabase SQL Editor.
-- =============================================================================

-- BEFORE
select count(*) as unlinked_nadine_sales
from public.sales_entries
where ba_id is null
  and lower(trim(ba_name)) = 'nadine';

select id, name, team, email
from public.profiles p
join auth.users u on u.id = p.id
where p.id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid;

-- Profile (keep display name; Excel imports use "Nadine")
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
  team = coalesce(nullif(trim(public.profiles.team), ''), excluded.team);

-- Remove import duplicate only if same day already logged in app (usually 0 rows)
delete from public.sales_entries s
where s.ba_id is null
  and lower(trim(s.ba_name)) = 'nadine'
  and exists (
    select 1 from public.sales_entries o
    where o.ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
      and o.entry_date = s.entry_date
      and coalesce(o.store, '') = coalesce(s.store, '')
      and coalesce(o.shift, '') = coalesce(s.shift, '')
  );

-- Link sales (unlinked + old Gmail account 9426e195-...)
update public.sales_entries
set ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
    ba_name = 'Nadine Taimour'
where lower(trim(ba_name)) in ('nadine', 'nadine taimour')
   or ba_id = '9426e195-13f3-4b48-9353-d7b85c657af8'::uuid;

-- Link attendance
delete from public.ba_attendance_entries a
where a.ba_id is null
  and lower(trim(a.ba_name)) = 'nadine'
  and exists (
    select 1 from public.ba_attendance_entries o
    where o.ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
      and o.entry_date = a.entry_date
  );

update public.ba_attendance_entries
set ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
    ba_name = 'Nadine Taimour'
where lower(trim(ba_name)) in ('nadine', 'nadine taimour')
   or ba_id = '9426e195-13f3-4b48-9353-d7b85c657af8'::uuid;

-- AFTER
select
  p.name,
  u.email,
  count(s.id) as linked_sales,
  coalesce(sum(s.sales_amount) filter (
    where s.entry_date >= '2026-05-01' and s.entry_date < '2026-06-01'
  ), 0) as may_total
from public.profiles p
join auth.users u on u.id = p.id
left join public.sales_entries s on s.ba_id = p.id
where p.id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
group by p.name, u.email;

select count(*) as still_unlinked_nadine
from public.sales_entries
where ba_id is null
  and lower(trim(ba_name)) = 'nadine';

-- Old account? (nadeentaimour@gmail.com) — if rows stuck on old UUID, say so
select u.id, u.email, count(s.id) as linked_sales
from auth.users u
left join public.sales_entries s on s.ba_id = u.id
where public.normalize_ba_name(coalesce(
  (select name from public.profiles p where p.id = u.id), ''
)) = public.normalize_ba_name('Nadine')
   or u.email ilike '%nadine%'
group by u.id, u.email
order by u.email;
