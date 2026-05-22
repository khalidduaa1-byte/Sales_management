-- Run in Supabase SQL Editor after fix_profiles_rls.sql
-- All checks should return rows; "bad_*" queries should return 0 rows.

-- 1) Helper functions exist and bypass RLS (security definer)
select
  p.proname as function_name,
  p.prosecdef as security_definer,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_manager', 'auth_profile_role', 'auth_profile_team', 'link_my_legacy_rows')
order by p.proname;

-- 2) Expected SELECT policies on profiles
select policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename = 'profiles'
  and cmd = 'SELECT'
order by policyname;

-- 3) FAIL if same-team policy still subqueries profiles (recursion risk)
select policyname, qual as bad_recursive_qual
from pg_policies
where schemaname = 'public'
  and tablename = 'profiles'
  and policyname = 'BAs can read same-team BA profiles'
  and qual ilike '%from public.profiles%';

-- 4) FAIL if is_manager is not security definer
select p.proname as bad_function
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'is_manager'
  and p.prosecdef is not true;
