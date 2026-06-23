-- add_animation_calendar.sql
--
-- WHAT
--   Generalizes the one-off "HPP" pilot into a real EGYPT AIR animation-spot
--   calendar, plus a reference table for the actuals of PAST animations.
--     * animation_events  — the calendar. Drives which animation shop appears in
--                            the BA app dropdown, automatically, during each event
--                            window. Managers can add future events with one INSERT.
--     * animation_daily   — daily actuals for animations that already happened.
--                            Reference ONLY: feeds the manager "Animations" tab.
--
-- WHY animation_daily exists (READ THIS):
--   The historical animation sales (Jan–Feb "The One" @ T3 702) are ALREADY
--   counted inside the existing monthly Excel-imported totals for those months.
--   They are NOT extra revenue sitting on top. Inserting them into sales_entries
--   would double-count (Jan Cairo would jump by ~€38k of phantom sales) and break
--   Invariant #3. So they live here, are shown in the Animations tab as a
--   breakdown, and are NEVER added to any shop or monthly total.
--
--   Future animations are different: BAs log them in the app like any other sale,
--   so those DO go into sales_entries (counted once — the app is the source going
--   forward, no Excel duplicate).
--
-- SAFE TO RE-RUN: create table if not exists + on conflict do nothing.

-- ── Tables ───────────────────────────────────────────────────────
create table if not exists public.animation_events (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,        -- BA-facing shop label, e.g. 'Terminal 3 — 702A (animation)'
  team               text not null check (team in ('Cairo', 'Sharm', 'Hurgadah')),
  campaign           text,                 -- reference only (The One / Light Blue / Devotion / Holidays)
  start_date         date not null,
  end_date           date not null,
  entry_buffer_days  integer not null default 3,  -- BAs may still log this many days after end_date
  target_pcs_per_day integer,              -- daily PCs target for the spot (null if unknown)
  created_at         timestamptz default now(),
  unique (name, start_date)
);

create table if not exists public.animation_daily (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid references public.animation_events(id) on delete set null,
  store_label  text not null,        -- matches the animation shop label
  team         text not null check (team in ('Cairo', 'Sharm', 'Hurgadah')),
  campaign     text,
  entry_date   date not null,
  target_pcs   integer,
  qty_sold     integer not null default 0,
  sales_amount numeric(12,2) not null default 0,  -- same unit as the app ($)
  created_at   timestamptz default now(),
  unique (store_label, entry_date)
);

-- ── RLS: everyone signed-in reads; only managers write ───────────
alter table public.animation_events enable row level security;
alter table public.animation_daily  enable row level security;

drop policy if exists "Anyone can read animation events" on public.animation_events;
create policy "Anyone can read animation events"
  on public.animation_events for select
  using (auth.uid() is not null);

drop policy if exists "Managers can write animation events" on public.animation_events;
create policy "Managers can write animation events"
  on public.animation_events for all
  using (public.is_manager())
  with check (public.is_manager());

drop policy if exists "Anyone can read animation daily" on public.animation_daily;
create policy "Anyone can read animation daily"
  on public.animation_daily for select
  using (auth.uid() is not null);

drop policy if exists "Managers can write animation daily" on public.animation_daily;
create policy "Managers can write animation daily"
  on public.animation_daily for all
  using (public.is_manager())
  with check (public.is_manager());

-- ── Seed: the 2026 calendar (April 11–20 was cancelled, omitted) ──
-- All spots use the 'Terminal N — <code> (animation)' form (Sharm: 'Sharm Sheikh — A
-- (animation)') so names share one format, the dashboard classifies the city, and
-- they stay out of the regular shop totals. The June pilot was at 702A (it was
-- logged under an interim 'HPP' label on the live DB — see rename_june_animation_to_702a.sql).
insert into public.animation_events (name, team, campaign, start_date, end_date, target_pcs_per_day) values
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One',       '2026-01-15', '2026-01-31', 15),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One',       '2026-02-01', '2026-02-15', 15),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'Light Blue',    '2026-06-01', '2026-06-10', null),
  ('Sharm Sheikh — A (animation)',  'Sharm', 'Light Blue',    '2026-06-21', '2026-06-30', null),
  ('Terminal 3 — 700 (animation)',  'Cairo', 'Light Blue',    '2026-07-21', '2026-07-30', null),
  ('Terminal 3 — 702C (animation)', 'Cairo', 'Light Blue',    '2026-08-01', '2026-08-10', null),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'Light Blue',    '2026-08-20', '2026-08-31', null),
  ('Terminal 3 — 700 (animation)',  'Cairo', 'Your Devotion', '2026-09-01', '2026-09-10', null),
  ('Terminal 2 — 281 (animation)',  'Cairo', 'Devotion',      '2026-10-01', '2026-10-10', null),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'Devotion',      '2026-10-20', '2026-10-31', null),
  ('Terminal 3 — 700 (animation)',  'Cairo', 'Holidays',      '2026-11-11', '2026-11-20', null),
  ('Sharm Sheikh — A (animation)',  'Sharm', 'Devotion',      '2026-11-11', '2026-11-20', null),
  ('Terminal 3 — 702C (animation)', 'Cairo', 'Holidays',      '2026-12-21', '2026-12-31', null),
  ('Sharm Sheikh — A (animation)',  'Sharm', 'Holidays',      '2026-12-10', '2026-12-20', null)
on conflict (name, start_date) do nothing;

-- ── Seed: historical actuals — "The One" @ T3 702A, 15 Jan – 15 Feb ──
-- Reference only. NOT added to any total (see header).
insert into public.animation_daily (store_label, team, campaign, entry_date, target_pcs, qty_sold, sales_amount) values
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-15', 15, 11, 1550.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-16', 15, 14, 1957.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-17', 15,  8, 1115.80),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-18', 15, 10, 1508.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-19', 15,  5,  710.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-20', 15,  2,  297.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-21', 15, 11, 1637.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-22', 15, 18, 2631.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-23', 15,  5,  671.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-24', 15, 10, 1356.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-25', 15, 11, 1635.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-26', 15,  8, 1160.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-27', 15,  5,  727.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-28', 15,  2,  302.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-29', 15,  9,  969.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-30', 15, 11, 1242.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-01-31', 15, 10, 1112.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-01', 15, 10, 1019.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-02', 15, 17, 1815.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-03', 15, 14, 1677.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-04', 15, 13, 1727.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-05', 15, 15, 1771.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-06', 15,  9,  907.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-07', 15, 16, 1756.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-08', 15, 26, 3358.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-09', 15, 11, 1201.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-10', 15,  6,  662.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-11', 15, 11, 1307.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-12', 15, 21, 2228.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-13', 15, 10, 1079.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-14', 15, 24, 3424.00),
  ('Terminal 3 — 702A (animation)', 'Cairo', 'The One', '2026-02-15', 15, 15, 1635.00)
on conflict (store_label, entry_date) do nothing;

-- Link the daily rows to their calendar events (by store + date window).
update public.animation_daily d
   set event_id = e.id
  from public.animation_events e
 where d.event_id is null
   and d.store_label = e.name
   and d.entry_date between e.start_date and e.end_date;
