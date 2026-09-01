-- ================================================================
-- Egypt BA Sales App — Database Setup
-- Run this entire script in Supabase SQL Editor
-- ================================================================

-- TABLE 1: profiles
-- Every user (BA or manager) gets a row here after they sign up.
-- It extends Supabase's built-in auth system which handles passwords.
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  role       text not null check (role in ('manager', 'ba')),
  team       text,   -- Cairo / Sharm / Hurgadah
  store      text,   -- which store they work at
  start_date date,   -- first active day; dashboard hides the BA before this month
  end_date   date    -- last active day; dashboard stops expecting submissions after it (null = still active)
);

-- TABLE 2: sales_entries
-- One row = one BA's shift submission
create table if not exists public.sales_entries (
  id            uuid primary key default gen_random_uuid(),
  ba_id         uuid references public.profiles(id) on delete cascade,
  ba_name       text not null,
  team          text not null,
  store         text not null,
  shift         text not null check (shift in ('Morning', 'Afternoon', 'Evening')),
  sales_amount  numeric(10,2) not null,
  items_sold    integer not null,
  working_days  integer not null default 1,
  entry_date    date not null default current_date,
  created_at    timestamptz default now()
);

-- TABLE 3: monthly_targets
-- Manager-configurable targets per month and team.
-- target_type:
--   - per_ba: value is target per BA, final target = value * active BAs
--   - team_total: value is full team target
create table if not exists public.monthly_targets (
  id           uuid primary key default gen_random_uuid(),
  month_key    text not null, -- format: YYYY-MM
  team         text not null check (team in ('Cairo', 'Sharm', 'Hurgadah')),
  target_type  text not null check (target_type in ('per_ba', 'team_total')),
  target_value numeric(12,2) not null check (target_value > 0),
  created_by   uuid references public.profiles(id),
  created_at   timestamptz default now(),
  updated_at   timestamptz default now(),
  unique (month_key, team)
);

-- TABLE 4: ba_attendance_entries
-- One row = one BA marked as off day / annual leave on a date.
create table if not exists public.ba_attendance_entries (
  id          uuid primary key default gen_random_uuid(),
  ba_id       uuid references public.profiles(id) on delete cascade,
  ba_name     text not null,
  team        text not null,
  store       text,
  entry_date  date not null,
  status      text not null check (status in ('off_day', 'annual_leave', 'public_holiday', 'sick_leave', 'other')),
  notes       text,
  created_at  timestamptz default now(),
  unique (ba_id, entry_date)
);

-- Add working_days to existing databases (safe to run even if column already exists)
alter table public.sales_entries
  add column if not exists working_days integer not null default 1;

-- Add start_date to existing databases (safe to run even if column already exists).
-- Backfill is handled by web_app/sql/add_profiles_start_date.sql on the live DB.
alter table public.profiles
  add column if not exists start_date date;

-- De-duplicate exact same BA/date/store/shift rows (keep newest), then prevent future duplicates.
-- Important: some historical imports may have ba_id = null, so we fallback to ba_name in the key.
with ranked as (
  select
    id,
    row_number() over (
      partition by
        coalesce(ba_id::text, 'name:' || lower(coalesce(ba_name, ''))),
        entry_date,
        coalesce(store, ''),
        coalesce(shift, '')
      order by created_at desc nulls last, id desc
    ) as rn
  from public.sales_entries
)
delete from public.sales_entries s
using ranked r
where s.id = r.id and r.rn > 1;

-- Enforce uniqueness for normal BA-app inserts (ba_id present).
create unique index if not exists sales_entries_unique_ba_date_store_shift
  on public.sales_entries (ba_id, entry_date, store, shift);

-- Enforce uniqueness for legacy rows where ba_id is null (fallback to ba_name).
create unique index if not exists sales_entries_unique_name_date_store_shift_when_no_baid
  on public.sales_entries (lower(ba_name), entry_date, store, shift)
  where ba_id is null;

alter table public.monthly_targets enable row level security;
alter table public.ba_attendance_entries enable row level security;
alter table public.animation_events enable row level security;
alter table public.animation_daily  enable row level security;
alter table public.ba_attendance_entries drop constraint if exists ba_attendance_entries_status_check;
alter table public.ba_attendance_entries add constraint ba_attendance_entries_status_check
  check (status in ('off_day', 'annual_leave', 'public_holiday', 'sick_leave', 'other'));

