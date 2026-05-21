-- Steel City H3 — legacy attendees + merge
--
-- Backfill past events with people who attended before the site existed
-- (Hash Name + Kennel only — no other PII). They're stored as event_attendances
-- rows with user_id NULL and is_legacy = true. When a real account signs up with
-- a matching hash name, an admin merges: the legacy rows get reassigned to that
-- account, so metrics show ONE person (not "Smutley (legacy)" + "Smutley").
--
--   1. event_attendances.is_legacy flag
--   2. get_event_attendance_roster — return is_legacy (DROP+recreate: return type)
--   3. get_legacy_attendees()      — the legacy-names list (+ matching account)
--   4. merge_legacy_attendee()     — reassign a legacy name's rows to an account
--   5. get_admin_leaderboards      — Top Hounds now counts ATTENDANCE (RSVPs +
--      attendance rows incl. legacy), so legacy folk appear and merge cleanly
--
-- Run in the Supabase SQL Editor AFTER 0001–0018. Idempotent.

-- ============================================================================
-- 1. is_legacy flag
-- ============================================================================
alter table public.event_attendances add column if not exists is_legacy boolean not null default false;


-- ============================================================================
-- 2. get_event_attendance_roster — include is_legacy
-- ============================================================================
drop function if exists public.get_event_attendance_roster(integer);

