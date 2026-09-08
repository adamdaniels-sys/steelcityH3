-- One-off data fix -- 2026-09-08. NOT a schema migration; run it once.
--
-- "Count Sheet" in the Buxton import was a typo for "Count Sheep". It came in
-- verbatim from the spreadsheet, which was the right call at the time: the
-- import deliberately does not guess at names, because "Nosejob: nj" looked
-- like a typo too and turned out to be two real people. This one Adam has
-- confirmed, so it is safe to correct.
--
-- The name is stored on the attendance rows themselves (event_attendances
-- .attendee_label), and get_legacy_attendees derives the legacy list from
-- those, so fixing the rows fixes every place it shows: the roster, the
-- past-attendee dropdown, and the reference list.
--
-- Matching is case-insensitive and trimmed, the same way the legacy list
-- groups names, so a stray space cannot make it miss.
--
-- Run in: Supabase Dashboard -> SQL Editor. Paste the whole file.

update public.event_attendances
   set attendee_label = 'Count Sheep'
 where is_legacy = true
   and user_id is null
   and lower(trim(attendee_label)) = 'count sheet';

-- Check. EXPECT: one row reading "Count Sheep", and no row reading
-- "Count Sheet". If you still see "Count Sheet", nothing was written.
select attendee_label, count(*) as rows
  from public.event_attendances
 where lower(trim(attendee_label)) in ('count sheet', 'count sheep')
 group by attendee_label;