-- TABLE 5: animation_events
-- The EGYPT AIR animation-spot calendar. Drives which animation shop appears in
-- the BA app shop dropdown, automatically, during each event window. Managers add
-- future events with one INSERT. Seed data lives in web_app/sql/add_animation_calendar.sql.
create table if not exists public.animation_events (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,        -- BA-facing shop label, e.g. 'Terminal 3 — 702A (animation)'
  team               text not null check (team in ('Cairo', 'Sharm', 'Hurgadah')),
  campaign           text,                 -- reference only (The One / Light Blue / Devotion / Holidays)
  start_date         date not null,
  end_date           date not null,
  entry_buffer_days  integer not null default 3,  -- BAs may still log this many days after end_date
  target_pcs_per_day integer,
  created_at         timestamptz default now(),
  unique (name, start_date)
);

-- TABLE 6: animation_daily
-- Daily actuals for animations that ALREADY happened. Reference ONLY — feeds the
-- manager "Animations" tab. These sales are already inside the monthly totals, so
-- they must NEVER be inserted into sales_entries (would double-count — Invariant #3).
create table if not exists public.animation_daily (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid references public.animation_events(id) on delete set null,
  store_label  text not null,
  team         text not null check (team in ('Cairo', 'Sharm', 'Hurgadah')),
  campaign     text,
  entry_date   date not null,
  target_pcs   integer,
  qty_sold     integer not null default 0,
  sales_amount numeric(12,2) not null default 0,  -- same unit as the app ($)
  created_at   timestamptz default now(),
  unique (store_label, entry_date)
);

-- ── Row Level Security (RLS) ─────────────────────────────────────
-- RLS means: users can only see/edit data they're allowed to.
-- Without this, anyone with the anon key could read all data.

alter table public.profiles     enable row level security;
alter table public.sales_entries enable row level security;

-- Drop policies first so this script is safe to re-run
drop policy if exists "Users can read own profile"    on public.profiles;
drop policy if exists "Managers can read all profiles" on public.profiles;
drop policy if exists "Users can update own profile"  on public.profiles;
drop policy if exists "BAs can insert own sales"      on public.sales_entries;
drop policy if exists "BAs can read own sales"        on public.sales_entries;
drop policy if exists "BAs can update own sales"     on public.sales_entries;
drop policy if exists "BAs can delete own sales"     on public.sales_entries;
drop policy if exists "Managers can read all sales"   on public.sales_entries;
drop policy if exists "Managers can read monthly targets" on public.monthly_targets;
drop policy if exists "Managers can write monthly targets" on public.monthly_targets;
drop policy if exists "BAs can read team monthly targets" on public.monthly_targets;
drop policy if exists "BAs can read same-team BA profiles" on public.profiles;
drop policy if exists "BAs can insert own attendance" on public.ba_attendance_entries;
drop policy if exists "BAs can read own attendance" on public.ba_attendance_entries;
drop policy if exists "BAs can update own attendance" on public.ba_attendance_entries;
drop policy if exists "BAs can delete own attendance" on public.ba_attendance_entries;
drop policy if exists "Managers can read all attendance" on public.ba_attendance_entries;

-- Helper functions for RLS on profiles.
-- Must be SECURITY DEFINER (bypasses RLS) so policies on profiles never
-- subquery profiles under the caller's RLS (infinite recursion).
create or replace function public.is_manager()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'manager'
  );
$$;

create or replace function public.auth_profile_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.auth_profile_team()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select team from public.profiles where id = auth.uid();
$$;

-- profiles: users can read their own profile, managers can read all
create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Managers can read all profiles"
  on public.profiles for select
  using (public.is_manager());

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- BAs can see other BAs on the same team (name/team only) so the app can count headcount
-- for per-BA targets without exposing sales data.
create policy "BAs can read same-team BA profiles"
  on public.profiles for select
  using (
    public.auth_profile_role() = 'ba'
    and public.auth_profile_team() is not null
    and role = 'ba'
    and team = public.auth_profile_team()
  );

-- sales_entries: BAs can insert + read their own; managers read all
create policy "BAs can insert own sales"
  on public.sales_entries for insert
  with check (ba_id = auth.uid());

-- Own rows by ba_id, plus legacy imports where ba_id is null but ba_name matches the signed-in profile name.
create policy "BAs can read own sales"
  on public.sales_entries for select
  using (
    ba_id = auth.uid()
    or (
      ba_id is null
      and lower(trim(ba_name)) = lower(trim((select p.name from public.profiles p where p.id = auth.uid())))
    )
  );

create policy "BAs can update own sales"
  on public.sales_entries for update
  using (ba_id = auth.uid())
  with check (ba_id = auth.uid());

