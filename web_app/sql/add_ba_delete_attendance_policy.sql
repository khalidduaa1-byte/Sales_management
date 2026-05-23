-- =============================================================================
-- Let BAs delete their own leave/off-day rows (fix wrong dates)
-- Run once in Supabase SQL Editor.
-- =============================================================================

drop policy if exists "BAs can delete own attendance" on public.ba_attendance_entries;

create policy "BAs can delete own attendance"
  on public.ba_attendance_entries for delete
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

-- Requires import_roster_matches_name from fix_besher_nasr_link_and_rls.sql or merge_ba_accounts.
-- If that function is missing, use this simpler policy instead:
-- create policy "BAs can delete own attendance"
--   on public.ba_attendance_entries for delete
--   using (ba_id = auth.uid());
