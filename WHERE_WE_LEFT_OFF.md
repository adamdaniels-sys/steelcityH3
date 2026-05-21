# Where we left off — Steel City H3

_Last updated: 2026-05-21 (test-pass fixes)_

## 🅿️ PARKED — go-live + SEO (do AFTER the test data is cleared)
The site is live but full of test data, so we are deliberately **NOT** chasing
search rankings yet (don't want randoms stumbling into the rubbish).

**Before launch:** clear the test events / accounts / RSVPs so it's all real.

**Optional now:** lock the whole site out of Google with a `noindex` header
(Vercel `X-Robots-Tag: noindex` in `vercel.json`) — link previews to people you
directly share with still work; only search engines are kept out. Remove it at
launch. (Not yet applied — Adam to decide.)

**At go-live, the SEO checklist (mostly easy wins for the niche "Sheffield hashing"):**
1. **Google Search Console** — verify the domain, submit the sitemap, "Request indexing". (Biggest first step.)
2. On-page (assistant to build): `sitemap.xml` + `robots.txt`; JSON-LD structured data (SportsClub on home, Event on event pages); sharpen homepage `<title>`/meta to include "Sheffield Hash House Harriers / hashing"; a visible "Sheffield Hash House Harriers" heading.
3. Backlinks (the bit that actually ranks a niche query): global hash-house-harriers directories, the Facebook group/page (link in About + pinned post), a Strava club and/or Meetup listing, local Sheffield "clubs/running" directories. Keep the club name identical everywhere.

## ⚡ Do these now (see STEP_BY_STEP.md for the full walk-through)
1. **Run `0018_debt_tracking.sql`** (debt RPCs + `orphaned_debts` table).
2. **Run `0019_legacy_attendees_merge.sql`** (legacy attendees + merge + metrics).
3. **Re-deploy `rapid-processor`** from `supabase/functions/rapid-processor/index.ts`
   (debt-snapshot-on-delete + the charity-name/WhatsApp email fixes — the live
   function appears to still be stale, so double-check the deploy lands).

_(Migration 0017 already run.)_

## Round 7 — legacy attendees + merge (2026-05-21)
Backfill the people who came before the website + merge them into real accounts.
- **Add a past attendee (legacy)** box on a past event's attendance tab — enter
  Hash name (+ Kennel). Stored as £0, paid, "Past member (legacy)" — counts in
  metrics, never shows as owing.
- New **Legacy attendees** admin page (dashboard quick action) lists each legacy
  name, their kennel, # past events, and whether a matching account has signed up.
- When it has, a **Merge into account** button reattaches all their backfilled
  attendances to the real account — so the Hall of Fame shows ONE person.
- **Top Hounds** now counts distinct past events *attended* (RSVPs + attendance
  rows incl. legacy), which is what makes legacy folk show up and merge cleanly.

**That clears the whole feature backlog.** Remaining nice-to-have (not built):
re-matching an orphaned debt to a returning member (would live on the Legacy page).

## Round 6 — debt / outstanding-money tracking (2026-05-21)
A debt = someone on a **completed** event's roster who isn't ticked **Paid** (the
amount in their box is what they owe). Money model already supports this.
- **Event page (Tab 3):** live **Outstanding** total (red when there's money owed).
- **Manage events:** completed events show a **Money outstanding £X** tag.
- **Who's coming (Tab 2):** anyone who owes from a past event gets an **owes £X** flag.
- **Manage members:** an **owes £X** badge + an **Owes money** filter; clicking a
  member shows **Outstanding payments** with a **Mark paid** button per event (which
  updates that event's takings). Plus a **Former members with unsettled debts** list.
- **Account deletion** snapshots any unsettled debt (by hash name) into `orphaned_debts`
  so it isn't lost; re-matching a returning member comes with the legacy-names feature.

You can now **complete an event with money still outstanding** — it just shows the
tags afterwards, rather than having to leave the event open.

**Still to build:** legacy attendee names + merge (backfill past attendees as
Hash name + Kennel; merge a legacy name into a real account on sign-up; this is also
where orphaned-debt re-matching will live).

## ⚡ Status of recent rounds
- Migrations **0015 + 0016** are run; `rapid-processor` redeployed for the
  WhatsApp/Maybe-email round. All live.
- **Link-previews round needs no migration** — just the git push (Vercel picks up
  `vercel.json` + `api/event.js` automatically). After it deploys, **verify once**:
  open `https://steelcityh3.org/event/<an-id>` and check the page source has the
  event's title in `og:title` (or paste the link into Facebook's Sharing
  Debugger). The og:image is a themed **1200×630 `og-cover.jpg`** (full badge on
  the cream/orange rivet backdrop) — regenerate it from the logo with `sharp` if
  the branding ever changes.

## Round 5 — bug fixes, single-field money model, clearer toggles (2026-05-21)
From a re-run with Queen Myrtle:
- **Bug:** meet-ups wouldn't save (pace was NOT NULL). Fixed — `pace` is now nullable.
- **Bug:** confirmation email said "St Luke's" + had no WhatsApp link. Root cause: the
  deployed function was an old version. The current source names the chosen
  **charity** and includes the **WhatsApp** link — **re-deploy `rapid-processor`**.
- **Money model rebuilt:** the per-head amount is now the **total** a head pays
  (charity is a slice of it, not added on top — the old way double-counted). One
  "Paid £" box per person; the page shows **Collected / Organiser keeps / To charity**.
  Rule: organiser keeps the expenses (per-head − charity slice); everything above
  goes to the charity (so a charity hash always raises at least its earmarked bit).
- **Toggles** (Charity? / Meal? / Stay? / Written up / Hash virgin) are no longer an
  orange slider — now a clear box that fills black with a big orange **tick** when on.

**Strategy:** no mass-emailing un-opted-in people. Instead post the site link in the
WhatsApp/Facebook groups asking people to **register**, repeat weekly, judge uptake.

**Still to build (next, agreed):** (1) **legacy attendee names + merge** (enter past
attendees as Hash name + Kennel; merge a legacy name into a real account when it
signs up, so metrics don't double-count); (2) **debt tracking** (complete events with
money outstanding; [Money Outstanding] tag; settle debts from Manage Members; flag
debtors in new RSVP logs; keep a record if a debtor deletes their account).

## Round 4 — shareable link previews (2026-05-21)
Mass-emailing the 200 contacts is **on hold** — first promote the site and get
people to **sign up** (Queen Myrtle to post in the FB group daily: "new website,
all RSVPs here now, sign up to the newsletter"). Single source of truth: Facebook
posts **link to the event**, they're not a second RSVP venue.

To make those posted links look good:
- New route **`/event/:id`** (served by `api/event.js`, a dependency-free Vercel
  function) returns the event page with **per-event Open Graph tags** (title,
  date, where) so Facebook/WhatsApp show a proper card. `/event.html?id=` still
  works as a fallback (generic preview).
- A **"Share / copy link"** button on every event page hands over the `/event/:id`
  URL (native share sheet, or copies to clipboard).
- Homepage, My On-Ons and admin links now point at `/event/:id`; the homepage has
  static OG tags too.
- **Note:** because `/event/:id` has a path segment, `event.html`'s assets were
  switched to root-absolute (`/spice.css`, `/auth.js`, `/logo-original.jpg`).

## State of play

Phases 1–4 are live at steelcityh3.org, plus a big admin/event rework done this
session. **Nobody has signed up yet** — the club sends sign-up links out once
you're happy with the site.

### Migrations (run in the Supabase SQL editor)
- **0001–0012** — run ✅ (auth, profiles, events, RSVPs, attendance, leaderboards, etc.)
- **0013_phase4_finalise_historical.sql** — _optional, probably not run yet._ Marks the seeded historical events (#13–17) as finalised so the old **£282.15** shows in the public/lifetime charity totals. Run it only if you want that historical figure displayed.
- **0014_phase4_workflow_charity.sql** — run ✅. New statuses, event type, charity model, kennel name, WhatsApp link, written-up flag.
- **0015_event_feedback_round.sql** — run ✅. Test-pass fixes: `rsvps.via_hare` (+ hare-delete trigger so removing a hare clears the RSVP it created), `events.charity_name`, `event_attendances.attendee_kennel`, and the roster RPC returns kennel.
- **0016_meals_accommodation.sql** — _NEEDS RUNNING._ `events.has_meal`/`meal_note`/`asks_accommodation`, `rsvps.needs_accommodation`/`dietary_requirements`, and tightens `rsvps` SELECT to own + admin (was world-readable).

## Round 2 — test-pass fixes (2026-05-21)
From Adam's run-through of TEST_SCRIPT.md:
- **Status** is now labelled "Status", right-aligned and large on the event page.
- **Pace** is hidden for Meet-ups (admin form + public page).
- **Charity name** field added (not always St Luke's) → shows on the public "Raised £X for…" badge.
- **Tabs get a green ✓** as each step is completed.
- **Hare logic**: removing a hare now clears the auto-created "coming" RSVP (only the auto-created one — a member's own RSVP is left alone). The Who's-coming table shows a 🐇 marker and a **Kennel** column, and refreshes when hares change.
- **WhatsApp link moved to Tab 1** (Event details) so it can be set early; it now goes in the **confirmation email** and shows on the event page for **on-on _and_ maybe** members. **Maybe RSVPs now get a confirmation email too.**
- **Charity roster boxes** are themed (red-tinted), bigger, and captioned ("Total £" / "♥ Charity £").
- **Walk-ups** can record a **hash name + kennel**.
- **On-on pub** field added to Tab 4 — private before the event, shown on the past write-up.
- **Mobile**: form rows (date/time, charity, after-event money) and the roster now stack instead of overflowing on a phone.

## Round 3 — meals, accommodation + wider desktop forms (2026-05-21)
- **Tabs span the full width** on desktop; the **Status** label sits above the 4th tab; the **event-detail form fills the width** (fields paired into 2-column rows) so planning uses the screen.
- **Meals**: Tab 1 has an **"Includes a meal?"** toggle (+ optional meal note). When on, the RSVP asks each attendee for **dietary requirements**, the public page shows a **Meal** row, and Tab 2 gains a **Dietary** column + count.
- **Accommodation**: Tab 1 **"Might need a place to stay?"** toggle. When on, the RSVP asks **"I'll need a place to stay"**; Tab 2 gains a **Stay?** column + count, and it's in the CSV — so hotels can be block-booked.
- **Privacy**: `rsvps` is **no longer world-readable** (dietary needs are sensitive) — own + admin reads only; public attendee lists already use definer RPCs so they're unaffected.

## What changed this session (all committed + deployed)

1. **Header**: "Up Next" → **"Coming up"**.
2. **Charity model**: events can be a **Charity event (Y/N)** with a separate **charity-per-head** amount on top of the base sub. Per event tracks **money collected** vs **charity collected** separately; only charity feeds the lifetime homepage counter.
3. **Route** removed from planned events (public page shows a "The plan" blurb; route becomes a post-event upload — placeholder in Tab 4).
4. **Hash names**: hidden for hash virgins (awarded, not chosen); new **Kennel (home hash)** field on profile, sign-up, and admin editor.
5. **WhatsApp**: there's no free way to bulk-add numbers to a group, so each event has a **WhatsApp invite-link** field → on-on members get a "Join the group" button. Copy-numbers now one-per-line.
6. **Event page = a 4-tab workflow** (replaced the collapsibles):
   - **In Planning → Hares Needed → Open → Ready to On-On → Completed** (+ Cancelled).
   - Tab 1 Event details → Tab 2 Who's Cumming (hares + RSVPs) → Tab 3 Ready to On-On (WhatsApp + attendance + money) → Tab 4 After the event (write-up + "written up" flag).
   - On-on pub field removed (it's secret).

To test it all: see **TEST_SCRIPT.md**.

## Known minor items (not bugs, just noted)
- **Meet-up events** still display "Run #N" on public pages (reusing the run-number field) — easy to relabel to "Meet-up #N" if wanted.
- The **dead `.burst*` CSS** from the old hero is still in `spice.css` (left in case you wanted to compare hero versions; say the word to delete).
- **Historical #15 (£282.15)**: shows in the charity totals only after running migration 0013 (see above).

## The next big thing: Email & audience phase (planned, NOT started)
You chose to do this **after** the rework. Scope: import ~200 contacts from
other hashing groups, email them event **invites + newsletters**, and let them
RSVP for events they don't normally attend the site for.

**RSVP-from-email decision (2026-05-21):** _not_ pure one-click RSVP. Newsletter
/ invite buttons should **link to the event page** (a tokenised magic-link so no
password is needed) so the attendee can also set **dietary requirements** and
**accommodation** needs while they RSVP — a one-click "I'm on-on" can't capture
those.

Key decisions already made / constraints:
- **Sender**: Resend **free** plan = 100 emails/day, 1 domain — a 200-person blast exceeds the daily cap, so we'll likely use **Brevo's free tier (300/day)** or split the send. Queen Myrtle would need her own sender account for `steelcityh3.org`.
- **Consent**: contacts are from various hashing groups (warm-ish). Plan: import + send a clear **"you've been added to the Steel City H3 list — unsubscribe here"** intro, with unsubscribe in every email. (Adam to confirm details with Queen Myrtle.)
- Bulk email must **not** go through the IONOS mailbox (deliverability risk) — that stays for one-at-a-time RSVP confirmations only.

## How to resume
Say **"let's do the email phase"** (or point me at any tweak from TEST_SCRIPT).
The full design notes are saved in the assistant's project memory.

**On-on. 🐾**
