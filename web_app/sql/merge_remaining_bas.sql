-- =============================================================================
-- Link remaining BAs (Esraa, Atef, Nouran, Ahmed + re-link others)
-- Run merge_ba_accounts.sql section 1 first if functions are missing.
--
-- Prefer a one-time manual run? Use: web_app/sql/manual_merge_four_bas.sql
-- =============================================================================

-- BEFORE: unlinked Excel rows still on short roster names?
select ba_name, count(*) as import_rows
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

-- BEFORE: registered profiles that should own those imports
select id, name, team
from public.profiles
where role = 'ba'
  and (
    public.normalize_ba_name(name) in (
      public.normalize_ba_name('Esraa Abdullah'),
      public.normalize_ba_name('Esraa'),
      public.normalize_ba_name('Mohamed Atef'),
      public.normalize_ba_name('Atef'),
      public.normalize_ba_name('Nouran adel'),
      public.normalize_ba_name('Nouran'),
      public.normalize_ba_name('ahmed abdelaal'),
      public.normalize_ba_name('Ahmed')
    )
  )
order by name;

-- Restore signup names if an earlier merge renamed profiles to roster-only names
update public.profiles set name = 'Mohamed Ahmed'
where role = 'ba' and name = 'Mohamed';

update public.profiles set name = 'Mamdouh Mohamed'
where role = 'ba' and name = 'Mamdouh';

update public.profiles set name = 'Nada Saad'
where role = 'ba' and name = 'Nada';

update public.profiles set name = 'Emaan Salah'
where role = 'ba' and name = 'Eman1';

update public.profiles set name = 'Veronia'
where role = 'ba' and public.normalize_ba_name(name) = public.normalize_ba_name('veronia');

update public.profiles set name = 'Samah Mohamed'
where role = 'ba' and name = 'Samah';

-- Link by roster map — matches profile whether they signed up as "Esraa" OR "Esraa Abdullah"
create temp table ba_merge_map (
  registered_name text not null,
  roster_name     text not null
);

insert into ba_merge_map (registered_name, roster_name) values
  ('Mohamed Ahmed',   'Mohamed'),
  ('Mamdouh Mohamed', 'Mamdouh'),
  ('Nada Saad',       'Nada'),
  ('Emaan Salah',     'Eman1'),
  ('veronia',         'Veronia'),
  ('Samah Mohamed',   'Samah'),
  ('ahmed abdelaal',  'Ahmed'),
  ('Esraa Abdullah',  'Esraa'),
  ('Mohamed Atef',    'Atef'),
  ('Nouran adel',     'Nouran');

do $$
declare
  m record;
  p record;
  res json;
begin
  for m in select * from ba_merge_map loop
    for p in
      select id, name
      from public.profiles
      where role = 'ba'
        and (
          public.normalize_ba_name(name) = public.normalize_ba_name(m.registered_name)
          or public.normalize_ba_name(name) = public.normalize_ba_name(m.roster_name)
        )
    loop
      res := public.link_legacy_rows_for_profile(p.id, p.name, m.roster_name);
      raise notice 'Linked profile "%" via Excel name "%": %', p.name, m.roster_name, res;
    end loop;
  end loop;
end $$;

-- History rows already linked: show signup name on every row for that BA
update public.sales_entries s
set ba_name = p.name
from public.profiles p
where s.ba_id = p.id and trim(s.ba_name) is distinct from trim(p.name);

update public.ba_attendance_entries a
set ba_name = p.name
from public.profiles p
where a.ba_id = p.id and trim(a.ba_name) is distinct from trim(p.name);

-- Dedupe (same day / shift duplicates after linking)
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

-- AFTER: these four should have linked_sales > 0 and import_rows for Esraa/Atef/Nouran/Ahmed = 0
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

select ba_name, count(*) as still_unlinked_import_rows
from public.sales_entries
where ba_id is null
  and public.normalize_ba_name(ba_name) in (
    public.normalize_ba_name('Esraa'),
    public.normalize_ba_name('Atef'),
    public.normalize_ba_name('Nouran'),
    public.normalize_ba_name('Ahmed')
  )
group by ba_name;
