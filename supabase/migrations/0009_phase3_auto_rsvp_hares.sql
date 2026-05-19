-- Steel City H3 — Phase 3 enhancement: auto-RSVP hares to on_on
--
-- When a member is added to event_hares (either by admin assignment OR by
-- self-nomination), they implicitly committed to coming — they're haring.
-- This trigger UPSERTS their rsvps row to status='on_on':
--
--   * No existing RSVP  → INSERT (status='on_on', guests_count=0)
--   * Existing 'maybe' / 'not_this_time' → UPDATE status to 'on_on'
--     (preserves guests_count — they might already be bringing virgins)
--   * Existing 'on_on'  → no change
--
-- Removing them from event_hares does NOT down-grade the RSVP — they might
-- still want to come even if they're not haring any more. That's a manual
-- step.
--
-- Idempotent — safe to re-run.

create or replace function public.auto_rsvp_on_hare_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.rsvps (user_id, event_id, status, guests_count)
  values (new.user_id, new.event_id, 'on_on', 0)
  on conflict (user_id, event_id)
  do update
    set status = 'on_on',
        updated_at = now()
    where rsvps.status is distinct from 'on_on';

  return new;
end;
$$;

drop trigger if exists auto_rsvp on public.event_hares;
create trigger auto_rsvp
  after insert on public.event_hares
  for each row execute function public.auto_rsvp_on_hare_insert();
