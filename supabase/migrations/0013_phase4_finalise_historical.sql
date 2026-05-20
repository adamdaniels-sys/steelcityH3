-- Steel City H3 — Phase 4 follow-up: finalise the historical completed events
--
-- Phase 4 gates all PUBLIC charity display on attendance_finalised_at (so a
-- half-done roster never leaks a partial total). The events seeded back in
-- Phase 1 (#13–17) predate that column, so their attendance_finalised_at is
-- NULL — which means the £282.15 from the anniversary hash (#15) stopped
-- showing on the homepage bar, the past-row, and the event page.
--
-- These events are genuinely finished, so mark them finalised. Sets the
-- timestamp to the evening of the event (a plausible "wrapped up" time) only
-- where it isn't already set. Run AFTER 0012. Idempotent.
--
-- After this: get_charity_totals() returns £282.15 across the completed hashes,
-- the homepage bar goes live, and #15's event page shows its charity badge.

update public.events
   set attendance_finalised_at = (event_date + interval '20 hours')
 where status = 'completed'
   and attendance_finalised_at is null;
