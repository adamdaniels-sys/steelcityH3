-- Steel City H3 — Phase 1 seed events
--
-- Migrates the events currently hardcoded in index.html (Up Next + Past Hashes)
-- and event.html (the EVENTS const) into the events table.
--
-- Run this AFTER 0001_phase1_schema.sql.
--
-- Idempotent: re-running upserts the same rows.
--
-- Note: events #1–12 aren't in the existing repo (the website launched after
-- the first year of hashing), so they're not seeded here. Admins can backfill
-- them via the Supabase Table Editor or the Phase 3 admin UI when it ships.

insert into public.events (
  id, run_number, title, event_date, start_time,
  location_summary, location_full, hares, pace, status,
  description, distance_miles, on_on_pub,
  scribe_report, scribe_report_by, charity_raised, amount_per_head
) values

  -- ==========================================================================
  -- PAST HASHES (status = 'completed')
  -- ==========================================================================

  (13, 13, 'February Hash — Loxley Lash',
    '2026-02-14', '12:00',
    'Derbyshire Dales', 'Loxley Valley, Sheffield',
    'Bigfoot', 'Walk or run', 'completed',
    'Lost in Loxley. Found by smell.',
    5.0, 'The Plough, Low Bradfield',
    $report$A masterclass in trail subterfuge from Compass-Free Carol's stand-in (Bigfoot, hare). We added at least a mile to the planned route.

We found the on-on by smell alone — the wind was helpfully blowing pub kitchen extractor straight at us by mile 4.

Closing pints at The Plough. Excellent pies.$report$,
    'Two-Pints Tony', null, 5.00),

  (14, 14, 'March Hash — Mosborough Meander',
    '2026-03-21', '12:00',
    'Sheffield', 'Mosborough, Sheffield',
    'Smutley', 'Walk', 'completed',
    'A surprisingly civilised hash through the old village.',
    4.0, 'The George, Mosborough',
    $report$Surprisingly civilised. Three pairs of new boots, a clear sky, and a pub with a fire still going for some reason in March.

Trail was solid — Smutley had clearly done a recce. One check near the church which we solved in under a minute (a club first).

Closing pint at The George. Mick stayed for another. Two of them.$report$,
    'Lost-Again Liz', null, 5.00),

  (15, 15, 'Gangs of Sheffield',
    '2026-04-10', '17:00',
    'Sheffield centre', 'The Old Queen''s Head, 40 Pond Hill, Sheffield S1 2BG',
    'Smutley', 'Walk', 'completed',
    '1st Anniversary Day 1 — Peaky Blinders, Little Chicago, £282.15 raised for St Luke''s.',
    3.0, 'Pub crawl finale — room reserved ''til 1 am',
    $report$What a turnout. The Old Queen's Head was already filling up by 5pm — Peaky Blinders hats and waistcoats everywhere, three flat caps for every two heads.

Guided tour of Little Chicago by author John Stokes and pub historian Dave Pickersgill — 20 places, all gone within a week. Heard stories that would curl your moustache.

Pub crawl across the Little Chicago area, ending at our reserved room. Real ale (CAMRA cards accepted), food until 9, music 'til 1.

Charity bucket: <b>£282.15 for St Luke's Hospice</b>. Beat that next year. (We will.)$report$,
    'Smutley', 282.15, 5.00),

  (16, 16, 'The 1st Anniversary Hash',
    '2026-04-11', '12:00',
    'Sheffield centre', 'Banker''s Draft (Wetherspoons), Market Place, Sheffield',
    'Bigfoot & Jake the Peg', 'Walk or run', 'completed',
    '1st Anniversary Day 2 — the main event.',
    5.0, 'Pub #4 — pizza, real ale, music',
    $report$Kicked off at noon at the Banker's Draft. About 25 of us — biggest hash to date. Trail laid by yours truly and Jake the Peg, across the city to Pub #1 for chip butties at 1.30.

Runners peeled off at 2.30 for Pub #2 via the Wicker. Walkers took the direct line to Pub #3. We all met up at Pub #4 by 5.

Real ale through to closing. Pizza. Music. Stayed 'til the bus stopped at 23:52. Walked home. Probably.$report$,
    'Bigfoot', null, 5.00),

  (17, 17, 'Bertie''s Been Framed',
    '2026-04-12', '11:00',
    'Sheffield centre', 'City Hall, City Square, Sheffield',
    'Cock-a-Tool', 'Walk', 'completed',
    '1st Anniversary Day 3 — the hang(ing)-over hash.',
    3.0, 'Hair-of-the-dog at the city centre',
    $report$The hang(ing)-over hash. 11 am City Hall start, hare: Cock-a-Tool. About a dozen of us, varying shades of green, all clutching takeaway coffees.

The trail was mercifully short and forgiving — Cock-a-Tool had taken pity on us. A gentle wander home through a bleary Sheffield, with one check that no-one was sober enough to solve. We agreed to just keep walking.

Solved the framing of Bertie. Possibly. Closing pint at City Hall. Bring on the rest of Year 1.$report$,
    'Sister Scribe', null, 5.00),

  -- ==========================================================================
  -- UPCOMING HASHES
  -- ==========================================================================

  (18, 18, 'June Hash',
    '2026-06-20', '12:00',
    'Sheffield centre — TBC', null,
    'TBC', 'Walk or run', 'open',
    'Sheffield month! Start point and exact pub announced on the Wednesday before by email.',
    null, null,
    null, null, null, 5.00),

  (19, 19, 'July Hash',
    '2026-07-18', '12:00',
    'Derbyshire Dales', null,
    'Volunteers wanted!', 'Walk or run', 'hares_wanted',
    'Dales month. Hares wanted — first time haring? We''ll help. Reply to Smutley.',
    null, null,
    null, null, null, 5.00),

  (20, 20, 'August Hash',
    '2026-08-15', '12:00',
    'Sheffield centre — TBC', null,
    'TBC', 'Walk or run', 'open',
    'Mid-summer Sheffield hash. Probably warm; bring water and a hat.',
    null, null,
    null, null, null, 5.00),

  (21, 21, 'September Hash',
    '2026-09-19', '12:00',
    'Derbyshire Dales', null,
    'TBC', 'Walk or run', 'open',
    'Last chance for shorts. Dales walk and a pint of something seasonal.',
    null, null,
    null, null, null, 5.00)

on conflict (id) do update set
  run_number       = excluded.run_number,
  title            = excluded.title,
  event_date       = excluded.event_date,
  start_time       = excluded.start_time,
  location_summary = excluded.location_summary,
  location_full    = excluded.location_full,
  hares            = excluded.hares,
  pace             = excluded.pace,
  status           = excluded.status,
  description      = excluded.description,
  distance_miles   = excluded.distance_miles,
  on_on_pub        = excluded.on_on_pub,
  scribe_report    = excluded.scribe_report,
  scribe_report_by = excluded.scribe_report_by,
  charity_raised   = excluded.charity_raised,
  amount_per_head  = excluded.amount_per_head;

-- Keep the identity sequence ahead of the seeded ids so new admin-created events
-- get unique ones. Without this, the next inserted row would try to use id=1.
select setval(
  pg_get_serial_sequence('public.events', 'id'),
  (select coalesce(max(id), 1) from public.events)
);
