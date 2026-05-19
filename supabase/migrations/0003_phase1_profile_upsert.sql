-- Steel City H3 — Phase 1 patch: let users recreate their own profile
--
-- Background: the original 0001 migration only allowed profile rows to be
-- created via the SECURITY DEFINER trigger on auth.users INSERT. That works
-- fine for the happy path (signup → trigger → blank row → user fills it in
-- via UPDATE), but if the profile row is ever deleted (e.g. by an admin
-- cleaning up during testing), the user becomes stuck:
--   * Next sign-in → getProfile returns null → routed to /complete-profile
--   * /complete-profile UPDATE matches 0 rows → silently "succeeds"
--   * User thinks they're done, but DB still has no profile row
--   * Repeat forever
--
-- This patch adds an INSERT policy so the client can UPSERT the profile.
-- Combined with switching complete-profile.html and profile.html from
-- UPDATE to UPSERT, the form can recreate a missing row.
--
-- Idempotent — safe to re-run.

drop policy if exists "profiles: insert own" on public.profiles;
create policy "profiles: insert own"
  on public.profiles for insert
  with check (auth.uid() = id);

grant insert on public.profiles to authenticated;