-- Mirror read policy: BAs may remove app rows (ba_id set) and legacy import rows
-- matched by name (ba_id null). Otherwise duplicate date/shop/shift can look "undeletable".
create policy "BAs can delete own sales"
  on public.sales_entries for delete
  using (
    ba_id = auth.uid()
    or (
      ba_id is null
      and lower(trim(ba_name)) = lower(trim((select p.name from public.profiles p where p.id = auth.uid())))
    )
  );

create policy "Managers can read all sales"
  on public.sales_entries for select
  using (public.is_manager());

create policy "Managers can read monthly targets"
  on public.monthly_targets for select
  using (public.is_manager());

-- BAs see targets for their own team only (used on the BA home screen).
create policy "BAs can read team monthly targets"
  on public.monthly_targets for select
  using (
    team = (select p.team from public.profiles p where p.id = auth.uid() and p.role = 'ba')
  );

create policy "Managers can write monthly targets"
  on public.monthly_targets for all
  using (public.is_manager())
  with check (public.is_manager());

-- ba_attendance_entries: BAs can insert/read/update their own; managers read all
create policy "BAs can insert own attendance"
  on public.ba_attendance_entries for insert
  with check (ba_id = auth.uid());

create policy "BAs can read own attendance"
  on public.ba_attendance_entries for select
  using (ba_id = auth.uid());

create policy "BAs can update own attendance"
  on public.ba_attendance_entries for update
  using (ba_id = auth.uid())
  with check (ba_id = auth.uid());

create policy "BAs can delete own attendance"
  on public.ba_attendance_entries for delete
  using (
    ba_id = auth.uid()
    or (
      ba_id is null
      and lower(trim(ba_name)) = lower(trim((select p.name from public.profiles p where p.id = auth.uid())))
    )
  );

create policy "Managers can read all attendance"
  on public.ba_attendance_entries for select
  using (public.is_manager());

-- Animation calendar + historical actuals: everyone signed-in reads, managers write.
drop policy if exists "Anyone can read animation events"   on public.animation_events;
drop policy if exists "Managers can write animation events" on public.animation_events;
drop policy if exists "Anyone can read animation daily"     on public.animation_daily;
drop policy if exists "Managers can write animation daily"  on public.animation_daily;

create policy "Anyone can read animation events"
  on public.animation_events for select
  using (auth.uid() is not null);

create policy "Managers can write animation events"
  on public.animation_events for all
  using (public.is_manager())
  with check (public.is_manager());

create policy "Anyone can read animation daily"
  on public.animation_daily for select
  using (auth.uid() is not null);

create policy "Managers can write animation daily"
  on public.animation_daily for all
  using (public.is_manager())
  with check (public.is_manager());

-- ── Auto-update updated_at on monthly_targets ────────────────────
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create or replace trigger monthly_targets_updated_at
  before update on public.monthly_targets
  for each row execute procedure public.set_updated_at();

-- ── Normalize BA names (signup + legacy import matching) ─────────
create or replace function public.normalize_ba_name(raw text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(raw, '')), '\s+', ' ', 'g'));
$$;

create or replace function public.link_legacy_rows_for_profile(
  p_user_id uuid,
  p_display_name text,
  p_import_match_name text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  n_sales int;
  n_att int;
  norm_match text;
  v_min date;
begin
  norm_match := public.normalize_ba_name(coalesce(nullif(trim(p_import_match_name), ''), p_display_name));
  if public.normalize_ba_name(p_display_name) = '' or p_user_id is null then
    return json_build_object('ok', false, 'sales_linked', 0, 'attendance_linked', 0);
  end if;

  update public.sales_entries
  set ba_id = p_user_id,
      ba_name = trim(p_display_name)
  where ba_id is null
    and public.normalize_ba_name(ba_name) = norm_match;
  get diagnostics n_sales = row_count;

  update public.ba_attendance_entries
  set ba_id = p_user_id,
      ba_name = trim(p_display_name)
  where ba_id is null
    and public.normalize_ba_name(ba_name) = norm_match;
  get diagnostics n_att = row_count;

  -- Pull start_date back to the earliest linked row (LEAST ignores NULLs).
  select least(
    (select min(entry_date) from public.sales_entries where ba_id = p_user_id),
    (select min(entry_date) from public.ba_attendance_entries where ba_id = p_user_id)
  ) into v_min;
  if v_min is not null then
    update public.profiles
    set start_date = case when start_date is null then v_min else least(start_date, v_min) end
    where id = p_user_id;
  end if;

  return json_build_object('ok', true, 'sales_linked', n_sales, 'attendance_linked', n_att);
end;
$$;

create or replace function public.link_my_legacy_rows()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  select name into v_name from public.profiles where id = auth.uid();
  if v_name is null then
    return json_build_object('ok', false, 'error', 'no_profile');
  end if;
  return public.link_legacy_rows_for_profile(
    auth.uid(),
    v_name,
    public.import_roster_name_for_profile(v_name)
  );
end;
$$;

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
          ('Nouran adel',     'Nouran')
      ) as m(registered_name, roster_name)
      where public.normalize_ba_name(m.registered_name) = public.normalize_ba_name(p_display_name)
      limit 1
    ),
    p_display_name
  );
