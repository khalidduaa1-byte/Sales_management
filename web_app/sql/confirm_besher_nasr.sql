-- Confirm Besher Nasr can sign in (no email link required)
-- beshernasr6@gmail.com — cc619b38-1ed0-4b3c-b774-23a4087cc9a2
-- Run in Supabase SQL Editor, then reset password in Auth (see index.html forgot password or Dashboard).

update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now())
where id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid;

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

select u.email, u.email_confirmed_at is not null as email_confirmed, p.name, p.team
from auth.users u
left join public.profiles p on p.id = u.id
where u.id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid;
