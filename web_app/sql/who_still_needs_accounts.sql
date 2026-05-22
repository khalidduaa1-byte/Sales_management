-- =============================================================================
-- Who still needs a login? Run in Supabase SQL Editor (live truth).
-- =============================================================================

-- A) Excel/import rows with NO account linked yet (still ba_id null)
--    = these roster names need signup OR manual link like Samah
select
  s.ba_name as excel_roster_name,
  s.team,
  count(*) as unlinked_sales_rows
from public.sales_entries s
where s.ba_id is null
  and trim(coalesce(s.ba_name, '')) <> ''
group by s.ba_name, s.team
order by s.team, s.ba_name;

-- B) Same for attendance imports
select
  a.ba_name,
  a.team,
  count(*) as unlinked_att_rows
from public.ba_attendance_entries a
where a.ba_id is null
  and trim(coalesce(a.ba_name, '')) <> ''
group by a.ba_name, a.team
order by a.team, a.ba_name;

-- C) Auth user exists but NO profile (login kicks them out)
select u.id as user_id, u.email, u.email_confirmed_at is not null as confirmed
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
  and u.email is not null
order by u.email;

-- D) Profile exists but NO auth user (orphan profile — rare)
select p.id, p.name, p.team, p.role
from public.profiles p
left join auth.users u on u.id = p.id
where p.role = 'ba'
  and u.id is null
order by p.name;

-- E) Registered BAs: do they have linked history?
select
  p.name as profile_name,
  p.team,
  u.email,
  count(s.id) filter (where s.ba_id = p.id) as linked_sales,
  count(s.id) filter (
    where s.ba_id is null
      and public.normalize_ba_name(s.ba_name) = public.normalize_ba_name(p.name)
  ) as still_unlinked_by_name
from public.profiles p
left join auth.users u on u.id = p.id
left join public.sales_entries s on s.ba_id = p.id
  or (s.ba_id is null and public.normalize_ba_name(s.ba_name) = public.normalize_ba_name(p.name))
where p.role = 'ba'
group by p.id, p.name, p.team, u.email
order by linked_sales asc, p.name;

-- F) Names on register dropdown right now (= no profile claims that Excel name yet)
select * from public.get_registration_ba_names();
