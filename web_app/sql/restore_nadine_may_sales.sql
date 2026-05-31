-- =============================================================================
-- Move Nadine rows between accounts (if old account still exists)
--
-- If you DELETED the old auth user, sales were CASCADE-deleted too.
-- Use instead: restore_nadine_after_delete.sql (re-inserts from Excel)
-- =============================================================================

-- DIAG: where are Nadine rows?
select
  coalesce(u.email, '(unlinked)') as account_email,
  p.name as profile_name,
  s.ba_id,
  count(*) filter (where s.entry_date >= '2026-05-01' and s.entry_date < '2026-05-16') as may_1_15_rows,
  count(*) filter (where s.entry_date >= '2026-05-16' and s.entry_date < '2026-06-01') as may_16_plus_rows,
  coalesce(sum(s.sales_amount) filter (
    where s.entry_date >= '2026-05-01' and s.entry_date < '2026-06-01'
  ), 0) as may_total
from public.sales_entries s
left join public.profiles p on p.id = s.ba_id
left join auth.users u on u.id = s.ba_id
where lower(trim(s.ba_name)) = 'nadine'
   or lower(trim(s.ba_name)) like 'nadine %'
   or p.name ilike '%nadine%'
   or u.email ilike '%nadine%'
group by u.email, p.name, s.ba_id
order by may_1_15_rows desc;

-- Ensure current profile
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
  team = excluded.team;

-- Move ALL Nadine Excel/app rows → current account (any old ba_id or unlinked)
update public.sales_entries
set ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
    ba_name = 'Nadine Taimour'
where lower(trim(ba_name)) in ('nadine', 'nadine taimour')
   or ba_id = '9426e195-13f3-4b48-9353-d7b85c657af8'::uuid;

update public.ba_attendance_entries
set ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid,
    ba_name = 'Nadine Taimour'
where lower(trim(ba_name)) in ('nadine', 'nadine taimour')
   or ba_id = '9426e195-13f3-4b48-9353-d7b85c657af8'::uuid;

-- Dedupe: same day + shop + shift (keep best row after merge)
with sales_ranked as (
  select id,
    row_number() over (
      partition by entry_date, coalesce(store, ''), coalesce(shift, '')
      order by
        (case when coalesce(sales_amount, 0) > 0 then 1 else 0 end) desc,
        created_at desc nulls last, id desc
    ) as rn
  from public.sales_entries
  where ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
    and entry_date >= '2026-05-01' and entry_date < '2026-06-01'
)
delete from public.sales_entries s using sales_ranked r
where s.id = r.id and r.rn > 1;

-- VERIFY May 1–15 should have rows now
select
  count(*) filter (where entry_date >= '2026-05-01' and entry_date < '2026-05-16') as may_1_15_days_with_sales,
  count(*) filter (where entry_date >= '2026-05-16' and entry_date < '2026-06-01') as may_16_plus_days,
  coalesce(sum(sales_amount) filter (
    where entry_date >= '2026-05-01' and entry_date < '2026-06-01'
  ), 0) as may_total
from public.sales_entries
where ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid;

select entry_date, sales_amount, store, shift
from public.sales_entries
where ba_id = 'cde0634d-9e92-48f2-aa68-e562925c6f22'::uuid
  and entry_date >= '2026-05-01' and entry_date < '2026-05-16'
order by entry_date;
