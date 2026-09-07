-- One-off data fix -- 2026-09-07. NOT a schema migration; run it once.
--
-- WHAT WENT WRONG
-- Hash 24 (19 September 2026) was created twice, 31 minutes apart, and BOTH
-- copies were marked 'completed' with attendance finalised -- on 6 September,
-- for an event that has not happened yet. The homepage files anything
-- 'completed' under Past Hashes, so the next hash vanished from "Coming up".
--
-- Root cause was the admin UI, not the admins: the attendance tab offered no
-- plain Save, and later tabs were locked until the status advanced, so
-- "Save & complete" was both the only save-looking button AND the only way to
-- reach the rest of the form. Tracked as ISS-004 and ISS-005.
--
-- WHY DELETING 16 IS SAFE
-- Both copies carry the same two hares (Smutley, Queen Myrtle), auto-assigned
-- seconds after each was created. Migration 0009's auto_rsvp_on_hare_insert
-- trigger creates an RSVP whenever a hare is added, so event 16's 2 RSVPs are
-- those same two people, generated automatically -- not real member interest.
-- Adam confirmed: delete 16, keep 18 (fuller description, tidier title).
--
-- NOTE ON THE PREVIOUS VERSION: it wrapped everything in BEGIN/COMMIT and
-- reported "success" while changing NOTHING -- updated_at on both rows stayed
-- at 6 September. The Supabase SQL editor manages its own transaction, so an
-- explicit BEGIN/COMMIT here does not behave the way it would in psql. This
-- version uses NO transaction block: each statement stands alone and commits
-- on its own. Run the whole file; the SELECT at the end shows the result.
--
-- The delete cascades to event_attendances, rsvps, event_hares and
-- event_photos (all "on delete cascade").
--
-- Run in: Supabase Dashboard -> SQL Editor.

-- 1. Delete the duplicate -- but ONLY if it is still exactly the row we mean.
--    The WHERE clause is the guard: if anything about it has changed, this
--    deletes nothing rather than deleting the wrong thing.
delete from public.events
 where id = 16
   and run_number = 24
   and event_date = '2026-09-19'
   and not exists (select 1 from public.event_photos where event_id = 16);

-- 2. Un-complete the survivor. 'ready' = hares sorted, open for RSVPs.
update public.events
   set status                  = 'ready',
       attendance_finalised_at = null,
       updated_at              = now()
 where id = 18
   and run_number = 24
   and event_date = '2026-09-19';

-- 3. Check. EXPECT: exactly one row -- id 18, status 'ready', finalised empty.
--    If you still see two rows, or 18 still says 'completed', nothing was
--    written: say so and do not re-run blindly.
select id, run_number, title, event_date, status, attendance_finalised_at, updated_at
  from public.events
 where event_date = '2026-09-19';
