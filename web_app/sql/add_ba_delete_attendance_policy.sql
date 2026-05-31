-- =============================================================================
-- SAFE: Allow BAs to delete their OWN leave/off-day rows (permissions only)
-- Does NOT delete any rows. Click Run / confirm — Supabase warns because of
-- "DROP POLICY" (removes an old rule name only, not your data).
-- =============================================================================

drop policy if exists "BAs can delete own attendance" on public.ba_attendance_entries;

create policy "BAs can delete own attendance"
  on public.ba_attendance_entries for delete
  using (ba_id = auth.uid());

-- Done. Esraa can use Delete in the app after Vercel deploys (or hard-refresh).
