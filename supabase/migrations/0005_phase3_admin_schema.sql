-- Steel City H3 — Phase 3 schema additions
--
-- Three things:
--   1. admin_actions table: append-only audit log of every admin write
--   2. event_hares table: structured hare assignment + additional_hares_text
--      column on events for visitor / non-member hares
--   3. log_admin_action() trigger function + triggers on events / profiles /
--      user_roles / event_hares — records every admin-driven write
--   4. get_next_third_saturday() RPC for the "Schedule next hash" smart
--      default in the admin UI
--
-- Idempotent — safe to re-run.

-- ============================================================================
-- 1. admin_actions table
-- ============================================================================

create table if not exists public.admin_actions (
  id           uuid        primary key default gen_random_uuid(),
  actor_id     uuid        references public.profiles(id) on delete set null,
  action       text        not null,   -- e.g. 'event.update', 'admin.promote'
  target_type  text        not null,   -- 'events' | 'profiles' | 'user_roles' | 'event_hares'
  target_id    text        not null,
  details      jsonb,
  created_at   timestamptz not null default now()
);

create index if not exists admin_actions_actor_idx   on public.admin_actions (actor_id);
create index if not exists admin_actions_target_idx  on public.admin_actions (target_type, target_id);
create index if not exists admin_actions_created_idx on public.admin_actions (created_at desc);

-- RLS — append-only for admins
alter table public.admin_actions enable row level security;

drop policy if exists "admin_actions: admin read"   on public.admin_actions;
drop policy if exists "admin_actions: admin insert" on public.admin_actions;

create policy "admin_actions: admin read"
  on public.admin_actions for select
  using (public.is_admin(auth.uid()));

create policy "admin_actions: admin insert"
  on public.admin_actions for insert
  with check (public.is_admin(auth.uid()));

-- No UPDATE/DELETE policies — audit log is immutable

grant select, insert on public.admin_actions to authenticated;


-- ============================================================================
-- 2. event_hares table + additional_hares_text column
-- ============================================================================

alter table public.events add column if not exists additional_hares_text text;

create table if not exists public.event_hares (
  id            uuid        primary key default gen_random_uuid(),
  event_id      integer     not null references public.events(id)   on delete cascade,
  user_id       uuid        not null references public.profiles(id) on delete cascade,
  volunteered   boolean     not null default false,
  created_at    timestamptz not null default now(),
  unique (event_id, user_id)
);

create index if not exists event_hares_event_idx on public.event_hares (event_id);
create index if not exists event_hares_user_idx  on public.event_hares (user_id);

alter table public.event_hares enable row level security;

drop policy if exists "event_hares: public read"            on public.event_hares;
drop policy if exists "event_hares: admin insert"           on public.event_hares;
drop policy if exists "event_hares: member self-nominate"   on public.event_hares;
drop policy if exists "event_hares: admin update"           on public.event_hares;
drop policy if exists "event_hares: admin delete"           on public.event_hares;
drop policy if exists "event_hares: member withdraw"        on public.event_hares;

-- Public read (so event detail pages can display hares to anyone)
create policy "event_hares: public read"
  on public.event_hares for select using (true);

-- Admins can insert any hare
create policy "event_hares: admin insert"
  on public.event_hares for insert
  with check (public.is_admin(auth.uid()));

-- Members can self-nominate only on hares_wanted events, only for themselves,
-- and volunteered must be true (to distinguish from admin-assigned rows)
create policy "event_hares: member self-nominate"
  on public.event_hares for insert
  with check (
    auth.uid() = user_id
    and volunteered = true
    and exists (
      select 1 from public.events
       where id = event_hares.event_id
         and status = 'hares_wanted'
    )
  );

-- Admins can update any row (typically to toggle volunteered flag)
create policy "event_hares: admin update"
  on public.event_hares for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- Admins can delete any row
create policy "event_hares: admin delete"
  on public.event_hares for delete
  using (public.is_admin(auth.uid()));

-- Members can withdraw their own volunteer slot for future events
create policy "event_hares: member withdraw"
  on public.event_hares for delete
  using (
    auth.uid() = user_id
    and exists (
      select 1 from public.events
       where id = event_hares.event_id
         and event_date >= current_date
    )
  );