$$;

create or replace function public.get_registration_ba_names()
returns table (ba_name text, team text)
language sql
security definer
stable
set search_path = public
as $$
  select distinct on (public.normalize_ba_name(n.ba_name))
    trim(n.ba_name) as ba_name,
    trim(n.team) as team
  from (
    select ba_name, team from public.sales_entries where ba_id is null
    union all
    select ba_name, team from public.ba_attendance_entries where ba_id is null
  ) n
  where trim(coalesce(n.ba_name, '')) <> ''
    and trim(coalesce(n.team, '')) <> ''
    and not exists (
      select 1 from public.profiles p
      where p.role = 'ba'
        and public.normalize_ba_name(p.name) = public.normalize_ba_name(n.ba_name)
    )
  order by public.normalize_ba_name(ba_name);
$$;

grant execute on function public.normalize_ba_name(text) to anon, authenticated;
grant execute on function public.get_registration_ba_names() to anon, authenticated;
grant execute on function public.is_manager() to authenticated;
grant execute on function public.auth_profile_role() to authenticated;
grant execute on function public.auth_profile_team() to authenticated;
grant execute on function public.import_roster_name_for_profile(text) to authenticated;
grant execute on function public.link_my_legacy_rows() to authenticated;

-- ── Auto-create profile on signup + link imported history ────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_team text;
begin
  v_name := trim(coalesce(new.raw_user_meta_data->>'name', 'Unknown'));
  v_team := nullif(trim(coalesce(new.raw_user_meta_data->>'team', '')), '');

  insert into public.profiles (id, name, role, team, store, start_date)
  values (
    new.id,
    v_name,
    coalesce(new.raw_user_meta_data->>'role', 'ba'),
    v_team,
    nullif(trim(coalesce(new.raw_user_meta_data->>'store', '')), ''),
    (now() at time zone 'Africa/Cairo')::date
  );

  if coalesce(new.raw_user_meta_data->>'role', 'ba') = 'ba' then
    perform public.link_legacy_rows_for_profile(
      new.id,
      v_name,
      public.import_roster_name_for_profile(v_name)
    );
  end if;

  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── Team-total month progress (for team_total targets) ───────────
-- For teams whose monthly target is target_type = 'team_total' (e.g. Hurgadah,
-- where commission is team-based), every BA should see the SAME team goal and
-- the team's COMBINED progress — not their individual share. RLS only lets a BA
-- read their own sales rows, so this SECURITY DEFINER function returns just the
-- team's deduped total (a single number, no per-BA rows) for the caller's own
-- team. Team is derived from auth.uid(); a caller can never read another team.
-- Dedup matches the manager dashboard's natural key (ba, date, store, shift).
create or replace function public.get_team_month_total(p_month_key text)
returns numeric
language sql
security definer
set search_path = public
as $$
  with my_team as (
    select lower(btrim(team)) as t from public.profiles where id = auth.uid()
  ),
  scoped as (
    select distinct on (
        coalesce(s.ba_id::text, lower(btrim(s.ba_name))),
        s.entry_date, lower(btrim(s.store)), s.shift
      )
      s.sales_amount
    from public.sales_entries s, my_team
    where (
            lower(btrim(s.team)) = my_team.t
            or (my_team.t in ('hurgadah','hurghada')
                and lower(btrim(s.team)) in ('hurgadah','hurghada'))
          )
      and to_char(s.entry_date, 'YYYY-MM') = p_month_key
    order by
      coalesce(s.ba_id::text, lower(btrim(s.ba_name))),
      s.entry_date, lower(btrim(s.store)), s.shift,
      (s.ba_id is not null) desc, s.sales_amount desc
  )
  select coalesce(sum(sales_amount), 0)::numeric from scoped;
$$;

revoke all on function public.get_team_month_total(text) from public;
grant execute on function public.get_team_month_total(text) to authenticated;
