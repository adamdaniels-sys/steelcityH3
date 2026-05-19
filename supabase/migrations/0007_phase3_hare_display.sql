-- Steel City H3 — Phase 3 hare display RPCs
--
-- Two SECURITY DEFINER functions used by the public site to render hares
-- with the two-tier display rules (hash name for members who have one,
-- "Hash Virgin Jon" / "Hash Virgin #N" for those who don't, depending on
-- whether the viewer is signed in).
--
-- Run AFTER 0005_phase3_admin_schema.sql.
-- Idempotent.

-- ============================================================================
-- get_event_hares_display — for a single event (event detail page)
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
        'Hash Virgin ' || coalesce(nullif(trim(split_part(n.real_name, ' ', 1)), ''), 'newcomer')
      else
        'Hash Virgin #' || n.virgin_seq
    end as display_name,
    n.volunteered
  from numbered n
  order by n.created_at;
end;
$$;

grant execute on function public.get_event_hares_display(integer) to anon, authenticated;


-- ============================================================================
-- get_events_hares_display — bulk version for the homepage event cards
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
        'Hash Virgin ' || coalesce(nullif(trim(split_part(n.real_name, ' ', 1)), ''), 'newcomer')
      else
        'Hash Virgin #' || n.virgin_seq
    end as display_name,
    n.volunteered
  from numbered n
  order by n.event_id, n.created_at;
end;
$$;

grant execute on function public.get_events_hares_display(integer[]) to anon, authenticated;
