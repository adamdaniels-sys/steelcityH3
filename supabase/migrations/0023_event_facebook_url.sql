-- Steel City H3 — per-event Facebook link
--
-- A link to the hash's Facebook post / photo album. Shows as a "Photos on
-- Facebook" button on the event page, so the on-site 3-photo pile can point at
-- the fuller album and the site + Facebook stay cross-linked.
--
-- Run in the Supabase SQL Editor AFTER 0001-0022. Idempotent.

alter table public.events add column if not exists facebook_url text;
