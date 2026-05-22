-- =============================================================================
-- Samah (Sharm) — manual account + merge Excel sales
-- Email: samah.mohamed31976@gmail.com
-- User UID: 32d44b55-682d-4971-8d56-d1c4a14c8507
--
-- Excel/roster name on imports: "Samah" (team Sharm)
-- Profile name at login: "Samah Mohamed"
-- Needs: link_legacy_rows_for_profile (merge_ba_accounts.sql section 1)
-- =============================================================================

-- BEFORE: unlinked Sharm imports still named Samah?
select ba_name, team, count(*) as rows_waiting
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Samah')
group by ba_name, team;

select ba_name, team, count(*) as att_waiting
from public.ba_attendance_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Samah')
group by ba_name, team;


-- Profile (Sharm BA)
insert into public.profiles (id, name, role, team, store)
values (
  '32d44b55-682d-4971-8d56-d1c4a14c8507'::uuid,
  'Samah Mohamed',
  'ba',
  'Sharm',
  null
)
on conflict (id) do update set
  name = excluded.name,
  role = excluded.role,
  team = excluded.team;

-- Merge all historical sales + attendance: roster "Samah" → her account
select public.link_legacy_rows_for_profile(
  '32d44b55-682d-4971-8d56-d1c4a14c8507'::uuid,
  'Samah Mohamed',
  'Samah'
);

-- Label linked rows with her registration name (not Excel short name)
update public.sales_entries s
set ba_name = p.name
from public.profiles p
where s.ba_id = p.id
  and p.id = '32d44b55-682d-4971-8d56-d1c4a14c8507'::uuid
  and trim(s.ba_name) is distinct from trim(p.name);

update public.ba_attendance_entries a
set ba_name = p.name
from public.profiles p
where a.ba_id = p.id
  and p.id = '32d44b55-682d-4971-8d56-d1c4a14c8507'::uuid
  and trim(a.ba_name) is distinct from trim(p.name);


-- AFTER: should show linked_sales > 0, att linked, no unlinked Samah left
select p.name, p.team, count(s.id) as linked_sales
from public.profiles p
left join public.sales_entries s on s.ba_id = p.id
where p.id = '32d44b55-682d-4971-8d56-d1c4a14c8507'::uuid
group by p.id, p.name, p.team;

select count(*) as still_unlinked_samah_sales
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Samah');

select count(*) as still_unlinked_samah_attendance
from public.ba_attendance_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Samah');
