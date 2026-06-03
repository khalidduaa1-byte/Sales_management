-- add_team_month_total_fn.sql
-- ================================================================
-- WHAT / WHY
-- Hurgadah's monthly target is target_type = 'team_total' (commission is
-- team-based, not per-BA). The BA app previously divided the team goal by the
-- BA headcount and showed each BA only their own slice — which broke as the
-- team grew (e.g. 45,000 / 4 = 11,250 made no sense for a team commission).
--
-- This function lets every team_total BA see the SAME team goal and the team's
-- COMBINED progress. RLS only lets a BA read their own sales rows, so we use a
-- SECURITY DEFINER function that returns ONLY the team's deduped total (a single
-- number — no individual rows, so no privacy leak). Team is derived from
-- auth.uid(): a caller can never read another team's number.
--
-- Dedup key matches the manager dashboard (ba, date, store, shift), so the
-- number a BA sees equals the manager's team total.
--
-- Safe to re-run (create or replace). Run this in the Supabase SQL Editor.
-- ================================================================

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

-- Sanity check after running (should match the manager dashboard's Hurgadah
-- June total; will be 0 until June sales are logged):
--   set role authenticated;  -- optional; or just trust the manager number
--   select public.get_team_month_total('2026-06');