create or replace function public.get_event_attendance_roster(p_event_id integer)
returns table (
  id              uuid,
  user_id         uuid,
  attendee_label  text,
  attendee_kennel text,
  is_virgin_guest boolean,
  is_legacy       boolean,
  host_user_id    uuid,
  host_name       text,
  paid            boolean,
  amount_paid     numeric,
  charity_amount  numeric,
  display_name    text,
  kennel_name     text,
  rsvp_status     text,
  created_at      timestamptz
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  return query
  select
    a.id, a.user_id, a.attendee_label, a.attendee_kennel, a.is_virgin_guest, a.is_legacy, a.host_user_id,
    coalesce(nullif(trim(hp.hash_name), ''), hp.real_name) as host_name,
    a.paid, a.amount_paid, a.charity_amount,
    case when a.user_id is not null
      then coalesce(nullif(trim(p.hash_name), ''), p.real_name, 'Member')
      else coalesce(a.attendee_label, 'Guest')
    end as display_name,
    case when a.user_id is not null then p.kennel_name else a.attendee_kennel end as kennel_name,
    r.status::text as rsvp_status,
    a.created_at
  from public.event_attendances a
  left join public.profiles p  on p.id  = a.user_id
  left join public.profiles hp on hp.id = a.host_user_id
  left join public.rsvps r     on r.user_id = a.user_id and r.event_id = a.event_id
  where a.event_id = p_event_id
  order by a.created_at, a.id;
end;
$$;
grant execute on function public.get_event_attendance_roster(integer) to authenticated;


-- ============================================================================
-- 3. get_legacy_attendees — distinct legacy names + any matching account
-- ============================================================================
create or replace function public.get_legacy_attendees()
returns table (
  label        text,
  kennel       text,
  event_count  integer,
  matched_user_id uuid,
  matched_name text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  return query
  with legacy as (
    select lower(trim(a.attendee_label))      as key,
           max(a.attendee_label)              as label,
           max(a.attendee_kennel)             as kennel,
           count(distinct a.event_id)::integer as event_count
    from public.event_attendances a
    where a.is_legacy = true
      and a.user_id is null
      and coalesce(trim(a.attendee_label), '') <> ''
    group by lower(trim(a.attendee_label))
  )
  select l.label, l.kennel, l.event_count,
         p.id as matched_user_id,
         coalesce(nullif(trim(p.hash_name), ''), p.real_name) as matched_name
  from legacy l
  left join public.profiles p on lower(trim(p.hash_name)) = l.key
  order by (p.id is not null) desc, lower(l.label);
end;
$$;
grant execute on function public.get_legacy_attendees() to authenticated;


-- ============================================================================
-- 4. merge_legacy_attendee — reassign a legacy name's rows to a real account
-- ============================================================================
create or replace function public.merge_legacy_attendee(p_label text, p_user_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer := 0;
  r record;
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  if p_user_id is null then raise exception 'no target user'; end if;

  for r in
    select id, event_id from public.event_attendances
    where is_legacy = true and user_id is null
      and lower(trim(attendee_label)) = lower(trim(p_label))
  loop
    -- If the member already has a row on this event, drop the legacy duplicate;
    -- otherwise hand the legacy row over to them.
    if exists (select 1 from public.event_attendances
               where event_id = r.event_id and user_id = p_user_id) then
      delete from public.event_attendances where id = r.id;
    else
      update public.event_attendances set user_id = p_user_id where id = r.id;
    end if;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;
grant execute on function public.merge_legacy_attendee(text, uuid) to authenticated;


-- ============================================================================
-- 5. get_admin_leaderboards — Top Hounds counts ATTENDANCE (incl. legacy)
-- ============================================================================
-- Only top_attenders changes: it now counts distinct past events a person
-- ATTENDED — via an on-on RSVP OR an attendance row (real or legacy). That
-- folds backfilled legacy attendance in, and once a legacy name is merged its
-- rows carry a user_id so they count under the real member automatically.
-- top_hares / top_defilers are unchanged (legacy hares aren't tracked).

create or replace function public.get_admin_leaderboards(p_limit integer default 5)
returns json
language plpgsql stable security definer set search_path = public
as $$
declare
  result json;
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  select json_build_object(

    'top_attenders', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select user_id, name, count(distinct event_id)::integer as value
        from (
          -- members: on-on RSVPs to past events
          select p.id as user_id,
                 case when p.hash_name is null or trim(p.hash_name) = ''
                   then 'Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
                   else p.hash_name end as name,
                 e.id as event_id
          from public.rsvps r
          join public.events e   on e.id = r.event_id
          join public.profiles p on p.id = r.user_id
          where r.status = 'on_on' and e.event_date < current_date
          union
          -- members: attendance rows (incl. merged legacy)
          select p.id,
                 case when p.hash_name is null or trim(p.hash_name) = ''
                   then 'Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
                   else p.hash_name end,
                 e.id
          from public.event_attendances a
          join public.events e   on e.id = a.event_id
          join public.profiles p on p.id = a.user_id
          where a.user_id is not null and e.event_date < current_date
          union
          -- un-merged legacy: keyed by hash name
          select null::uuid, a.attendee_label, e.id
          from public.event_attendances a
          join public.events e on e.id = a.event_id
          where a.user_id is null and a.is_legacy = true and e.event_date < current_date
            and coalesce(trim(a.attendee_label), '') <> ''
        ) att
        group by user_id, name
        order by count(distinct event_id) desc, lower(name)
        limit p_limit
      ) t
    ),

    'top_hares', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select p.id as user_id,
               case when p.hash_name is null or trim(p.hash_name) = ''
                 then 'Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
                 else p.hash_name end as name,
               count(*)::integer as value
        from public.event_hares h
        join public.events e   on e.id = h.event_id
        join public.profiles p on p.id = h.user_id
        where e.event_date < current_date
        group by p.id, p.hash_name, p.real_name
        order by count(*) desc, lower(coalesce(p.hash_name, p.real_name, ''))
        limit p_limit
      ) t
    ),

    'top_defilers', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select p.id as user_id,
               case when p.hash_name is null or trim(p.hash_name) = ''
                 then 'Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
                 else p.hash_name end as name,
               sum(r.guests_count)::integer as value
        from public.rsvps r
        join public.events e   on e.id = r.event_id
        join public.profiles p on p.id = r.user_id
        where r.status = 'on_on' and e.event_date < current_date
        group by p.id, p.hash_name, p.real_name
        having sum(r.guests_count) > 0
        order by sum(r.guests_count) desc, lower(coalesce(p.hash_name, p.real_name, ''))
        limit p_limit
      ) t
    )

  ) into result;

  return result;
end;
$$;
grant execute on function public.get_admin_leaderboards(integer) to authenticated;
