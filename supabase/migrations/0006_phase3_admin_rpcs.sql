-- Steel City H3 — Phase 3 supplementary RPCs for the admin members UI
--
-- Two SECURITY DEFINER functions that join profiles with auth.users (and
-- user_roles + rsvps where useful) to give admins everything they need for
-- the members list and member detail pages. Non-admins get a forbidden
-- error.
--
-- Run AFTER 0005_phase3_admin_schema.sql.
-- Idempotent — safe to re-run.

-- ============================================================================
-- get_member_admin_view — the list page
-- ============================================================================

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
    p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  order by lower(coalesce(p.hash_name, p.real_name, '')), p.created_at;
end;
$$;

grant execute on function public.get_member_admin_view() to authenticated;


-- ============================================================================
-- get_member_admin_detail — the edit page
-- ============================================================================

create or replace function public.get_member_admin_detail(p_user_id uuid)
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
    'profile', (select row_to_json(p) from public.profiles p where p.id = p_user_id),
    'email', (select email::text from auth.users where id = p_user_id),
    'is_admin', exists (select 1 from public.user_roles where user_id = p_user_id and role = 'admin'),
    'rsvps', (
      select coalesce(json_agg(rj order by event_date desc), '[]'::json)
      from (
        select
          r.status,
          r.guests_count,
          r.created_at as rsvp_created_at,
          e.id as event_id,
          e.run_number,
          e.title,
          e.event_date,
          e.status as event_status
        from public.rsvps r
        join public.events e on e.id = r.event_id
        where r.user_id = p_user_id
      ) rj
    )
  ) into result;

  return result;
end;
$$;

grant execute on function public.get_member_admin_detail(uuid) to authenticated;


-- ============================================================================
-- count_admins — used by the demote-safeguard logic
-- ============================================================================

create or replace function public.count_admins()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from public.user_roles where role = 'admin';
$$;

grant execute on function public.count_admins() to authenticated;
