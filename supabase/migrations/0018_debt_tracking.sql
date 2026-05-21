-- Steel City H3 — debt / outstanding-money tracking
--
-- A "debt" is an attendance row on a FINALISED event that isn't marked paid
-- (amount_paid is the figure they owe). Reads only — settling a debt is a
-- normal admin UPDATE of event_attendances.paid (covered by existing RLS).
--   1. get_member_debts(uuid)        — one member's unpaid finalised rows
--   2. get_members_with_debts()      — every member who owes + totals
--   3. get_events_outstanding(int[]) — unpaid count + total per event
--   4. orphaned_debts                — preserves a debt record (by hash name)
--      when a member deletes their account (their attendance rows cascade away)
--
-- Run in the Supabase SQL Editor AFTER 0001–0017. Idempotent.

-- ============================================================================
-- 1. get_member_debts — per-event breakdown for one member
-- ============================================================================
create or replace function public.get_member_debts(p_user_id uuid)
returns table (
  attendance_id uuid,
  event_id      integer,
  run_number    integer,
  title         text,
  event_date    date,
  amount        numeric
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  return query
  select a.id, e.id, e.run_number, e.title, e.event_date, a.amount_paid
  from public.event_attendances a
  join public.events e on e.id = a.event_id
  where a.user_id = p_user_id
    and a.paid = false
    and coalesce(a.amount_paid, 0) > 0
    and e.attendance_finalised_at is not null
  order by e.event_date desc;
end; $$;
grant execute on function public.get_member_debts(uuid) to authenticated;


-- ============================================================================
-- 2. get_members_with_debts — everyone who owes (for the members list tags)
-- ============================================================================
create or replace function public.get_members_with_debts()
returns table (
  user_id     uuid,
  display_name text,
  owed        numeric,
  debt_count  integer
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  return query
  select a.user_id,
         coalesce(nullif(trim(p.hash_name), ''), p.real_name, 'Member'),
         sum(a.amount_paid)::numeric,
         count(*)::integer
  from public.event_attendances a
  join public.events e   on e.id = a.event_id
  join public.profiles p on p.id = a.user_id
  where a.user_id is not null
    and a.paid = false
    and coalesce(a.amount_paid, 0) > 0
    and e.attendance_finalised_at is not null
  group by a.user_id, p.hash_name, p.real_name;
end; $$;
grant execute on function public.get_members_with_debts() to authenticated;


-- ============================================================================
-- 3. get_events_outstanding — unpaid count + total per event (for list tags)
-- ============================================================================
create or replace function public.get_events_outstanding(p_event_ids integer[])
returns table (event_id integer, unpaid_count integer, unpaid_total numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  return query
  select a.event_id, count(*)::integer, sum(a.amount_paid)::numeric
  from public.event_attendances a
  join public.events e on e.id = a.event_id
  where a.event_id = any(p_event_ids)
    and a.paid = false
    and coalesce(a.amount_paid, 0) > 0
    and e.attendance_finalised_at is not null
  group by a.event_id;
end; $$;
grant execute on function public.get_events_outstanding(integer[]) to authenticated;


-- ============================================================================
-- 4. orphaned_debts — survives an account deletion (cascade wipes attendances)
-- ============================================================================
-- Snapshotted by the delete_account Edge Function before it removes the user,
-- so a debt isn't silently lost. Matched back by hash name if they return
-- (the merge flow comes with the legacy-names feature).
create table if not exists public.orphaned_debts (
  id            uuid primary key default gen_random_uuid(),
  hash_name     text,
  real_name     text,
  kennel_name   text,
  owed          numeric(10,2) not null default 0,
  debt_count    integer       not null default 0,
  former_user_id uuid,
  recorded_at   timestamptz   not null default now()
);

alter table public.orphaned_debts enable row level security;
drop policy if exists "orphaned_debts: admin read" on public.orphaned_debts;
create policy "orphaned_debts: admin read"
  on public.orphaned_debts for select
  using (public.is_admin(auth.uid()));
grant select on public.orphaned_debts to authenticated;
