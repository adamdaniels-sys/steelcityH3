-- Steel City H3 — Phase 2 schema additions
--
-- Adds the rsvps table + supporting RLS, indexes, and the get_attendee_list
-- RPC function that handles the two-tier display rules from the Phase 2 brief:
--   * Members with a hash_name      → shown as the hash name to everyone
--   * Members without (hash virgins)→ "Hash Virgin {first_name}" to signed-in
--                                     viewers, "Hash Virgin #N" to anonymous
--                                     visitors (numbered per-event by RSVP
--                                     order so each anon visitor sees the
--                                     same numbers)
--
-- Plus-one virgins (guests brought by a host) are counts only — they never
-- appear in get_attendee_list as separate rows. They show up inline on the
-- host's row, e.g. "Smutley + 2 hash virgins".
--
-- Idempotent — safe to re-run.

-- ============================================================================
-- 1. rsvp_status enum
-- ============================================================================

do $$ begin
  create type public.rsvp_status as enum ('on_on', 'maybe', 'not_this_time');
exception when duplicate_object then null; end $$;


-- ============================================================================
-- 2. rsvps table
-- ============================================================================

create table if not exists public.rsvps (
  id            uuid                 primary key default gen_random_uuid(),
  user_id       uuid                 not null references public.profiles(id) on delete cascade,
  event_id      integer              not null references public.events(id)   on delete cascade,
  status        public.rsvp_status   not null,
  guests_count  integer              not null default 0
                                       check (guests_count >= 0 and guests_count <= 20),
  created_at    timestamptz          not null default now(),
  updated_at    timestamptz          not null default now(),
  unique (user_id, event_id)
);

-- updated_at trigger (re-uses the function defined in 0001)
drop trigger if exists set_updated_at on public.rsvps;
create trigger set_updated_at
  before update on public.rsvps
  for each row execute function public.set_updated_at();

-- Indexes for the queries we run frequently
create index if not exists rsvps_event_status_idx on public.rsvps (event_id, status);
create index if not exists rsvps_user_idx          on public.rsvps (user_id);


-- ============================================================================
-- 3. Row-Level Security — rsvps
-- ============================================================================
-- Read: public (the attendee list is visible to anonymous visitors)
-- Write: users on their own rows; admins on any row

alter table public.rsvps enable row level security;

drop policy if exists "rsvps: public read"        on public.rsvps;
drop policy if exists "rsvps: insert own"         on public.rsvps;
drop policy if exists "rsvps: insert any (admin)" on public.rsvps;
drop policy if exists "rsvps: update own"         on public.rsvps;
drop policy if exists "rsvps: update any (admin)" on public.rsvps;
drop policy if exists "rsvps: delete own"         on public.rsvps;
drop policy if exists "rsvps: delete any (admin)" on public.rsvps;

create policy "rsvps: public read"
  on public.rsvps for select using (true);

create policy "rsvps: insert own"
  on public.rsvps for insert
  with check (auth.uid() = user_id);

create policy "rsvps: insert any (admin)"
  on public.rsvps for insert
  with check (public.is_admin(auth.uid()));

create policy "rsvps: update own"
  on public.rsvps for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "rsvps: update any (admin)"
  on public.rsvps for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "rsvps: delete own"
  on public.rsvps for delete
  using (auth.uid() = user_id);

create policy "rsvps: delete any (admin)"
  on public.rsvps for delete
  using (public.is_admin(auth.uid()));

grant select, insert, update, delete on public.rsvps to authenticated;
grant select                         on public.rsvps to anon;


-- ============================================================================
-- 4. get_attendee_list RPC
-- ============================================================================
-- SECURITY DEFINER so it can read profiles regardless of caller's RLS scope
-- (profiles select is normally own-only or admin-only). The function itself
-- only ever returns the safe, curated display_name — never raw real_name or
-- phone.

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
        'Hash Virgin ' ||
        coalesce(nullif(trim(split_part(n.o_real_name, ' ', 1)), ''), 'newcomer')
      else
        'Hash Virgin #' || n.o_virgin_seq
    end as display_name,
    n.o_created_at   as rsvp_created_at
  from numbered n
  order by n.o_created_at;
end;
$$;

grant execute on function public.get_attendee_list(integer) to anon, authenticated;


-- ============================================================================
-- 5. get_event_attendance_counts RPC
-- ============================================================================
-- Used by the homepage event cards to show "15 on-on · 4 maybe". The counts
-- include each host's guests_count, not just the number of RSVPs.
-- Takes an array of event ids so the homepage can fetch all upcoming events
-- in one round-trip.

create or replace function public.get_event_attendance_counts(p_event_ids integer[])
returns table (
  event_id     integer,
  on_on_total  integer,
  maybe_total  integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.event_id,
    coalesce(sum(case when r.status = 'on_on' then 1 + r.guests_count end), 0)::integer as on_on_total,
    coalesce(sum(case when r.status = 'maybe' then 1 + r.guests_count end), 0)::integer as maybe_total
  from public.rsvps r
  where r.event_id = any(p_event_ids)
  group by r.event_id;
$$;

grant execute on function public.get_event_attendance_counts(integer[]) to anon, authenticated;
