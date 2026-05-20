-- Steel City H3 — Phase 4 schema: attendance + payment ground truth
--
-- Turns RSVPs (intent) into attendance (reality). Adds:
--   1. event_attendances table — one row per body that turned up
--   2. events.attendance_finalised_at column (locks the roster for metrics)
--   3. recalc_event_charity()  trigger — events.charity_raised = sum(paid)
--   4. flip_virgin_on_first_attendance() trigger — first attendance un-virgins
--   5. RLS: members read their OWN attendance only; admins do everything
--   6. log_admin_action() updated — suppresses audit noise from the system
--      writes this phase introduces (charity recalcs, virgin flips, the bulk
--      auto-populate) while still logging real admin edits
--   7. populate_attendance_from_rsvps() — idempotent auto-roster from on-on RSVPs
--   8. get_event_attendance_roster()    — admin roster read (display names etc.)
--   9. get_charity_totals()             — public lifetime total + hash count
--
-- Run in the Supabase SQL Editor AFTER 0001–0011. Idempotent — safe to re-run.

-- ============================================================================
-- 1. event_attendances table
-- ============================================================================

create table if not exists public.event_attendances (
  id              uuid          primary key default gen_random_uuid(),
  event_id        integer       not null references public.events(id)   on delete cascade,
  user_id         uuid                   references public.profiles(id) on delete cascade,
  attendee_label  text,
  is_virgin_guest boolean       not null default false,
  host_user_id    uuid                   references public.profiles(id) on delete set null,
  paid            boolean       not null default false,
  amount_paid     numeric(10,2) not null default 0.00,
  marked_paid_by  uuid                   references public.profiles(id) on delete set null,
  marked_paid_at  timestamptz,
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now(),
  -- Either a registered member OR a free-text label — never both null
  constraint attendance_identified
    check (user_id is not null or attendee_label is not null)
);

-- A registered member can only attend a given event once. Plus-ones / walk-ups
-- (user_id null) can have many rows per event, so the index is partial.
create unique index if not exists one_attendance_per_member_per_event
  on public.event_attendances (event_id, user_id) where user_id is not null;

create index if not exists event_attendances_event_idx on public.event_attendances (event_id);
create index if not exists event_attendances_user_idx  on public.event_attendances (user_id);

-- updated_at trigger (reuses set_updated_at from 0001)
drop trigger if exists set_updated_at on public.event_attendances;
create trigger set_updated_at
  before update on public.event_attendances
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 2. events.attendance_finalised_at
-- ============================================================================

alter table public.events add column if not exists attendance_finalised_at timestamptz;


-- ============================================================================
-- 3. recalc_event_charity() — keep events.charity_raised accurate
-- ============================================================================
-- Runs on every attendance write. charity_raised is now computed, never
-- admin-entered. Sums amount_paid for paid rows on the parent event.

create or replace function public.recalc_event_charity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  eid integer := coalesce(new.event_id, old.event_id);
begin
  update public.events
     set charity_raised = coalesce((
       select sum(amount_paid)
       from public.event_attendances
       where event_id = eid and paid = true
     ), 0)
   where id = eid;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists recalc_charity on public.event_attendances;
create trigger recalc_charity
  after insert or update or delete on public.event_attendances
  for each row execute function public.recalc_event_charity();


-- ============================================================================
-- 4. flip_virgin_on_first_attendance()
-- ============================================================================
-- The first time a member gets an attendance row, they're no longer a virgin.
-- Not reversed on delete — once an admin confirms a member came, it sticks.

create or replace function public.flip_virgin_on_first_attendance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is not null then
    update public.profiles
       set is_hash_virgin = false
     where id = new.user_id and is_hash_virgin = true;
  end if;
  return new;
end;
$$;

drop trigger if exists virgin_to_member on public.event_attendances;
create trigger virgin_to_member
  after insert on public.event_attendances
  for each row execute function public.flip_virgin_on_first_attendance();


-- ============================================================================
-- 5. Row-Level Security — event_attendances
-- ============================================================================
-- Members read only their OWN rows (for "My On-Ons" attendance badges).
-- All writes are admin-only. The public never reads this table directly —
-- they see aggregate charity_raised on events (public read) instead.

alter table public.event_attendances enable row level security;

drop policy if exists "ea: admin read all"  on public.event_attendances;
drop policy if exists "ea: member read own" on public.event_attendances;
drop policy if exists "ea: admin insert"    on public.event_attendances;
drop policy if exists "ea: admin update"    on public.event_attendances;
drop policy if exists "ea: admin delete"    on public.event_attendances;

create policy "ea: admin read all"
  on public.event_attendances for select
  using (public.is_admin(auth.uid()));

create policy "ea: member read own"
  on public.event_attendances for select
  using (auth.uid() = user_id);

create policy "ea: admin insert"
  on public.event_attendances for insert
  with check (public.is_admin(auth.uid()));

create policy "ea: admin update"
  on public.event_attendances for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "ea: admin delete"
  on public.event_attendances for delete
  using (public.is_admin(auth.uid()));

grant select, insert, update, delete on public.event_attendances to authenticated;


