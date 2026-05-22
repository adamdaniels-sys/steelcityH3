-- Steel City H3 — legacy attendees: expose what they owe
--
-- get_legacy_attendees() now also returns `owed` + `debt_count` so legacy
-- (pre-website) people can be listed on Manage Members with their outstanding
-- balance. Same debt rule as 0018: an unpaid row (amount_paid > 0) on a
-- FINALISED event. Return type changes, so DROP first (42P13 otherwise).
--
-- Run in the Supabase SQL Editor AFTER 0019 (and 0020). Idempotent.

drop function if exists public.get_legacy_attendees();

create or replace function public.get_legacy_attendees()
returns table (
  label           text,
  kennel          text,
  event_count     integer,
  matched_user_id uuid,
  matched_name    text,
  owed            numeric,
  debt_count      integer
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  return query
  with legacy as (
    select lower(trim(a.attendee_label))      as key,
           max(a.attendee_label)              as label,
           max(a.attendee_kennel)             as kennel,
           count(distinct a.event_id)::integer as event_count,
           coalesce(sum(case
                          when a.paid = false
                           and coalesce(a.amount_paid, 0) > 0
                           and e.attendance_finalised_at is not null
                          then a.amount_paid else 0 end), 0)::numeric as owed,
           count(*) filter (
             where a.paid = false
               and coalesce(a.amount_paid, 0) > 0
               and e.attendance_finalised_at is not null
           )::integer as debt_count
    from public.event_attendances a
    join public.events e on e.id = a.event_id
    where a.is_legacy = true
      and a.user_id is null
      and coalesce(trim(a.attendee_label), '') <> ''
    group by lower(trim(a.attendee_label))
  )
  select l.label, l.kennel, l.event_count,
         p.id as matched_user_id,
         coalesce(nullif(trim(p.hash_name), ''), p.real_name) as matched_name,
         l.owed, l.debt_count
  from legacy l
  left join public.profiles p on lower(trim(p.hash_name)) = l.key
  order by (p.id is not null) desc, lower(l.label);
end;
$$;
grant execute on function public.get_legacy_attendees() to authenticated;
