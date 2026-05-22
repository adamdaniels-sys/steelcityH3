-- Steel City H3 - CLEAR TEST DATA
--
-- Wipes every event, RSVP, roster row, hare, debt snapshot and the admin audit
-- log so the site is a blank slate for the real data. It does NOT delete any
-- member accounts (see the OPTIONAL block at the bottom for that).
--
-- Order: 1) run this   2) run seed_real_data.sql
-- Run in the Supabase SQL Editor (Dashboard -> SQL Editor -> New query).

begin;
set local app.suppress_audit = 'on';   -- keep these deletes out of the audit log

delete from public.event_attendances;
delete from public.event_hares;
delete from public.rsvps;

-- debt snapshots — table only exists once migration 0018 has run
do $$ begin
  if to_regclass('public.orphaned_debts') is not null then
    delete from public.orphaned_debts;
  end if;
end $$;

delete from public.events;

-- admin audit log: every row so far is a test action — clear for a clean start
delete from public.admin_actions;

-- send the events id counter back to the start
select setval(pg_get_serial_sequence('public.events','id'), 1, false);

commit;


-- ============================================================================
-- OPTIONAL - remove the test member accounts
-- ============================================================================
-- Everything above keeps ALL accounts. To also clear the test sign-ups while
-- keeping the 3 admins + "Adam el Serf", the safest route is the dashboard:
--
--   Authentication -> Users -> tick the test accounts -> Delete
--   (deleting a user there cascades to their profile automatically)
--
-- ...because you can see the names there. If you'd rather do it in SQL, edit the
-- keep-list below and run it. It auto-keeps anyone with the admin role, plus any
-- email you list (so double-check your admins really have the admin role first):
--
-- delete from auth.users u
-- where not exists (
--         select 1 from public.user_roles ur
--         where ur.user_id = u.id and ur.role = 'admin')   -- keeps the 3 admins
--   and u.email not in (
--         'adamdaniels@gmail.com'      -- <- replace with Adam el Serf's email; add more lines as needed
--       );
