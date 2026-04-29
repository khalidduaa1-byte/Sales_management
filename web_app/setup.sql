-- ================================================================
-- Egypt BA Sales App — Database Setup
-- Run this entire script in Supabase SQL Editor
-- ================================================================

-- TABLE 1: profiles
-- Every user (BA or manager) gets a row here after they sign up.
-- It extends Supabase's built-in auth system which handles passwords.
create table if not exists public.profiles (
  id        uuid primary key references auth.users(id) on delete cascade,
  name      text not null,
  role      text not null check (role in ('manager', 'ba')),
  team      text,   -- Cairo / Sharm / Hurgadah
  store     text    -- which store they work at
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
  status      text not null check (status in ('off_day', 'annual_leave', 'other')),
  notes       text,
  created_at  timestamptz default now(),
  unique (ba_id, entry_date)
);

-- Add working_days to existing databases (safe to run even if column already exists)
alter table public.sales_entries
  add column if not exists working_days integer not null default 1;

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
alter table public.ba_attendance_entries drop constraint if exists ba_attendance_entries_status_check;
alter table public.ba_attendance_entries add constraint ba_attendance_entries_status_check
  check (status in ('off_day', 'annual_leave', 'other'));

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
drop policy if exists "Managers can read all sales"   on public.sales_entries;
drop policy if exists "Managers can read monthly targets" on public.monthly_targets;
drop policy if exists "Managers can write monthly targets" on public.monthly_targets;
drop policy if exists "BAs can insert own attendance" on public.ba_attendance_entries;
drop policy if exists "BAs can read own attendance" on public.ba_attendance_entries;
drop policy if exists "BAs can update own attendance" on public.ba_attendance_entries;
drop policy if exists "Managers can read all attendance" on public.ba_attendance_entries;

-- Helper function: check if the current user is a manager.
-- Must be security definer so it runs as the owner (bypasses RLS),
-- which prevents infinite recursion when called from a policy on profiles.
create or replace function public.is_manager()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'manager'
  );
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

-- sales_entries: BAs can insert + read their own; managers read all
create policy "BAs can insert own sales"
  on public.sales_entries for insert
  with check (ba_id = auth.uid());

create policy "BAs can read own sales"
  on public.sales_entries for select
  using (ba_id = auth.uid());

create policy "Managers can read all sales"
  on public.sales_entries for select
  using (public.is_manager());

create policy "Managers can read monthly targets"
  on public.monthly_targets for select
  using (public.is_manager());

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

create policy "Managers can read all attendance"
  on public.ba_attendance_entries for select
  using (public.is_manager());

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

-- ── Auto-create profile on signup ────────────────────────────────
-- This is a "trigger" — it fires automatically when someone signs up.
-- It creates their profile row so we don't have to do it manually.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name, role, team, store)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', 'Unknown'),
    coalesce(new.raw_user_meta_data->>'role', 'ba'),
    new.raw_user_meta_data->>'team',
    new.raw_user_meta_data->>'store'
  );
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
