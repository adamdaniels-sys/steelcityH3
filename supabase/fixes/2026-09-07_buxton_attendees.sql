-- One-off data import -- 2026-09-07. NOT a schema migration.
--
-- Adds the 77 attendees of the Buxton joint hash weekend (event 15, run #19,
-- 27 June 2026, Palace Hotel & Spa Buxton -- the club's largest event) as
-- LEGACY attendees.
--
-- Source: "Whos Cumming.xlsx" from Queen Myrtle. The raw list is kept beside
-- this file as 2026-09-07_whos-cumming-77-names.txt.
--
-- WHY LEGACY: uptake of site accounts has been slow, so most of these people
-- have none. Legacy rows (user_id null, is_legacy true) count in the metrics
-- and Hall of Fame, cost GBP 0 and are marked paid, so nobody shows as owing
-- money for a residential weekend that was settled off-site.
--
-- NAMES ARE IMPORTED VERBATIM -- all 77 rows, exactly as the spreadsheet has
-- them. Two entries look like data errors but are NOT, and must stay as-is:
--   . "Nosejob: nj" is TWO separate people sharing a hash name, recorded on
--     one row. Confirmed by Adam. Left as written rather than guessed apart --
--     splitting it needs someone who knows which two people they are.
--   . "Walkie Talkie" and "Walky Talky" are both kept. They may or may not be
--     the same person; the club can tell, and a spare row takes seconds to
--     delete in the admin UI, whereas a person dropped here is invisible.
-- The general rule: import what was sent, let the people who know the club
-- correct it. A wrong guess here is silent and permanent.
--
-- LATER CORRECTION (2026-09-08): "Count Sheet" was a genuine typo for "Count
-- Sheep", confirmed by Adam, and is corrected here and in the names file. The
-- live data was fixed separately by 2026-09-08_count_sheep_typo.sql, since this
-- import had already run. Note this is the club telling us, not us guessing --
-- which is exactly the process the rule above describes.
--
-- SAFE TO RE-RUN: it skips anyone already on this event's roster, whether they
-- were added as a legacy attendee, a walk-up, or through a real account. The
-- two hares already on the roster (Queen Myrtle and Smutley) are left alone,
-- and re-running adds nobody twice.
--
-- WRITTEN AS ONE STATEMENT ON PURPOSE. An earlier version used temp tables and
-- failed in the Supabase SQL editor with 'relation "incoming" does not exist':
-- the editor commits between statements, and "on commit drop" had already
-- destroyed the table. Everything below is a single INSERT with CTEs, so it
-- runs as one unit wherever you paste it.
--
-- Run in: Supabase Dashboard -> SQL Editor. Paste the whole file, run once.

insert into public.event_attendances
  (event_id, user_id, attendee_label, attendee_kennel,
   is_legacy, is_virgin_guest, amount_paid, charity_amount, paid)
with
-- Guard: 0 rows (and so 0 inserts) unless event 15 is still the Buxton weekend.
target as (
  select id from public.events
   where id = 15 and event_date = '2026-06-27' and location_summary = 'Buxton'
),
incoming(label) as (
  values
    ('A.N.Other'),
    ('Alice'),
    ('ASBO'),
    ('Big Mac'),
    ('Blind Doug'),
    ('Bodsa'),
    ('Bomber'),
    ('Bottomtanicals'),
    ('Busta Gonad'),
    ('Careless'),
    ('Cheesy Lollipop'),
    ('Chicki'),
    ('Cockatool'),
    ('Commercial Whale'),
    ('Count Sheep'),
    ('Crashed oot'),
    ('Creeper'),
    ('Cums Every Time'),
    ('Dirty Stop Out'),
    ('Dishy Goolies'),
    ('Dongle'),
    ('Dormouse'),
    ('Drip Lip'),
    ('Everready'),
    ('Fill My Cavity'),
    ('Flossie'),
    ('Flying Bottom'),
    ('Fondue'),
    ('For Sale Or Rent'),
    ('Furry'),
    ('GiveU1'),
    ('Groin Biter'),
    ('Headless Mullet'),
    ('Heir Flash'),
    ('Henpecked H4'),
    ('Hoggy'),
    ('Homeless Dick'),
    ('Horse''s Arse'),
    ('Humper'),
    ('Instant  Whip'),
    ('Ladykiller'),
    ('Little Stiffy'),
    ('Looselips'),
    ('Madder than Mad McMaddie'),
    ('Martini'),
    ('Mccavity'),
    ('Megasaurarse'),
    ('Molly'),
    ('Nosejob: nj'),
    ('Oral Sex'),
    ('Ossama''s Been Hashing'),
    ('Pippi Longcocking'),
    ('Puffed oot'),
    ('Queen Myrtle'),
    ('Queen of England'),
    ('Rab C'),
    ('Rhino'),
    ('Rivet'),
    ('Smartarse'),
    ('Smutley'),
    ('Software'),
    ('Speculator'),
    ('Speedbump'),
    ('Sperm Whale'),
    ('Splash'),
    ('Stiff Meat'),
    ('Swampy'),
    ('Sweaty Yeti'),
    ('Too Tuf'),
    ('Tweeny'),
    ('Twonk'),
    ('Unmentionable'),
    ('Walkie Talkie'),
    ('Walky Talky'),
    ('Wee Wee'),
    ('Wheelchair'),
    ('Wriggle')
),
-- Everyone already on this event's roster, however they were added: legacy and
-- walk-up rows carry attendee_label, real accounts carry hash_name on profiles.
existing_keys as (
  select lower(trim(a.attendee_label)) as key
    from public.event_attendances a
   where a.event_id = 15 and a.attendee_label is not null
  union
  select lower(trim(p.hash_name))
    from public.event_attendances a
    join public.profiles p on p.id = a.user_id
   where a.event_id = 15 and p.hash_name is not null
),
fresh as (
  select i.label
    from incoming i
   where lower(trim(i.label)) not in (select key from existing_keys)
),
-- Someone in the list may already hold an account without being on this event.
-- They get a REAL attendance row (user_id set) rather than a legacy one, so the
-- weekend attaches to their account and never needs merging later.
--
-- Note: "Nosejob: nj" is two people on one row, so it matches no account and
-- correctly falls through to the legacy branch.
matched as (
  select f.label, p.id as user_id
    from fresh f
    join public.profiles p
      on lower(trim(p.hash_name)) = lower(trim(f.label))
)
-- Members with an account -> a real row. Everyone else -> a legacy row.
select t.id, m.user_id, null::text, null::text, false, false, 0, 0, true
  from fresh f
  join matched m on m.label = f.label
  cross join target t
union all
select t.id, null::uuid, f.label, null::text, true, false, 0, 0, true
  from fresh f
  cross join target t
 where f.label not in (select label from matched);

-- Check: how the roster looks now. Expect 79 total -- the 77 imported plus the
-- two hares who were already there.
select count(*) filter (where is_legacy)           as legacy_rows,
       count(*) filter (where user_id is not null) as account_rows,
       count(*)                                    as total_on_roster
  from public.event_attendances
 where event_id = 15;
