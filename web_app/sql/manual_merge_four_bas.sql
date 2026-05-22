-- =============================================================================
-- ONE-TIME manual merge: Esraa, Atef, Nouran, Ahmed
-- Run in Supabase SQL Editor, top to bottom.
--
-- Excel imports use SHORT names: Esraa | Atef | Nouran | Ahmed
-- Profiles may use FULL names: Esraa Abdullah | Mohamed Atef | Nouran adel | ahmed abdelaal
-- (or the short name — both work in the steps below)
--
-- Needs: public.link_legacy_rows_for_profile (from merge_ba_accounts.sql section 1)
-- =============================================================================

-- ── STEP 0: See who exists before you merge ─────────────────────────────────
select p.id, p.name, p.team, u.email
from public.profiles p
left join auth.users u on u.id = p.id
where p.role = 'ba'
  and public.normalize_ba_name(p.name) in (
    public.normalize_ba_name('Esraa Abdullah'),
    public.normalize_ba_name('Esraa'),
    public.normalize_ba_name('Mohamed Atef'),
    public.normalize_ba_name('Atef'),
    public.normalize_ba_name('Nouran adel'),
    public.normalize_ba_name('Nouran'),
    public.normalize_ba_name('ahmed abdelaal'),
    public.normalize_ba_name('Ahmed')
  )
order by p.name;

-- Unlinked import rows waiting to attach (should show counts before merge)
select ba_name, count(*) as rows_to_link
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) in (
    public.normalize_ba_name('Esraa'),
    public.normalize_ba_name('Atef'),
    public.normalize_ba_name('Nouran'),
    public.normalize_ba_name('Ahmed')
  )
group by ba_name
order by ba_name;


-- ── STEPS 1–4: Link by confirmed profile id (run all four) ───────────────────
-- Each returns JSON, e.g. {"ok":true,"sales_linked":42,"attendance_linked":3}

select public.link_legacy_rows_for_profile(
  '9c39f263-a822-469b-9a52-760d3a60851f'::uuid, 'Esraa Abdullah', 'Esraa');

select public.link_legacy_rows_for_profile(
  '7b7f1204-88a9-4721-85ea-89a0c30ca6e1'::uuid, 'Mohamed Atef', 'Atef');

select public.link_legacy_rows_for_profile(
  'cb4ccf31-c6fb-41a5-84d0-d21b22443526'::uuid, 'Nouran adel', 'Nouran');

select public.link_legacy_rows_for_profile(
  '04005d6e-eb8f-4b96-9949-88a89b8e5e6e'::uuid, 'ahmed abdelaal', 'Ahmed');


-- ── STEP 5: Fix labels on linked rows (dashboard uses profile name) ─────────
update public.sales_entries s
set ba_name = p.name
from public.profiles p
where s.ba_id = p.id
  and trim(s.ba_name) is distinct from trim(p.name);

update public.ba_attendance_entries a
set ba_name = p.name
from public.profiles p
where a.ba_id = p.id
  and trim(a.ba_name) is distinct from trim(p.name);


-- ── STEP 6: Verify — linked_sales should be > 0; unlinked imports → 0 ───────
select p.name as profile_name, count(s.id) as linked_sales
from public.profiles p
left join public.sales_entries s on s.ba_id = p.id
where p.role = 'ba'
  and public.normalize_ba_name(p.name) in (
    public.normalize_ba_name('Esraa Abdullah'),
    public.normalize_ba_name('Esraa'),
    public.normalize_ba_name('Mohamed Atef'),
    public.normalize_ba_name('Atef'),
    public.normalize_ba_name('Nouran adel'),
    public.normalize_ba_name('Nouran'),
    public.normalize_ba_name('ahmed abdelaal'),
    public.normalize_ba_name('Ahmed')
  )
group by p.id, p.name
order by p.name;

select ba_name, count(*) as still_unlinked
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) in (
    public.normalize_ba_name('Esraa'),
    public.normalize_ba_name('Atef'),
    public.normalize_ba_name('Nouran'),
    public.normalize_ba_name('Ahmed')
  )
group by ba_name;
