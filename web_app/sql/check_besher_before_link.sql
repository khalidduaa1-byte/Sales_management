-- =============================================================================
-- READ ONLY — no changes. Run first if you want to preview.
-- =============================================================================

select count(*) as unlinked_excel_rows
from public.sales_entries
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher');

select count(*) as already_on_his_account
from public.sales_entries
where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid;

select id, name, team, role
from public.profiles
where id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid;

-- If > 0, UPDATE could fail on duplicate day (rare if he never used the app)
select count(*) as duplicate_day_conflicts
from public.sales_entries s
where s.ba_id is null
  and lower(trim(s.ba_name)) in ('besher', 'basher')
  and exists (
    select 1 from public.sales_entries o
    where o.ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid
      and o.entry_date = s.entry_date
      and coalesce(o.store, '') = coalesce(s.store, '')
      and coalesce(o.shift, '') = coalesce(s.shift, '')
  );
