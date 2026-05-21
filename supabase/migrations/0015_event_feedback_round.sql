-- Steel City H3 — event workflow feedback round (post-test-pass)
--
-- Adds, from Adam's test-pass notes:
--   1. rsvps.via_hare       — provenance flag so removing a hare cleans up the
--                             RSVP it auto-created (but never a member's own RSVP)
--   2. events.charity_name  — the charity isn't always St Luke's
--   3. event_attendances.attendee_kennel — record a walk-up's home kennel
--   4. get_event_attendance_roster — return attendee_kennel (DROP+recreate:
--      adding an output column changes the return type, which CREATE OR REPLACE
--      can't do — same gotcha as 0014).
--
-- Run in the Supabase SQL Editor AFTER 0001–0014. Idempotent.

-- ============================================================================
-- 1. rsvps.via_hare — was this RSVP created automatically by a hare-add?
-- ============================================================================
-- The auto_rsvp trigger (0009) upserts a hare into on_on. Until now, removing
-- the hare left a phantom "coming" RSVP behind. We now tag RSVPs the trigger
-- *creates from scratch* as via_hare=true; a member who already had their own
-- RSVP keeps via_hare=false and is never auto-removed.

alter table public.rsvps add column if not exists via_hare boolean not null default false;

-- Rewrite the insert trigger: stamp via_hare=true only on a fresh insert.
-- On conflict (the member already had an RSVP) we still upgrade them to on_on
-- but leave via_hare untouched — that RSVP is theirs, not ours.
create or replace function public.auto_rsvp_on_hare_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.rsvps (user_id, event_id, status, guests_count, via_hare)
  values (new.user_id, new.event_id, 'on_on', 0, true)
  on conflict (user_id, event_id)
  do update
    set status = 'on_on',
        updated_at = now()
    where rsvps.status is distinct from 'on_on';

  return new;
end;
$$;

-- New: when a hare is removed, delete the RSVP *only* if we created it.
create or replace function public.auto_rsvp_on_hare_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.rsvps
  where user_id = old.user_id
    and event_id = old.event_id
    and via_hare = true;
  return old;
end;
$$;

drop trigger if exists auto_rsvp_delete on public.event_hares;
create trigger auto_rsvp_delete
  after delete on public.event_hares
  for each row execute function public.auto_rsvp_on_hare_delete();


-- ============================================================================
-- 2. events.charity_name — the charity isn't always St Luke's
-- ============================================================================

alter table public.events add column if not exists charity_name text;

-- Default existing charity events to St Luke's (the historical recipient) so
-- public badges keep reading sensibly until each is edited.
update public.events
   set charity_name = 'St Luke''s Hospice'
 where charity_name is null
   and (is_charity_event = true or coalesce(charity_raised, 0) > 0);


-- ============================================================================
-- 3. event_attendances.attendee_kennel — a walk-up's home hashing group
-- ============================================================================

alter table public.event_attendances add column if not exists attendee_kennel text;


-- ============================================================================
-- 4. get_event_attendance_roster — include attendee_kennel
-- ============================================================================
-- DROP first: adding an output column changes the return type (42P13).

drop function if exists public.get_event_attendance_roster(integer);

create or replace function public.get_event_attendance_roster(p_event_id integer)
returns table (
  id              uuid,
  user_id         uuid,
  attendee_label  text,
  attendee_kennel text,
  is_virgin_guest boolean,
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
    a.id, a.user_id, a.attendee_label, a.attendee_kennel, a.is_virgin_guest, a.host_user_id,
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
