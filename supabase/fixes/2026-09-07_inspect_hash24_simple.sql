-- READ-ONLY fallback. Four separate queries, no UNION, nothing clever.
-- Run them one at a time (or all at once and read the four result sets) and
-- paste back what you see. Nothing here changes any data.
--
-- Use this if 2026-09-07_inspect_hash24.sql gives you any more trouble.

-- 1. The two events themselves.
select id, run_number, title, status, event_date, created_at, attendance_finalised_at
  from public.events
 where id in (16, 18)
 order by id;

-- 2. Who is on the attendance roster of each.
select a.event_id, a.attendee_label, p.hash_name, a.is_legacy, a.paid, a.amount_paid, a.created_at
  from public.event_attendances a
  left join public.profiles p on p.id = a.user_id
 where a.event_id in (16, 18)
 order by a.event_id, a.created_at;

-- 3. Who has RSVP'd to each.
select r.event_id, p.hash_name, p.real_name, r.status, r.guests_count, r.created_at
  from public.rsvps r
  left join public.profiles p on p.id = r.user_id
 where r.event_id in (16, 18)
 order by r.event_id, r.created_at;

-- 4. Who is haring each.
select h.event_id, p.hash_name, p.real_name, h.volunteered, h.created_at
  from public.event_hares h
  left join public.profiles p on p.id = h.user_id
 where h.event_id in (16, 18)
 order by h.event_id, h.created_at;