grant select                         on public.event_hares to anon;
grant select, insert, update, delete on public.event_hares to authenticated;


-- ============================================================================
-- 3. Audit trigger function + triggers
-- ============================================================================
-- Records every admin-driven write to events / profiles / user_roles /
-- event_hares into admin_actions. Skips writes that are clearly member
-- self-actions (admin editing own profile, member self-nominating as hare,
-- member withdrawing their own hare slot) because those aren't "admin
-- actions" — they happen via the member-facing UI even if the actor is
-- coincidentally an admin.

create or replace function public.log_admin_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor       uuid := auth.uid();
  details_jsonb jsonb;
  target_text text;
begin
  -- Only log if the caller is signed-in and an admin
  if actor is null or not public.is_admin(actor) then
    return coalesce(new, old);
  end if;

  -- Profiles: skip when admin edits their OWN row (that's a member action)
  if tg_table_name = 'profiles' and coalesce(new.id, old.id) = actor then
    return coalesce(new, old);
  end if;

  -- event_hares INSERT: skip member self-nominations (user_id = actor, volunteered = true)
  if tg_table_name = 'event_hares'
     and tg_op = 'INSERT'
     and new.user_id = actor
     and new.volunteered = true then
    return new;
  end if;

  -- event_hares DELETE: skip member withdrawals (user_id = actor)
  if tg_table_name = 'event_hares'
     and tg_op = 'DELETE'
     and old.user_id = actor then
    return old;
  end if;

  -- Build payload
  if tg_op = 'INSERT' then
    details_jsonb := jsonb_build_object('new', to_jsonb(new));
    target_text := new.id::text;
  elsif tg_op = 'UPDATE' then
    details_jsonb := jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new));
    target_text := new.id::text;
  else  -- DELETE
    details_jsonb := jsonb_build_object('old', to_jsonb(old));
    target_text := old.id::text;
  end if;

  insert into public.admin_actions (actor_id, action, target_type, target_id, details)
  values (
    actor,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    target_text,
    details_jsonb
  );

  return coalesce(new, old);
end;
$$;

-- Attach to events
drop trigger if exists log_admin on public.events;
create trigger log_admin
  after insert or update or delete on public.events
  for each row execute function public.log_admin_action();

-- Attach to profiles
drop trigger if exists log_admin on public.profiles;
create trigger log_admin
  after insert or update or delete on public.profiles
  for each row execute function public.log_admin_action();

-- Attach to user_roles
drop trigger if exists log_admin on public.user_roles;
create trigger log_admin
  after insert or update or delete on public.user_roles
  for each row execute function public.log_admin_action();

-- Attach to event_hares
drop trigger if exists log_admin on public.event_hares;
create trigger log_admin
  after insert or update or delete on public.event_hares
  for each row execute function public.log_admin_action();


-- ============================================================================
-- 4. get_next_third_saturday() RPC
-- ============================================================================
-- Returns the 3rd Saturday of the month after the latest scheduled event.
-- If that's already in the past, keeps walking forward until it finds a
-- future date. Used by the admin UI's "Schedule next hash" smart default.

create or replace function public.get_next_third_saturday()
returns date
language plpgsql
stable
as $$
declare
  latest_event   date;
  candidate_month date;
  first_dow      integer;
  first_saturday date;
  third_saturday date;
begin
  select max(event_date) into latest_event from public.events;

  if latest_event is null then
    candidate_month := date_trunc('month', current_date)::date;
  else
    candidate_month := (date_trunc('month', latest_event) + interval '1 month')::date;
  end if;

  -- Walk forward month by month until we find a 3rd Saturday >= today
  loop
    first_dow      := extract(dow from candidate_month)::integer;  -- 0=Sun, 6=Sat
    first_saturday := candidate_month + ((6 - first_dow + 7) % 7);
    third_saturday := first_saturday + 14;

    if third_saturday >= current_date then
      return third_saturday;
    end if;

    candidate_month := (candidate_month + interval '1 month')::date;
  end loop;
end;
$$;

grant execute on function public.get_next_third_saturday() to authenticated;
