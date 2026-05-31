-- =============================================================================
-- Link NEW signups to Excel/import history (sales + attendance)
-- Run in Supabase SQL Editor after BAs create accounts.
--
-- Prerequisite (once per project): run section 1 of merge_ba_accounts.sql
--   (creates link_legacy_rows_for_profile, normalize_ba_name, etc.)
--
-- Safe to re-run. Does not delete unique rows — only links ba_id null + dedupes.
-- =============================================================================

-- ── 1) WHO signed up recently? (last 14 days — widen if needed) ─────────────
select
  p.id,
  p.name as profile_name,
  p.team,
  u.email,
  u.created_at::date as signed_up,
  u.email_confirmed_at is not null as email_confirmed
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'ba'
  and u.created_at >= now() - interval '14 days'
order by u.created_at desc;

-- ── 2) Do they still have unlinked Excel rows? (should go to 0 after step 5) ─
select
  p.name as profile_name,
  p.team,
  u.email,
  count(s.id) filter (where s.ba_id = p.id) as already_linked,
  (
    select count(*)
    from public.sales_entries x
    where x.ba_id is null
      and public.normalize_ba_name(x.ba_name) = public.normalize_ba_name(p.name)
  ) as unlinked_sales_matching_profile_name,
  (
    select string_agg(distinct x.ba_name, ', ' order by x.ba_name)
    from public.sales_entries x
    where x.ba_id is null
      and trim(coalesce(x.ba_name, '')) <> ''
      and public.normalize_ba_name(x.ba_name) in (
        select public.normalize_ba_name(m.roster_name)
        from (
          values
            (p.name),
            (public.import_roster_name_for_profile(p.name))
        ) as m(roster_name)
      )
  ) as excel_names_we_will_try
from public.profiles p
left join auth.users u on u.id = p.id
where p.role = 'ba'
group by p.id, p.name, p.team, u.email
having count(s.id) filter (where s.ba_id = p.id) = 0
   or exists (
     select 1 from public.sales_entries x
     where x.ba_id is null
       and public.normalize_ba_name(x.ba_name) = public.normalize_ba_name(p.name)
   )
order by unlinked_sales_matching_profile_name desc, p.name;

-- ── 3) Excel names still waiting for ANY account ────────────────────────────
select s.ba_name as excel_roster_name, s.team, count(*) as unlinked_rows
from public.sales_entries s
where s.ba_id is null
  and trim(coalesce(s.ba_name, '')) <> ''
group by s.ba_name, s.team
order by s.team, s.ba_name;

-- ── 4) New signups: pick Excel name from dropdown? (exact match expected) ───
select p.name, u.email, p.team
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'ba'
  and u.created_at >= now() - interval '14 days'
order by p.name;

-- ── 5) LINK everyone (known short-name map + exact / roster match) ─────────
create temp table ba_merge_map (
  registered_name text not null,
  roster_name     text not null
);

insert into ba_merge_map (registered_name, roster_name) values
  ('Mohamed Ahmed',   'Mohamed'),
  ('Mamdouh Mohamed', 'Mamdouh'),
  ('Nada Saad',       'Nada'),
  ('Emaan Salah',     'Eman1'),
  ('Eman salah',      'Eman1'),
  ('veronia',         'Veronia'),
  ('Samah mohamed',   'Samah'),
  ('Samah Mohamed',   'Samah'),
  ('ahmed abdelaal',  'Ahmed'),
  ('Esraa Abdullah',  'Esraa'),
  ('Mohamed Atef',    'Atef'),
  ('Nouran adel',     'Nouran');
  -- ADD new mismatches here, then re-run from this DO block:
  -- ('Full Name They Typed', 'ExcelShortName'),

do $$
declare
  r record;
  v_roster text;
  v_match text;
  res json;
begin
  for r in
    select id, name from public.profiles where role = 'ba' order by name
  loop
    select m.roster_name into v_roster
    from ba_merge_map m
    where public.normalize_ba_name(m.registered_name) = public.normalize_ba_name(r.name)
    limit 1;
    v_match := coalesce(v_roster, public.import_roster_name_for_profile(r.name), r.name);
    res := public.link_legacy_rows_for_profile(r.id, r.name, v_match);
    raise notice 'Linked % via "%": %', r.name, v_match, res;
  end loop;
end $$;

-- Align display names on linked rows
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

-- Dedupe sales (same BA + date + store + shift)
with sales_ranked as (
  select id,
    row_number() over (
      partition by
        coalesce(ba_id::text, 'name:' || public.normalize_ba_name(ba_name)),
        entry_date, coalesce(store, ''), coalesce(shift, '')
      order by
        (case when coalesce(sales_amount, 0) > 0 then 1 else 0 end) desc,
        created_at desc nulls last, id desc
    ) as rn
  from public.sales_entries
)
delete from public.sales_entries s using sales_ranked r
where s.id = r.id and r.rn > 1;

-- Dedupe attendance (same BA + date)
with att_ranked as (
  select id,
    row_number() over (
      partition by
        coalesce(ba_id::text, 'name:' || public.normalize_ba_name(ba_name)),
        entry_date
      order by created_at desc nulls last, id desc
    ) as rn
  from public.ba_attendance_entries
)
delete from public.ba_attendance_entries a using att_ranked r
where a.id = r.id and r.rn > 1;

-- ── 6) AFTER — each BA should show linked_sales > 0 if they had imports ─────
select
  p.name,
  p.team,
  u.email,
  count(s.id) filter (where s.ba_id = p.id) as linked_sales,
  coalesce(sum(s.sales_amount) filter (where s.ba_id = p.id and s.entry_date >= '2026-05-01' and s.entry_date < '2026-06-01'), 0) as may_total_linked
from public.profiles p
left join auth.users u on u.id = p.id
left join public.sales_entries s on s.ba_id = p.id
where p.role = 'ba'
group by p.id, p.name, p.team, u.email
order by p.name;

-- Still unlinked Excel (need signup OR manual map row above)
select ba_name, team, count(*) as still_unlinked
from public.sales_entries
where ba_id is null
  and trim(coalesce(ba_name, '')) <> ''
group by ba_name, team
order by ba_name;