-- ============================================================================
-- 6. log_admin_action() — keep the audit log signal-rich
-- ============================================================================
-- Phase 4 introduces three sources of *system* writes that would otherwise
-- flood the audit log: the charity recalc (UPDATE events), the virgin flip
-- (UPDATE profiles), and the bulk auto-populate (many INSERT event_attendances
-- in one go). We suppress all three:
--   * a transaction-local GUC `app.suppress_audit` (set by the auto-populate
--     RPC) skips everything during the bulk insert
--   * an events UPDATE that only touches charity_raised/updated_at is skipped
--   * a profiles UPDATE that only touches is_hash_virgin/updated_at is skipped
-- Real admin edits (paid toggles, amount edits, manual roster adds/removes,
-- finalisation, profile edits, event edits) are still logged in full.

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
  -- Bulk system operations set this transaction-local flag to opt out entirely
  if current_setting('app.suppress_audit', true) = 'on' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  -- Only log if the caller is signed-in and an admin
  if actor is null or not public.is_admin(actor) then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  -- Skip system-driven, single-column updates (not real admin edits):
  --   events.charity_raised   — recalculated by recalc_event_charity()
  --   profiles.is_hash_virgin — flipped by flip_virgin_on_first_attendance()
  if tg_table_name = 'events' and tg_op = 'UPDATE'
     and (to_jsonb(new) - 'charity_raised' - 'updated_at')
       = (to_jsonb(old) - 'charity_raised' - 'updated_at') then
    return new;
  end if;
  if tg_table_name = 'profiles' and tg_op = 'UPDATE'
     and (to_jsonb(new) - 'is_hash_virgin' - 'updated_at')
       = (to_jsonb(old) - 'is_hash_virgin' - 'updated_at') then
    return new;
  end if;

  -- Compute the target id as text. For user_roles (composite PK) use user_id;
  -- for other tables the `id` column is canonical. JSON extraction avoids the
  -- mixed-type comparison (integer events.id vs uuid actor) that broke 0005.
  if tg_table_name = 'user_roles' then
    target_text := coalesce(
      to_jsonb(new) ->> 'user_id',
      to_jsonb(old) ->> 'user_id'
    );
  else
    target_text := coalesce(
      to_jsonb(new) ->> 'id',
      to_jsonb(old) ->> 'id'
    );
  end if;

  -- Profiles: skip when admin is editing their OWN row (that's a member action)
  if tg_table_name = 'profiles' and target_text = actor::text then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  -- event_hares: skip member self-actions
  if tg_table_name = 'event_hares' then
    affected_user_id := coalesce(
      to_jsonb(new) ->> 'user_id',
      to_jsonb(old) ->> 'user_id'
    );
    if affected_user_id = actor::text then
      if tg_op = 'INSERT' and (to_jsonb(new) ->> 'volunteered')::boolean = true then
        return new;
      elsif tg_op = 'DELETE' then
        return old;
      end if;
    end if;
  end if;

  -- Build the details payload
  if tg_op = 'INSERT' then
    details_jsonb := jsonb_build_object('new', to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    details_jsonb := jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new));
  else
    details_jsonb := jsonb_build_object('old', to_jsonb(old));
  end if;

  insert into public.admin_actions (actor_id, action, target_type, target_id, details)
  values (
    actor,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    target_text,
    details_jsonb
  );

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

-- Audit attendance writes too (manual adds / paid toggles / removals).
drop trigger if exists log_admin on public.event_attendances;
create trigger log_admin
  after insert or update or delete on public.event_attendances
  for each row execute function public.log_admin_action();


-- ============================================================================
-- 7. populate_attendance_from_rsvps() — the "magic moment" auto-roster
-- ============================================================================
-- Called when an admin first opens the attendance page. Idempotent: only fills
-- the roster if it's empty. One row per on-on member + one row per guest
-- (attributed to the host). maybe / not_this_time RSVPs are NOT auto-added.

create or replace function public.populate_attendance_from_rsvps(p_event_id integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(10,2);
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  -- Idempotent — never double-populate
  if exists (select 1 from public.event_attendances where event_id = p_event_id) then
    return;
  end if;

  select coalesce(amount_per_head, 5.00) into v_amount
  from public.events where id = p_event_id;

  -- This is a bulk system action — keep it out of the audit log
  perform set_config('app.suppress_audit', 'on', true);

  -- One row per on-on member (amount pre-filled, not yet paid)
  insert into public.event_attendances (event_id, user_id, amount_paid)
  select p_event_id, r.user_id, v_amount
  from public.rsvps r
  where r.event_id = p_event_id and r.status = 'on_on';

  -- One row per guest, attributed to the host member
  insert into public.event_attendances
    (event_id, user_id, attendee_label, is_virgin_guest, host_user_id, amount_paid)
  select p_event_id, null, 'Plus-one', true, r.user_id, v_amount
  from public.rsvps r
  cross join generate_series(1, r.guests_count) gs
  where r.event_id = p_event_id and r.status = 'on_on' and r.guests_count > 0;
end;
$$;

grant execute on function public.populate_attendance_from_rsvps(integer) to authenticated;


-- ============================================================================
-- 8. get_event_attendance_roster() — admin roster read
-- ============================================================================
-- Returns the roster with resolved display names, host names, and each
-- member's RSVP status (so the page can show "RSVP'd on-on" / "Walk-up" /
-- "Plus-one of Smutley"). Admin-only.

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
    a.id,
    a.user_id,
    a.attendee_label,
    a.is_virgin_guest,
    a.host_user_id,
    coalesce(nullif(trim(hp.hash_name), ''), hp.real_name) as host_name,
    a.paid,
    a.amount_paid,
    case
      when a.user_id is not null then
        coalesce(nullif(trim(p.hash_name), ''), p.real_name, 'Member')
      else
        coalesce(a.attendee_label, 'Guest')
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


-- ============================================================================
-- 9. get_charity_totals() — public lifetime running total
-- ============================================================================
-- Sum of charity_raised and count of hashes, across FINALISED events only
-- (so in-progress rosters never leak a partial total to the public).

create or replace function public.get_charity_totals()
returns table (
  total      numeric,
  hash_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(charity_raised), 0)::numeric as total,
    count(*)::integer                         as hash_count
  from public.events
  where attendance_finalised_at is not null;
$$;

grant execute on function public.get_charity_totals() to anon, authenticated;
