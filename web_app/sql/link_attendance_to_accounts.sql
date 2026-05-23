-- Link unlinked attendance (OFF / AL days) to registered BAs — fixes red X on off days
-- Run after sales linking. Safe to re-run.

update public.ba_attendance_entries a
set ba_id = p.id, ba_name = p.name
from public.profiles p
where a.ba_id is null
  and p.role = 'ba'
  and public.normalize_ba_name(a.ba_name) = public.normalize_ba_name(
    public.import_roster_name_for_profile(p.name)
  );

-- Fallback: first name match (Nadine / Besher Nasr / etc.)
update public.ba_attendance_entries a
set ba_id = p.id, ba_name = p.name
from public.profiles p
where a.ba_id is null
  and p.role = 'ba'
  and public.normalize_ba_name(split_part(trim(a.ba_name), ' ', 1)) =
      public.normalize_ba_name(split_part(trim(p.name), ' ', 1));

select ba_name, count(*) as still_unlinked_att
from public.ba_attendance_entries
where ba_id is null
group by ba_name
order by ba_name;
