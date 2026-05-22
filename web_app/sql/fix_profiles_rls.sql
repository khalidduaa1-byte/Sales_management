-- Fix: "infinite recursion detected in policy for relation profiles"
-- Cause: RLS policies on profiles that SELECT from profiles without bypassing RLS.
-- Run entire file in Supabase SQL Editor, then retry login.
--
-- Supabase may warn "destructive operations" because of DROP POLICY below.
-- That is expected and safe here: no tables/rows are deleted — only 3 RLS
-- rules on profiles are replaced, plus helper functions are updated.

-- ── Helpers (SECURITY DEFINER = bypass RLS; safe inside profiles policies) ──

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

grant execute on function public.is_manager() to authenticated;
grant execute on function public.auth_profile_role() to authenticated;
grant execute on function public.auth_profile_team() to authenticated;

-- ── profiles SELECT policies ────────────────────────────────────────────────

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Managers can read all profiles" on public.profiles;
create policy "Managers can read all profiles"
  on public.profiles for select
  using (public.is_manager());

drop policy if exists "BAs can read same-team BA profiles" on public.profiles;
create policy "BAs can read same-team BA profiles"
  on public.profiles for select
  using (
    public.auth_profile_role() = 'ba'
    and public.auth_profile_team() is not null
    and role = 'ba'
    and team = public.auth_profile_team()
  );

-- ── link_my_legacy_rows (BA app on load) ────────────────────────────────────

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
  return public.link_legacy_rows_for_profile(auth.uid(), v_name, v_name);
end;
$$;

grant execute on function public.link_my_legacy_rows() to authenticated;
