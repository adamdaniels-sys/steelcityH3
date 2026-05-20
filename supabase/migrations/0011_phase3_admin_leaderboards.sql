-- Steel City H3 — Phase 3 enhancement: admin dashboard leaderboards
--
-- One SECURITY DEFINER RPC that returns three "hall of fame" league tables
-- for the admin dashboard:
--   * top_attenders — most hashes hounded (on-on RSVPs to PAST events)
--   * top_hares     — most trails laid   (hare slots on PAST events)
--   * top_defilers  — most hash virgins brought as plus-ones ("Head Defiler")
--
-- "Past" = the event date is strictly before today, so upcoming RSVPs / hare
-- assignments don't inflate the standings. Members without a hash name show
-- as "Hash Virgin {first name}" — the same display rule get_attendee_list uses
-- for signed-in viewers. Admin-only: raises 'forbidden' for everyone else.
--
-- Run AFTER 0005 / 0006. Idempotent — safe to re-run.

create or replace function public.get_admin_leaderboards(p_limit integer default 5)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result json;
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  select json_build_object(

    -- Most hashes hounded: on-on RSVPs to events that have happened
    'top_attenders', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select
          p.id as user_id,
          case
            when p.hash_name is null or trim(p.hash_name) = '' then
              'Hash Virgin ' ||
              coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
            else p.hash_name
          end as name,
          count(*)::integer as value
        from public.rsvps r
        join public.events e   on e.id = r.event_id
        join public.profiles p on p.id = r.user_id
        where r.status = 'on_on'
          and e.event_date < current_date
        group by p.id, p.hash_name, p.real_name
        order by count(*) desc, lower(coalesce(p.hash_name, p.real_name, ''))
        limit p_limit
      ) t
    ),

    -- Most trails laid: hare slots on events that have happened
    'top_hares', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select
          p.id as user_id,
          case
            when p.hash_name is null or trim(p.hash_name) = '' then
              'Hash Virgin ' ||
              coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
            else p.hash_name
          end as name,
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

    -- Head Defiler: most hash virgins brought as plus-ones to past hashes
    'top_defilers', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select
          p.id as user_id,
          case
            when p.hash_name is null or trim(p.hash_name) = '' then
              'Hash Virgin ' ||
              coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
            else p.hash_name
          end as name,
          sum(r.guests_count)::integer as value
        from public.rsvps r
        join public.events e   on e.id = r.event_id
        join public.profiles p on p.id = r.user_id
        where r.status = 'on_on'
          and e.event_date < current_date
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
