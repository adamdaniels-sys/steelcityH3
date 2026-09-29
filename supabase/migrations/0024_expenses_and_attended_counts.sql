-- Steel City H3 — event expenses, and honest "attended / hared" counts
--
-- Two requests from Queen Myrtle (21 Sep 2026):
--
-- 1. EXPENSES. The money collected is not all profit: sweets, shots and the
--    down-downs at the end are paid for out of it. events.expenses holds what
--    was spent on the day (+ an optional note of what on), so the attendance
--    tab can show what is left after expenses.
--
-- 2. COUNTS. Manage Members had an "RSVPs" column that counted every RSVP row a
--    member had ever made — future hashes, "maybe"s, "not this time"s and the
--    automatic RSVP a hare gets — so it did not match hashes actually attended.
--    get_member_admin_view now also returns:
--      attended_count  distinct hashes (up to today) they actually came to
--      hared_count     distinct hashes (up to today) they laid
--    "Attended" trusts the attendance roster: an attendance row counts; an
--    on-on RSVP only counts for a past hash whose attendance was never taken.
--    Un-merged legacy rows under their hash name count too, so a member who
--    is on record both ways is not double-counted (distinct hashes).
--    "Hared" counts the member picker AND their hash name in the free-text
--    hares field.
--    The Hall of Fame (get_admin_leaderboards) uses the same attendance rule,
--    so the two pages agree.
--
-- Run in the Supabase SQL Editor AFTER 0001-0023. Idempotent.

-- ============================================================================
-- 1. Expenses
-- ============================================================================
alter table public.events add column if not exists expenses numeric(10,2);
alter table public.events add column if not exists expenses_note text;


-- ============================================================================
-- 2a. Helpers — one definition of "attended" and "hared", used by both RPCs
-- ============================================================================

-- Split a free-text hares field ("Smutley & Mudplug, Wops") into names.
create or replace function public.split_hare_names(p_text text)
returns setof text
language sql immutable as $$
  select lower(trim(s))
  from regexp_split_to_table(coalesce(p_text, ''), '\s*[&,]\s*') s
  where trim(s) <> '';
$$;

-- Every (member, past hash) pair where the member attended.
create or replace function public.member_attended_events()
returns table (user_id uuid, event_id integer)
language sql stable security definer set search_path = public as $$
  -- attendance roster rows (incl. legacy rows already merged into the account)
  select a.user_id, a.event_id
  from public.event_attendances a
  join public.events e on e.id = a.event_id
  where a.user_id is not null and e.event_date <= current_date
  union
  -- un-merged legacy rows recorded under the member's hash name
  select p.id, a.event_id
  from public.event_attendances a
  join public.events e   on e.id = a.event_id
  join public.profiles p on coalesce(trim(p.hash_name), '') <> ''
                        and lower(trim(p.hash_name)) = lower(trim(a.attendee_label))
  where a.user_id is null and a.is_legacy = true and e.event_date <= current_date
  union
  -- on-on RSVPs, but only for past hashes where nobody took attendance
  select r.user_id, r.event_id
  from public.rsvps r
  join public.events e on e.id = r.event_id
  where r.status = 'on_on' and e.event_date < current_date
    and not exists (select 1 from public.event_attendances x where x.event_id = r.event_id);
$$;
revoke execute on function public.member_attended_events() from public, anon, authenticated;

-- Every (member, past hash) pair where the member was a hare.
create or replace function public.member_hared_events()
returns table (user_id uuid, event_id integer)
language sql stable security definer set search_path = public as $$
  select h.user_id, h.event_id
  from public.event_hares h
  join public.events e on e.id = h.event_id
  where e.event_date <= current_date
  union
  select p.id, e.id
  from public.events e
  join public.profiles p on coalesce(trim(p.hash_name), '') <> ''
  where e.event_date <= current_date
    and lower(trim(p.hash_name)) in (select public.split_hare_names(e.hares));
$$;
revoke execute on function public.member_hared_events() from public, anon, authenticated;


-- ============================================================================
-- 2b. get_member_admin_view — add attended_count + hared_count
--     Return type changes, so DROP first (42P13 otherwise).
-- ============================================================================
drop function if exists public.get_member_admin_view();

create or replace function public.get_member_admin_view()
returns table (
  id                 uuid,
  hash_name          text,
  real_name          text,
  email              text,
  phone              text,
  is_hash_virgin     boolean,
  newsletter_opt_in  boolean,
  is_admin           boolean,
  rsvp_count         integer,
  attended_count     integer,
  hared_count        integer,
  created_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  return query
  with att as (
    select m.user_id, count(distinct m.event_id)::integer as n
    from public.member_attended_events() m group by m.user_id
  ), hr as (
    select m.user_id, count(distinct m.event_id)::integer as n
    from public.member_hared_events() m group by m.user_id
  )
  select
    p.id,
    p.hash_name,
    p.real_name,
    u.email::text,
    p.phone,
    p.is_hash_virgin,
    p.newsletter_opt_in,
    exists (
      select 1 from public.user_roles ur
       where ur.user_id = p.id and ur.role = 'admin'
    ) as is_admin,
    (select count(*)::integer from public.rsvps r where r.user_id = p.id) as rsvp_count,
    coalesce(att.n, 0) as attended_count,
    coalesce(hr.n, 0)  as hared_count,
    p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  left join att on att.user_id = p.id
  left join hr  on hr.user_id  = p.id
  order by lower(coalesce(p.hash_name, p.real_name, '')), p.created_at;
end;
$$;

grant execute on function public.get_member_admin_view() to authenticated;


-- ============================================================================
-- 2c. get_admin_leaderboards — same "attended" and "hared" rules
--     (top_defilers unchanged from 0020)
-- ============================================================================
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
          select p.id as user_id,
                 case when p.hash_name is null or trim(p.hash_name) = ''
                   then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
                   else p.hash_name end as name,
                 m.event_id
          from public.member_attended_events() m
          join public.profiles p on p.id = m.user_id
          union
          -- legacy names with no matching account, keyed by hash name
          select null::uuid, max(a.attendee_label) over (partition by lower(trim(a.attendee_label))), a.event_id
          from public.event_attendances a
          join public.events e on e.id = a.event_id
          where a.user_id is null and a.is_legacy = true and e.event_date <= current_date
            and coalesce(trim(a.attendee_label), '') <> ''
            and not exists (
              select 1 from public.profiles p
               where lower(trim(p.hash_name)) = lower(trim(a.attendee_label))
            )
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
                 then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
                 else p.hash_name end as name,
               count(distinct m.event_id)::integer as value
        from public.member_hared_events() m
        join public.profiles p on p.id = m.user_id
        group by p.id, p.hash_name, p.real_name
        order by count(distinct m.event_id) desc, lower(coalesce(p.hash_name, p.real_name, ''))
        limit p_limit
      ) t
    ),

    'top_defilers', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select p.id as user_id,
               case when p.hash_name is null or trim(p.hash_name) = ''
                 then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
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


-- ============================================================================
-- Check. EXPECT: two new columns on events, and one row per member with
-- sensible attended / hared numbers (Queen Myrtle and David should read the
-- number of hashes they were actually ticked in on the roster).
-- ============================================================================
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'events'
   and column_name in ('expenses', 'expenses_note');
