-- =============================================================================
-- Link Besher (Hurgadah) — run in Supabase SQL Editor
-- If still_unlinked_besher_sales stays 107, run DIAGNOSTICS (A) first.
-- =============================================================================

-- ── A) DIAGNOSTICS — run these, read results before section C ───────────────

-- A1) Any profile named Besher/Basher? (empty = why link failed)
select p.id, p.name, p.team, u.email, u.created_at::date as signed_up
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'ba'
  and public.normalize_ba_name(p.name) in (
    public.normalize_ba_name('Besher'),
    public.normalize_ba_name('Basher')
  );

-- A2) Recent BA signups (last 30 days) — Besher is probably one of these
select u.id as user_id, u.email, p.name, p.team, p.role, u.created_at
from auth.users u
left join public.profiles p on p.id = u.id
where u.created_at >= now() - interval '30 days'
order by u.created_at desc;

-- A3) Auth user with NO profile? (login fails / link never runs)
select u.id as user_id, u.email, u.created_at
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
  and u.created_at >= now() - interval '30 days'
order by u.created_at desc;

-- A4) Unlinked Besher rows waiting
select count(*) as unlinked_sales
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');

-- A5) Link function exists?
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'link_legacy_rows_for_profile';


-- ── B) FIX missing profile (only if A3 shows a row — his auth user, no profile) ─
-- Replace USER_ID and email from A3:
--
-- insert into public.profiles (id, name, role, team, store)
-- values (
--   'PASTE-USER-ID-FROM-A3'::uuid,
--   'Besher',
--   'ba',
--   'Hurgadah',
--   null
-- )
-- on conflict (id) do update set
--   name = excluded.name,
--   role = excluded.role,
--   team = excluded.team;


-- ── C) LINK — paste his user_id from A1, A2, or B (one UUID only) ─────────
-- Uncomment and replace PASTE-BESHER-USER-UUID, then run this whole block:

/*
do $$
declare
  v_uid uuid := 'PASTE-BESHER-USER-UUID'::uuid;
  res json;
begin
  update public.profiles
  set name = 'Besher', team = coalesce(nullif(trim(team), ''), 'Hurgadah')
  where id = v_uid and role = 'ba';

  res := public.link_legacy_rows_for_profile(v_uid, 'Besher', 'Besher');
  raise notice 'link result: %', res;
end $$;
*/

-- ── C-alt) DIRECT link (use if function missing or C still leaves 107 unlinked) ─
-- Same UUID as above — uncomment both updates + run:

/*
update public.sales_entries
set ba_id = 'PASTE-BESHER-USER-UUID'::uuid,
    ba_name = 'Besher'
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');

update public.ba_attendance_entries
set ba_id = 'PASTE-BESHER-USER-UUID'::uuid,
    ba_name = 'Besher'
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');
*/


-- ── D) AUTO-LINK: only when exactly ONE recent Hurgadah BA (no UUID paste) ─
-- Skips if zero or multiple candidates. Safe to run after checking A2.
do $$
declare
  v_uid uuid;
  n int;
  res json;
begin
  select count(*) into n
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.role = 'ba'
    and u.created_at >= now() - interval '30 days'
    and (
      public.normalize_ba_name(coalesce(p.team, '')) like '%hurg%'
      or public.normalize_ba_name(coalesce(p.name, '')) like '%besher%'
      or public.normalize_ba_name(coalesce(p.name, '')) like '%basher%'
    );

  if n <> 1 then
    raise notice 'AUTO-LINK skipped: % Hurgadah/recent candidates (need exactly 1). Use section C with UUID.', n;
    return;
  end if;

  select p.id into v_uid
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.role = 'ba'
    and u.created_at >= now() - interval '30 days'
    and (
      public.normalize_ba_name(coalesce(p.team, '')) like '%hurg%'
      or public.normalize_ba_name(coalesce(p.name, '')) like '%besher%'
      or public.normalize_ba_name(coalesce(p.name, '')) like '%basher%'
    )
  limit 1;

  update public.profiles
  set name = 'Besher', team = 'Hurgadah'
  where id = v_uid;

  begin
    res := public.link_legacy_rows_for_profile(v_uid, 'Besher', 'Besher');
    raise notice 'AUTO link via function: %', res;
  exception when undefined_function then
    update public.sales_entries
    set ba_id = v_uid, ba_name = 'Besher'
    where ba_id is null
      and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');
    update public.ba_attendance_entries
    set ba_id = v_uid, ba_name = 'Besher'
    where ba_id is null
      and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');
    raise notice 'AUTO link via direct UPDATE (function was missing)';
  end;
end $$;


-- ── E) AFTER — still_unlinked should be 0 ───────────────────────────────────
select p.id, p.name, p.team, u.email, count(s.id) as linked_sales
from public.profiles p
join auth.users u on u.id = p.id
left join public.sales_entries s on s.ba_id = p.id
where p.role = 'ba'
  and public.normalize_ba_name(p.name) = public.normalize_ba_name('Besher')
group by p.id, p.name, p.team, u.email;

select count(*) as still_unlinked_besher_sales
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) = public.normalize_ba_name('Besher');
