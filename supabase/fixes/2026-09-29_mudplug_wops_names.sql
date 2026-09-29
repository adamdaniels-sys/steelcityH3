-- One-off data fix -- 2026-09-29. NOT a schema migration; run it once.
--
-- Queen Myrtle confirmed two spellings:
--   "Mug Plug" should be "Mudplug"
--   "Wop"      should be "Wops"
--
-- A hash name can be stored in four places, so all four are corrected:
--   event_attendances.attendee_label  (legacy roster rows -> the legacy lists)
--   events.hares                      (the "Hares without an account" text)
--   events.additional_hares_text
--   profiles.hash_name                (in case either has signed up)
--
-- Matching is whole-word and case-insensitive (\m and \M are word edges), so
-- "Wop" is never matched inside "Wops" or any longer name, and re-running this
-- file changes nothing.
--
-- Run in: Supabase Dashboard -> SQL Editor. Paste the whole file.

update public.event_attendances
   set attendee_label = 'Mudplug'
 where lower(trim(attendee_label)) in ('mug plug', 'mugplug');

update public.event_attendances
   set attendee_label = 'Wops'
 where lower(trim(attendee_label)) = 'wop';

update public.events
   set hares = regexp_replace(regexp_replace(hares, '\mMug\s*Plug\M', 'Mudplug', 'gi'), '\mWop\M', 'Wops', 'gi')
 where hares ~* '\mMug\s*Plug\M' or hares ~* '\mWop\M';

update public.events
   set additional_hares_text = regexp_replace(regexp_replace(additional_hares_text, '\mMug\s*Plug\M', 'Mudplug', 'gi'), '\mWop\M', 'Wops', 'gi')
 where additional_hares_text ~* '\mMug\s*Plug\M' or additional_hares_text ~* '\mWop\M';

update public.profiles
   set hash_name = 'Mudplug'
 where lower(trim(hash_name)) in ('mug plug', 'mugplug');

update public.profiles
   set hash_name = 'Wops'
 where lower(trim(hash_name)) = 'wop';

-- Check. EXPECT: rows reading only "Mudplug" and "Wops" -- no "Mug Plug",
-- no "Wop". If an old spelling still shows, nothing was written for it.
select 'attendance' as place, attendee_label as name, count(*) as rows
  from public.event_attendances
 where attendee_label ~* '\m(mug\s*plug|mudplug|wops?)\M'
 group by attendee_label
union all
select 'hares text', hares, count(*)
  from public.events
 where hares ~* '\m(mug\s*plug|mudplug|wops?)\M'
 group by hares
union all
select 'profile', hash_name, count(*)
  from public.profiles
 where hash_name ~* '\m(mug\s*plug|mudplug|wops?)\M'
 group by hash_name;
