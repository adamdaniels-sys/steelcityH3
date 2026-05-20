-- Steel City H3 — event workflow + charity model rework
--
-- Adds the new event lifecycle statuses, the Hash/Meet-Up event type, the
-- two-part money model (base sub + optional charity donation), a per-event
-- WhatsApp group link, a "written up" flag, the per-attendee charity split,
-- and a member kennel name. Updates the recalc trigger, the auto-populate RPC,
-- and the roster RPC accordingly.
--
-- Run in the Supabase SQL Editor AFTER 0001–0013. Idempotent.
--
-- NOTE: if the editor complains "unsafe use of new value" on the enum, run the
-- two ALTER TYPE lines on their own first, then run the rest.

-- ============================================================================
-- 1. New event lifecycle statuses
-- ============================================================================
-- Pipeline: planning -> hares_wanted -> open -> ready -> completed (+ closed).
-- Labels in the UI: In Planning / Hares Needed / Open / Ready to On-On /
-- Completed / Cancelled.

alter type public.event_status add value if not exists 'planning';
alter type public.event_status add value if not exists 'ready';


-- ============================================================================
-- 2. events table additions
-- ============================================================================

alter table public.events add column if not exists event_type text not null default 'hash';
alter table public.events drop constraint if exists events_event_type_chk;
alter table public.events add constraint events_event_type_chk check (event_type in ('hash', 'meetup'));

alter table public.events add column if not exists is_charity_event      boolean       not null default false;
alter table public.events add column if not exists charity_amount_per_head numeric(10,2) not null default 0;
alter table public.events add column if not exists total_collected       numeric(10,2);
alter table public.events add column if not exists whatsapp_group_link   text;
alter table public.events add column if not exists written_up            boolean       not null default false;


-- ============================================================================
-- 3. event_attendances: per-attendee charity split
-- ============================================================================

alter table public.event_attendances add column if not exists charity_amount numeric(10,2) not null default 0;


-- ============================================================================
-- 4. profiles: kennel name (the hashing group they belong to)
-- ============================================================================

alter table public.profiles add column if not exists kennel_name text;


-- ============================================================================
-- 5. recalc_event_charity — now splits total collected vs charity
-- ============================================================================
-- charity_raised  = sum(charity_amount) for paid rows  (the brag number)
-- total_collected = sum(amount_paid)    for paid rows  (everything taken)

create or replace function public.recalc_event_charity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  eid integer := coalesce(new.event_id, old.event_id);
begin
  update public.events set
    charity_raised = coalesce((
      select sum(charity_amount) from public.event_attendances
      where event_id = eid and paid = true), 0),
    total_collected = coalesce((
      select sum(amount_paid) from public.event_attendances
      where event_id = eid and paid = true), 0)
  where id = eid;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;


-- ============================================================================
-- 6. log_admin_action — also ignore total_collected on system events updates
-- ============================================================================
-- (re-defines the function to add total_collected to the events "system
--  recalc" skip; everything else identical to 0012.)

create or replace function public.log_admin_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor             uuid := auth.uid();
  details_jsonb     jsonb;
  target_text       text;
  affected_user_id  text;
begin
  if current_setting('app.suppress_audit', true) = 'on' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if actor is null or not public.is_admin(actor) then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  -- Skip system-driven, single-purpose updates (not real admin edits):
  if tg_table_name = 'events' and tg_op = 'UPDATE'
     and (to_jsonb(new) - 'charity_raised' - 'total_collected' - 'updated_at')
       = (to_jsonb(old) - 'charity_raised' - 'total_collected' - 'updated_at') then
    return new;
  end if;
  if tg_table_name = 'profiles' and tg_op = 'UPDATE'
     and (to_jsonb(new) - 'is_hash_virgin' - 'updated_at')
       = (to_jsonb(old) - 'is_hash_virgin' - 'updated_at') then
    return new;
  end if;

  if tg_table_name = 'user_roles' then
    target_text := coalesce(to_jsonb(new) ->> 'user_id', to_jsonb(old) ->> 'user_id');
  else
    target_text := coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id');
  end if;

  if tg_table_name = 'profiles' and target_text = actor::text then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_table_name = 'event_hares' then
    affected_user_id := coalesce(to_jsonb(new) ->> 'user_id', to_jsonb(old) ->> 'user_id');
    if affected_user_id = actor::text then
      if tg_op = 'INSERT' and (to_jsonb(new) ->> 'volunteered')::boolean = true then
        return new;
      elsif tg_op = 'DELETE' then
        return old;
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' then
    details_jsonb := jsonb_build_object('new', to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    details_jsonb := jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new));
  else
    details_jsonb := jsonb_build_object('old', to_jsonb(old));
  end if;

  insert into public.admin_actions (actor_id, action, target_type, target_id, details)
  values (actor, tg_table_name || '.' || lower(tg_op), tg_table_name, target_text, details_jsonb);

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;


-- ============================================================================
-- 7. populate_attendance_from_rsvps — pre-fill base + charity split
-- ============================================================================

create or replace function public.populate_attendance_from_rsvps(p_event_id integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount  numeric(10,2);
  v_charity numeric(10,2);
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  if exists (select 1 from public.event_attendances where event_id = p_event_id) then
    return;
  end if;

  select coalesce(amount_per_head, 5.00),
         case when coalesce(is_charity_event, false)
              then coalesce(charity_amount_per_head, 0) else 0 end
    into v_amount, v_charity
  from public.events where id = p_event_id;

  perform set_config('app.suppress_audit', 'on', true);

  insert into public.event_attendances (event_id, user_id, amount_paid, charity_amount)
  select p_event_id, r.user_id, v_amount + v_charity, v_charity
  from public.rsvps r
  where r.event_id = p_event_id and r.status = 'on_on';

  insert into public.event_attendances
    (event_id, user_id, attendee_label, is_virgin_guest, host_user_id, amount_paid, charity_amount)
  select p_event_id, null, 'Plus-one', true, r.user_id, v_amount + v_charity, v_charity
  from public.rsvps r
  cross join generate_series(1, r.guests_count) gs
  where r.event_id = p_event_id and r.status = 'on_on' and r.guests_count > 0;
end;
$$;

grant execute on function public.populate_attendance_from_rsvps(integer) to authenticated;


-- ============================================================================
-- 8. get_event_attendance_roster — include charity_amount
-- ============================================================================

create or replace function public.get_event_attendance_roster(p_event_id integer)
returns table (
  id              uuid,
  user_id         uuid,
  attendee_label  text,
  is_virgin_guest boolean,
  host_user_id    uuid,
  host_name       text,
  paid            boolean,
  amount_paid     numeric,
  charity_amount  numeric,
  display_name    text,
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
    a.id, a.user_id, a.attendee_label, a.is_virgin_guest, a.host_user_id,
    coalesce(nullif(trim(hp.hash_name), ''), hp.real_name) as host_name,
    a.paid, a.amount_paid, a.charity_amount,
    case when a.user_id is not null
      then coalesce(nullif(trim(p.hash_name), ''), p.real_name, 'Member')
      else coalesce(a.attendee_label, 'Guest')
    end as display_name,
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
