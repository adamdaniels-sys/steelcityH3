# Where we left off — Steel City H3

_Last updated: 2026-05-20 (end of session)_

## State of play

Phases 1–4 are live at steelcityh3.org, plus a big admin/event rework done this
session. **Nobody has signed up yet** — the club sends sign-up links out once
you're happy with the site.

### Migrations (run in the Supabase SQL editor)
- **0001–0012** — run ✅ (auth, profiles, events, RSVPs, attendance, leaderboards, etc.)
- **0013_phase4_finalise_historical.sql** — _optional, probably not run yet._ Marks the seeded historical events (#13–17) as finalised so the old **£282.15** shows in the public/lifetime charity totals. Run it only if you want that historical figure displayed.
- **0014_phase4_workflow_charity.sql** — run ✅ (this session). New statuses, event type, charity model, kennel name, WhatsApp link, written-up flag.

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
**RSVP straight from the email** (one-click, no login) so people who never visit
the site still count.

Key decisions already made / constraints:
- **Sender**: Resend **free** plan = 100 emails/day, 1 domain — a 200-person blast exceeds the daily cap, so we'll likely use **Brevo's free tier (300/day)** or split the send. Queen Myrtle would need her own sender account for `steelcityh3.org`.
- **Consent**: contacts are from various hashing groups (warm-ish). Plan: import + send a clear **"you've been added to the Steel City H3 list — unsubscribe here"** intro, with unsubscribe in every email. (Adam to confirm details with Queen Myrtle.)
- Bulk email must **not** go through the IONOS mailbox (deliverability risk) — that stays for one-at-a-time RSVP confirmations only.

## How to resume
Say **"let's do the email phase"** (or point me at any tweak from TEST_SCRIPT).
The full design notes are saved in the assistant's project memory.

**On-on. 🐾**
