-- READ-ONLY. Run this and paste the output back. It changes nothing.
--
-- Why: the delete guard refused, reporting that event 16 has 2 attendances,
-- 2 rsvps and 2 hares. That data is invisible to the public API (RLS hides it),
-- so my earlier "both copies are empty" check was wrong, and so was my advice
-- to keep event 18. This shows what is actually on each copy.
--
-- Every column is cast to text: events.status is an enum, and a UNION needs
-- matching types down each column.

select 'EVENT'::text      as what,
       e.id::text         as event_id,
       e.title::text      as who_or_what,
       e.status::text     as detail_1,
       e.event_date::text as detail_2,
       e.created_at::text as when_added
  from public.events e
 where e.id in (16, 18)

union all

select 'attendance'::text,
       a.event_id::text,
       coalesce(p.hash_name, a.attendee_label, '(account, no hash name)')::text,
       (case when a.is_legacy          then 'legacy'
             when a.user_id is not null then 'member'
             else                            'guest' end)::text,
       ('paid=' || a.paid::text || '  GBP ' || coalesce(a.amount_paid, 0)::text)::text,
       a.created_at::text
  from public.event_attendances a
  left join public.profiles p on p.id = a.user_id
 where a.event_id in (16, 18)

union all

select 'rsvp'::text,
       r.event_id::text,
       coalesce(p.hash_name, p.real_name, '(no name on profile)')::text,
       r.status::text,
       ('guests=' || coalesce(r.guests_count, 0)::text)::text,
       r.created_at::text
  from public.rsvps r
  left join public.profiles p on p.id = r.user_id
 where r.event_id in (16, 18)

union all

select 'hare'::text,
       h.event_id::text,
       coalesce(p.hash_name, p.real_name, '(no name on profile)')::text,
       (case when h.volunteered then 'volunteered' else 'assigned' end)::text,
       ''::text,
       h.created_at::text
  from public.event_hares h
  left join public.profiles p on p.id = h.user_id
 where h.event_id in (16, 18)

order by 2, 1, 3;
