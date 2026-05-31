-- =============================================================================
-- Confirm + profile + link Excel for Nadine, Mary, Rehab
-- Run entire file in Supabase SQL Editor (confirm when prompted).
-- =============================================================================

-- ── 1) Confirm email (allow sign-in) ─────────────────────────────────────────
-- confirmed_at is generated — only set email_confirmed_at
update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now())
where id in (
  '9426e195-13f3-4b48-9353-d7b85c657af8'::uuid,  -- Nadine  nadeentaimour@gmail.com
  'dab26185-e934-4aba-9975-b1c32f05cd64'::uuid,  -- Mary    noshiaghaly@gmail.com
  'f91210a3-654d-43e8-a67c-0b375f859a34'::uuid   -- Rehab   rehabsameheltomy1980@gmail.com
);

-- ── 2) Profiles (Excel roster names + teams) ─────────────────────────────────
insert into public.profiles (id, name, role, team, store) values
  ('9426e195-13f3-4b48-9353-d7b85c657af8'::uuid, 'Nadine', 'ba', 'Cairo', null),
  ('dab26185-e934-4aba-9975-b1c32f05cd64'::uuid, 'Mary', 'ba', 'Cairo', null),
  ('f91210a3-654d-43e8-a67c-0b375f859a34'::uuid, 'Rehab', 'ba', 'Hurgadah', null)
on conflict (id) do update set
  name = excluded.name,
  role = 'ba',
  team = excluded.team;

-- ── 3) Link Excel imports (ba_name on rows = Nadine / Mary / Rehab) ──────────
update public.sales_entries
set ba_id = v.uid, ba_name = v.display_name
from (values
  ('9426e195-13f3-4b48-9353-d7b85c657af8'::uuid, 'Nadine'),
  ('dab26185-e934-4aba-9975-b1c32f05cd64'::uuid, 'Mary'),
  ('f91210a3-654d-43e8-a67c-0b375f859a34'::uuid, 'Rehab')
) as v(uid, display_name)
where sales_entries.ba_id is null
  and public.normalize_ba_name(sales_entries.ba_name) =
      public.normalize_ba_name(v.display_name);

update public.ba_attendance_entries
set ba_id = v.uid, ba_name = v.display_name
from (values
  ('9426e195-13f3-4b48-9353-d7b85c657af8'::uuid, 'Nadine'),
  ('dab26185-e934-4aba-9975-b1c32f05cd64'::uuid, 'Mary'),
  ('f91210a3-654d-43e8-a67c-0b375f859a34'::uuid, 'Rehab')
) as v(uid, display_name)
where ba_attendance_entries.ba_id is null
  and public.normalize_ba_name(ba_attendance_entries.ba_name) =
      public.normalize_ba_name(v.display_name);

-- ── 4) VERIFY ────────────────────────────────────────────────────────────────
select u.email,
  u.email_confirmed_at is not null as confirmed,
  p.name,
  p.team,
  count(s.id) as linked_sales
from auth.users u
join public.profiles p on p.id = u.id
left join public.sales_entries s on s.ba_id = p.id
where u.id in (
  '9426e195-13f3-4b48-9353-d7b85c657af8'::uuid,
  'dab26185-e934-4aba-9975-b1c32f05cd64'::uuid,
  'f91210a3-654d-43e8-a67c-0b375f859a34'::uuid
)
group by u.email, u.email_confirmed_at, p.name, p.team
order by p.name;

select ba_name, count(*) as still_unlinked
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) in (
    public.normalize_ba_name('Nadine'),
    public.normalize_ba_name('Mary'),
    public.normalize_ba_name('Rehab')
  )
group by ba_name;
