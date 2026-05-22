-- Steel City H3 — "SCH3 Hash Virgin" rename + free hares/virgins on hashes
--
-- 1. Terminology: every server-generated "Hash Virgin {name}" / "Hash Virgin #N"
--    label becomes "SCH3 Hash Virgin …". Only the display string changes — same
--    signatures, so CREATE OR REPLACE (no DROP needed).
--    Functions touched: get_attendee_list, get_event_hares_display,
--    get_events_hares_display, get_admin_leaderboards.
--
-- 2. Payment rule: on a HASH, hares and SCH3 Hash Virgins (anyone attending their
--    first Steel City hash — even seasoned hashers from other kennels) pay £0.
--    populate_attendance_from_rsvps now pre-fills £0 for those rows. Brought
--    plus-ones are first-time guests, so they're free too. Admins can still
--    override any amount on the roster.
--
-- Run in the Supabase SQL Editor AFTER 0001–0019. Idempotent.

-- ============================================================================
-- 1a. get_attendee_list  (public "Who's cumming" list)
-- ============================================================================
create or replace function public.get_attendee_list(p_event_id integer)
returns table (
  user_id          uuid,
  status           text,
  guests_count     integer,
  display_name     text,
  rsvp_created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  is_authed boolean := auth.uid() is not null;
begin
  return query
  with ordered as (
    select
      r.user_id            as o_user_id,
      r.status::text       as o_status,
      r.guests_count       as o_guests_count,
      r.created_at         as o_created_at,
      p.hash_name          as o_hash_name,
      p.real_name          as o_real_name,
      (p.hash_name is null or trim(p.hash_name) = '') as o_is_virgin
    from public.rsvps r
    join public.profiles p on p.id = r.user_id
    where r.event_id = p_event_id
      and r.status in ('on_on', 'maybe')
  ),
  numbered as (
    select
      o.*,
      case
        when o.o_is_virgin then row_number() over (
          partition by o.o_is_virgin
          order by o.o_created_at
        )
      end as o_virgin_seq
    from ordered o
  )
  select
    n.o_user_id      as user_id,
    n.o_status       as status,
    n.o_guests_count as guests_count,
    case
      when not n.o_is_virgin then n.o_hash_name
      when is_authed then
        'SCH3 Hash Virgin ' ||
        coalesce(nullif(trim(split_part(n.o_real_name, ' ', 1)), ''), 'newcomer')
      else
        'SCH3 Hash Virgin #' || n.o_virgin_seq
    end as display_name,
    n.o_created_at   as rsvp_created_at
  from numbered n
  order by n.o_created_at;
end;
$$;

grant execute on function public.get_attendee_list(integer) to anon, authenticated;


-- ============================================================================
-- 1b. get_event_hares_display  (single event)
-- ============================================================================
create or replace function public.get_event_hares_display(p_event_id integer)
returns table (
  user_id      uuid,
  display_name text,
  volunteered  boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  is_authed boolean := auth.uid() is not null;
begin
  return query
  with numbered as (
    select
      eh.user_id,
      eh.volunteered,
      eh.created_at,
      p.hash_name,
      p.real_name,
      (p.hash_name is null or trim(p.hash_name) = '') as is_virgin,
      row_number() over (
        partition by (p.hash_name is null or trim(p.hash_name) = '')
        order by eh.created_at
      ) as virgin_seq
    from public.event_hares eh
    join public.profiles p on p.id = eh.user_id
    where eh.event_id = p_event_id
  )
  select
    n.user_id,
    case
      when not n.is_virgin then n.hash_name
      when is_authed then
        'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(n.real_name, ' ', 1)), ''), 'newcomer')
      else
        'SCH3 Hash Virgin #' || n.virgin_seq
    end as display_name,
    n.volunteered
  from numbered n
  order by n.created_at;
end;
$$;

grant execute on function public.get_event_hares_display(integer) to anon, authenticated;


-- ============================================================================
-- 1c. get_events_hares_display  (bulk, homepage cards)
-- ============================================================================
create or replace function public.get_events_hares_display(p_event_ids integer[])
returns table (
  event_id     integer,
  user_id      uuid,
  display_name text,
  volunteered  boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  is_authed boolean := auth.uid() is not null;
begin
  return query
  with numbered as (
    select
      eh.event_id,
      eh.user_id,
      eh.volunteered,
      eh.created_at,
      p.hash_name,
      p.real_name,
      (p.hash_name is null or trim(p.hash_name) = '') as is_virgin,
      row_number() over (
        partition by eh.event_id, (p.hash_name is null or trim(p.hash_name) = '')
        order by eh.created_at
      ) as virgin_seq
    from public.event_hares eh
    join public.profiles p on p.id = eh.user_id
    where eh.event_id = any(p_event_ids)
  )
  select
    n.event_id,
    n.user_id,
    case
      when not n.is_virgin then n.hash_name
      when is_authed then
        'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(n.real_name, ' ', 1)), ''), 'newcomer')
      else
        'SCH3 Hash Virgin #' || n.virgin_seq
    end as display_name,
    n.volunteered
  from numbered n
  order by n.event_id, n.created_at;
end;
$$;

grant execute on function public.get_events_hares_display(integer[]) to anon, authenticated;


-- ============================================================================
-- 1d. get_admin_leaderboards  (Hall of Fame)
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
          -- members: on-on RSVPs to past events
          select p.id as user_id,
                 case when p.hash_name is null or trim(p.hash_name) = ''
                   then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
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
                   then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
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
                 then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
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
-- 2. populate_attendance_from_rsvps — hares + SCH3 Hash Virgins free on a hash
-- ============================================================================
create or replace function public.populate_attendance_from_rsvps(p_event_id integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount  numeric(10,2);
  v_is_hash boolean;
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  if exists (select 1 from public.event_attendances where event_id = p_event_id) then
    return;
  end if;

  select coalesce(amount_per_head, 0), (coalesce(event_type, 'hash') = 'hash')
    into v_amount, v_is_hash
  from public.events where id = p_event_id;

  perform set_config('app.suppress_audit', 'on', true);

  -- Members. On a hash, hares and SCH3 Hash Virgins (their first SCH3 hash) pay £0.
  insert into public.event_attendances (event_id, user_id, amount_paid, charity_amount)
  select p_event_id, r.user_id,
         case
           when v_is_hash and (
                  exists (
                    select 1 from public.event_hares h
                    where h.event_id = p_event_id and h.user_id = r.user_id
                  )
                  or coalesce(pr.is_hash_virgin, false)
                )
             then 0
           else v_amount
         end,
         0
  from public.rsvps r
  join public.profiles pr on pr.id = r.user_id
  where r.event_id = p_event_id and r.status = 'on_on';

  -- Plus-ones are brought hash virgins (first SCH3 hash) — free on a hash.
  insert into public.event_attendances
    (event_id, user_id, attendee_label, is_virgin_guest, host_user_id, amount_paid, charity_amount)
  select p_event_id, null, 'Plus-one', true, r.user_id,
         case when v_is_hash then 0 else v_amount end, 0
  from public.rsvps r
  cross join generate_series(1, r.guests_count) gs
  where r.event_id = p_event_id and r.status = 'on_on' and r.guests_count > 0;
end;
$$;

grant execute on function public.populate_attendance_from_rsvps(integer) to authenticated;
