-- =============================================================================
-- Besher Nasr — SAFE version (no DELETE)
-- UID: cc619b38-1ed0-4b3c-b774-23a4087cc9a2
-- Use this if Supabase warns about "destructive" and you want minimal risk.
-- (He has not logged days in the app — DELETE block would remove 0 rows anyway.)
-- =============================================================================

-- Roster map + RLS (same as full fix — helps app show "Besher" imports)
create or replace function public.import_roster_name_for_profile(p_display_name text)
returns text
language sql
immutable
as $$
  select coalesce(
    (
      select m.roster_name
      from (
        values
          ('Mohamed Ahmed', 'Mohamed'),
          ('Mamdouh Mohamed', 'Mamdouh'),
          ('Nada Saad', 'Nada'),
          ('Emaan Salah', 'Eman1'),
          ('Eman salah', 'Eman1'),
          ('veronia', 'Veronia'),
          ('Samah mohamed', 'Samah'),
          ('Samah Mohamed', 'Samah'),
          ('ahmed abdelaal', 'Ahmed'),
          ('Esraa Abdullah', 'Esraa'),
          ('Mohamed Atef', 'Atef'),
          ('Nouran adel', 'Nouran'),
          ('Besher Nasr', 'Besher'),
          ('Basher Nasr', 'Besher')
      ) as m(registered_name, roster_name)
      where public.normalize_ba_name(m.registered_name) = public.normalize_ba_name(p_display_name)
      limit 1
    ),
    p_display_name
  );
$$;

create or replace function public.import_roster_matches_name(p_entry_name text, p_profile_name text)
returns boolean
language sql
stable
as $$
  select
    public.normalize_ba_name(coalesce(p_entry_name, '')) =
      public.normalize_ba_name(coalesce(p_profile_name, ''))
    or public.normalize_ba_name(coalesce(p_entry_name, '')) =
      public.normalize_ba_name(public.import_roster_name_for_profile(p_profile_name));
$$;

drop policy if exists "BAs can read own sales" on public.sales_entries;
create policy "BAs can read own sales"
  on public.sales_entries for select
  using (
    ba_id = auth.uid()
    or (
      ba_id is null
      and public.import_roster_matches_name(
        ba_name,
        (select p.name from public.profiles p where p.id = auth.uid())
      )
    )
  );

drop policy if exists "BAs can delete own sales" on public.sales_entries;
create policy "BAs can delete own sales"
  on public.sales_entries for delete
  using (
    ba_id = auth.uid()
    or (
      ba_id is null
      and public.import_roster_matches_name(
        ba_name,
        (select p.name from public.profiles p where p.id = auth.uid())
      )
    )
  );

insert into public.profiles (id, name, role, team, store)
values (
  'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
  'Besher Nasr',
  'ba',
  'Hurgadah',
  null
)
on conflict (id) do update set
  name = excluded.name,
  role = 'ba',
  team = coalesce(nullif(trim(public.profiles.team), ''), excluded.team);

-- Link only (no DELETE)
update public.sales_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher');

update public.ba_attendance_entries
set ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid,
    ba_name = 'Besher Nasr'
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher');

select count(*) as linked_to_besher
from public.sales_entries
where ba_id = 'cc619b38-1ed0-4b3c-b774-23a4087cc9a2'::uuid;

select count(*) as still_unlinked_besher
from public.sales_entries
where ba_id is null
  and lower(trim(ba_name)) in ('besher', 'basher');
