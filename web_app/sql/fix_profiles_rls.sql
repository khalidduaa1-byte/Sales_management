-- Re-apply "read own profile" policy if profile fetch fails after login (RLS)
-- Safe to run in Supabase SQL Editor

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Managers can read all profiles" on public.profiles;
create policy "Managers can read all profiles"
  on public.profiles for select
  using (public.is_manager());

-- Ensure link_my_legacy_rows exists (BA app calls this on load)
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
