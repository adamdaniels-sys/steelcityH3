-- Steel City H3 — Phase 3 enhancement: sync hash_name to auth display_name
--
-- When ANY actor (the user themselves OR an admin editing on their behalf)
-- updates profiles.hash_name, mirror it into auth.users.raw_user_meta_data
-- under the 'display_name' key. Keeps the Supabase Authentication Users
-- dashboard list readable instead of bare email addresses.
--
-- Previously this sync only happened when the user edited via /profile or
-- /complete-profile (which called supabase.auth.updateUser directly). Admin
-- edits via /admin-member.html didn't sync because supabase.auth.updateUser
-- only affects the calling user, not the target.
--
-- Trigger fires from a SECURITY DEFINER function so it can write to
-- auth.users. Idempotent — safe to re-run.

create or replace function public.sync_display_name_to_auth()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Only act if hash_name actually changed
  if new.hash_name is not distinct from old.hash_name then
    return new;
  end if;

  update auth.users
  set raw_user_meta_data = case
    when new.hash_name is not null and trim(new.hash_name) <> '' then
      coalesce(raw_user_meta_data, '{}'::jsonb)
        || jsonb_build_object('display_name', new.hash_name)
    else
      coalesce(raw_user_meta_data, '{}'::jsonb) - 'display_name'
  end
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists sync_display_name on public.profiles;
create trigger sync_display_name
  after update on public.profiles
  for each row execute function public.sync_display_name_to_auth();
