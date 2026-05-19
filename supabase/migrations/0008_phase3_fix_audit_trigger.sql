-- Steel City H3 — Phase 3 audit trigger fix
--
-- The original log_admin_action() function (in 0005) referenced new.id / old.id
-- directly in branches gated by tg_table_name. Even though those branches are
-- guarded by short-circuit AND, plpgsql does cross-branch type analysis that
-- can fail when the trigger fires on a table whose `id` column type doesn't
-- match other types referenced in the same function body (here: events.id is
-- integer, actor is uuid).
--
-- Symptom Adam hit when saving an event:
--   "operator does not exist: integer = uuid"
--
-- Fix: extract row ids via (to_jsonb(new) ->> 'id') which always returns text,
-- so the comparisons never mix integer with uuid. Also switch the trigger's
-- return to an explicit CASE on tg_op instead of coalesce(new, old) for
-- clarity.
--
-- Idempotent — safe to re-run; replaces the function in place.

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
  -- Only log if the caller is signed-in and an admin
  if actor is null or not public.is_admin(actor) then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  -- Compute the target id as text. For user_roles (composite PK) use user_id;
  -- for other tables the `id` column is canonical. JSON extraction avoids the
  -- mixed-type comparison that broke the original function.
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
