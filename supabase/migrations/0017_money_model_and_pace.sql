-- Steel City H3 — single-field money model + meet-up pace fix
--
-- 1. pace: allow NULL (meet-ups have no pace; the create was failing on the
--    NOT NULL constraint).
-- 2. Money model change: the per-head amount is now the TOTAL a head pays
--    (charity is a PORTION of it, not added on top). Each roster row stores one
--    figure — amount_paid (what they actually handed over). We DERIVE:
--       expenses share = amount_per_head - charity_amount_per_head
--       organiser keeps = min(paid, expenses share)
--       to charity      = max(0, paid - expenses share)   (charity events only)
--    so an overpayment flows to charity and it's clear what to keep vs donate.
--
-- Run in the Supabase SQL Editor AFTER 0001–0016. Idempotent.

-- ============================================================================
-- 1. pace nullable
-- ============================================================================
alter table public.events alter column pace drop not null;


-- ============================================================================
-- 2. recalc_event_charity — derive charity from amount_paid + the event rates
-- ============================================================================
-- total_collected = sum(amount_paid) for paid rows (every penny taken)
-- charity_raised  = sum(max(0, amount_paid - expenses_share)) for paid rows,
--                   on charity events only.

create or replace function public.recalc_event_charity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  eid             integer := coalesce(new.event_id, old.event_id);
  v_per_head      numeric(10,2);
  v_charity_head  numeric(10,2);
  v_is_charity    boolean;
  v_expenses      numeric(10,2);
begin
  select amount_per_head, charity_amount_per_head, is_charity_event
    into v_per_head, v_charity_head, v_is_charity
  from public.events where id = eid;

  v_expenses := greatest(0, coalesce(v_per_head, 0) - coalesce(v_charity_head, 0));

  update public.events set
    total_collected = coalesce((
      select sum(amount_paid)
      from public.event_attendances
      where event_id = eid and paid = true), 0),
    charity_raised = case when coalesce(v_is_charity, false) then coalesce((
      select sum(greatest(0, amount_paid - v_expenses))
      from public.event_attendances
      where event_id = eid and paid = true), 0) else 0 end
  where id = eid;

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;


-- ============================================================================
-- 3. populate_attendance_from_rsvps — pre-fill amount_paid = the head total
-- ============================================================================
-- (No longer adds charity on top — the per-head amount IS the total.)

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

  if exists (select 1 from public.event_attendances where event_id = p_event_id) then
    return;
  end if;

  select coalesce(amount_per_head, 0) into v_amount
  from public.events where id = p_event_id;

  perform set_config('app.suppress_audit', 'on', true);

  insert into public.event_attendances (event_id, user_id, amount_paid, charity_amount)
  select p_event_id, r.user_id, v_amount, 0
  from public.rsvps r
  where r.event_id = p_event_id and r.status = 'on_on';

  insert into public.event_attendances
    (event_id, user_id, attendee_label, is_virgin_guest, host_user_id, amount_paid, charity_amount)
  select p_event_id, null, 'Plus-one', true, r.user_id, v_amount, 0
  from public.rsvps r
  cross join generate_series(1, r.guests_count) gs
  where r.event_id = p_event_id and r.status = 'on_on' and r.guests_count > 0;
end;
$$;

grant execute on function public.populate_attendance_from_rsvps(integer) to authenticated;
