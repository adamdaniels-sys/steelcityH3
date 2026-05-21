-- Steel City H3 — meals + accommodation capture
--
-- Some events now include a sit-down meal (need each attendee's dietary
-- requirements) and some need overnight stays (so admins can block-book
-- hotels). This migration:
--   1. events: has_meal (+ meal_note) and asks_accommodation toggles
--   2. rsvps:  needs_accommodation + dietary_requirements per attendee
--   3. TIGHTENS rsvps SELECT — dietary_requirements is sensitive, so the table
--      can no longer be world-readable.
--
-- Run in the Supabase SQL Editor AFTER 0001–0015. Idempotent.

-- ============================================================================
-- 1. events: meal + accommodation toggles (drive the extra RSVP questions)
-- ============================================================================

alter table public.events add column if not exists has_meal           boolean not null default false;
alter table public.events add column if not exists meal_note          text;
alter table public.events add column if not exists asks_accommodation boolean not null default false;


-- ============================================================================
-- 2. rsvps: per-attendee accommodation need + dietary requirements
-- ============================================================================

alter table public.rsvps add column if not exists needs_accommodation boolean not null default false;
alter table public.rsvps add column if not exists dietary_requirements text;


-- ============================================================================
-- 3. Tighten rsvps SELECT — dietary requirements are sensitive
-- ============================================================================
-- Until now rsvps was world-readable ("public read using(true)"). That was
-- fine for status/guests, but dietary_requirements is special-category data,
-- so we restrict reads to the row's owner or an admin. Public attendee
-- displays use the SECURITY DEFINER RPCs (get_attendee_list,
-- get_event_attendance_counts) which bypass RLS, so they're unaffected. The
-- only direct reads in the app are a member's own rows or an admin reading all.

drop policy if exists "rsvps: public read"        on public.rsvps;
drop policy if exists "rsvps: select own"         on public.rsvps;
drop policy if exists "rsvps: select any (admin)" on public.rsvps;

create policy "rsvps: select own"
  on public.rsvps for select
  using (auth.uid() = user_id);

create policy "rsvps: select any (admin)"
  on public.rsvps for select
  using (public.is_admin(auth.uid()));

-- anon never reads rsvps directly any more (only via the definer RPCs).
-- The grant is harmless without a permissive anon policy, but revoke it for
-- clarity so the intent is explicit.
revoke select on public.rsvps from anon;
