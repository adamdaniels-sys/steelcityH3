# Loading the real club data

This swaps the test rubbish for the real history from `ROUND UP.ods`
(runs 3-13, ~95 attendees). Do it in this order, all in the Supabase SQL Editor.

## Before you start
Make sure these migrations have been run (in order): **0018**, **0019**, then the
new **0020_sch3_virgin_and_free_hares.sql**. `0020` adds the "SCH3 Hash Virgin"
wording and makes hares + first-timers free — the seed assumes it's there.

## 1. Clear the test data
Run **`clear_test_data.sql`**. This wipes all events, RSVPs, rosters, hares,
debts and the audit log. It leaves every **account** alone.

To also remove the **test sign-ups** (keeping the 3 admins + Adam el Serf), the
easy way is the dashboard: **Authentication -> Users -> tick the test ones ->
Delete**. (There's an optional SQL version at the bottom of the clear script.)

## 2. Load the real data
Run **`seed_real_data.sql`**. It creates runs 3-13 as completed hashes (£3,
charity off, noon start) and loads everyone as a **legacy attendee** with their
kennel and the right fee:
- £3 = paid
- £0 = hares and "First timer" (SCH3 Hash Virgins)
- "owes" (Horse's Arse, run 13) = an unpaid £3, i.e. a debt

## 3. Fold the regulars into their accounts
Everyone — including you, Queen Myrtle and Smutley — is loaded as legacy. Once an
account exists with a matching **hash name**, go to **Admin -> Legacy attendees**
and **Merge** them in (see `STEP_BY_STEP.md` Part 4). Do this for Smutley, Queen
Myrtle and your own hash name so the metrics count them as one person, not two.

## 4. What's missing / needs a decision (from the sheet)
- **Run 14** (Dore & Totley Station) has **no date** — left out. If it's still
  upcoming, create it in the admin UI so members can RSVP; if it's already
  happened, add its date and uncomment the block at the foot of the seed.
- **Runs 9 & 10** had **no data** in the sheet — not created (the run numbers
  simply skip from 8 to 11, which is fine).
- **Run 5 "Horny Devil"** had a **blank fee** — loaded as £0. Change if they paid.
- **Run 4 "Nate"** had a stray "Fl" cell in the sheet — ignored.
- **Start times** are all noon (the sheet doesn't record them) — fix per event
  if any differed.
- **Titles** are "Month Year Hash" (e.g. "July 2025 Hash"); the run number shows
  separately as "Run #6". Rename any in the admin UI if you'd prefer.
