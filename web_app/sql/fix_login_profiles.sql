-- =============================================================================
-- Login broken? Run this in Supabase SQL Editor (read-only checks first)
-- =============================================================================

-- 1) Auth users vs profiles (missing profile = login then instant kick-out)
select
  u.id as user_id,
  u.email,
  u.email_confirmed_at is not null as email_confirmed,
  p.id as profile_id,
  p.name,
  p.role
from auth.users u
left join public.profiles p on p.id = u.id
order by u.email;

-- 2) Auth users with NO profile row (fix these in step 3)
select u.id, u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
order by u.email;

-- =============================================================================
-- 3) FIX missing profile — one block per person (edit UUID + name + role)
-- Get user_id from query above. role must be 'manager' or 'ba'.
-- =============================================================================

-- Example: manager Rania (replace if your row shows profile_id null)
-- insert into public.profiles (id, name, role, team, store)
-- values (
--   'a70eaa58-deb8-4693-926b-a7e7c1fb4b95',
--   'Rania Essam Eldin',
--   'manager',
--   null,
--   null
-- )
-- on conflict (id) do update set
--   name = excluded.name,
--   role = excluded.role;

-- Example: BA (paste their auth user id)
-- insert into public.profiles (id, name, role, team, store)
-- values (
--   'PASTE-BA-USER-UUID',
--   'Their Display Name',
--   'ba',
--   'Cairo',
--   null
-- )
-- on conflict (id) do update set
--   name = excluded.name,
--   role = excluded.role,
--   team = coalesce(excluded.team, public.profiles.team);

-- =============================================================================
-- 4) Wrong role on profile? (manager sent to BA page or vice versa)
-- =============================================================================
-- update public.profiles set role = 'manager' where id = 'PASTE-UUID';
-- update public.profiles set role = 'ba' where id = 'PASTE-UUID';

-- =============================================================================
-- 5) Re-check after fix
-- =============================================================================
select u.email, p.name, p.role
from auth.users u
join public.profiles p on p.id = u.id
order by u.email;
