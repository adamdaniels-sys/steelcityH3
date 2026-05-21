# Steel City H3 — Test Script

A walk-through for testing everything built in the latest round (the tabbed
event workflow, charity model, profiles, WhatsApp, statuses). Tick as you go.
Best done signed in as an **admin**, with a **second test account** as a plain
member for the public/RSVP bits.

**Tip:** if anything looks stale, hard-refresh (Ctrl-F5) to clear the cached page.

---

## A. The quick visual stuff

- [ ] **Header** reads **"Coming up"** (not "Up Next") on every page.
- [ ] **Homepage hero**: big crest badge top-right, orange tilted photo-frame placeholder, tagline reads **"A drinking club with a running problem."**
- [ ] **Homepage looks right on a phone** (crest centred above the title, nav scrolls sideways, no sideways scroll of the whole page).

---

## B. Create and run a full event (the big one)

Admin → Manage events → **Schedule next hash**.

### Tab 1 — Event details
- [ ] Status chip top says **"In Planning"**, label says **"NEW EVENT"**, only Tab 1 is clickable.
- [ ] Change **Event type** to "Meet-up" → the field label changes to **"Meet-up number"**; change back to "Hash" → "Run number".
- [ ] Tick **Charity event?** → a **"Charity donation per head"** field appears.
- [ ] Fill it in (e.g. amount per head £3.50, charity £5), give it a title/date.
- [ ] Click **Save & invite** → status chip becomes **"Hares Needed"**, the name label shows your title, **Tab 2 appears** and opens.

### Tab 2 — Who's Cumming?
- [ ] Add yourself (or a member) as a **hare** (type to search, click to add).
- [ ] Click **"Mark 'Enough hares'"** → status chip becomes **"Open"**, button flips to "Back to Hares needed".
- [ ] The hare you added shows in the **"Who's planning to come"** list as on-on (auto-added).
- [ ] Click **Save & On-On** → status becomes **"Ready to On-On"**, **Tabs 3 & 4 appear**.

### Tab 3 — Ready to On-On
- [ ] Paste any link into **WhatsApp group invite link** → **Save link** → toast confirms.
- [ ] **Copy phone numbers** → toast says copied (numbers one-per-line if you paste somewhere).
- [ ] The roster shows your hare(s). Tick **Paid** on one → it goes green, **Collected** rises, and (charity event) **Charity** rises too.
- [ ] Edit a row's **amount** and **charity** figures → totals update.
- [ ] **Add a walk-up** ("Visiting Manchester H3") → appears on the roster.
- [ ] **Add a plus-one** with a host → appears, attributed to the host.
- [ ] Remove a row (the ✕) → confirm → it goes, totals drop.
- [ ] Click **Save & complete** → status becomes **"Completed"**, jumps to Tab 4.

### Tab 4 — After the event
- [ ] Money collected + Charity collected show the roster totals (read-only).
- [ ] Add a distance + scribe note, tick **Mark as written up**, **Save write-up**.
- [ ] Go to **Manage events** → that event shows a green **"✎ Written up"** badge.

---

## C. Charity vs non-charity

- [ ] Create a **non-charity** event (leave "Charity event?" unticked). On its roster (Tab 3), there's **no charity column**, only "Collected".
- [ ] After completing a **charity** event, open it (signed out) → public page shows a **"Raised £X for St Luke's"** badge.
- [ ] Homepage charity bar / running total reflects charity only (not the expenses money).

> Note: the lifetime total only counts events you've **completed**. The seeded historical £282.15 only shows if you've run `0013_phase4_finalise_historical.sql`.

---

## D. Dashboard worklist + statuses

- [ ] Admin dashboard shows **"Still to wrap up"** listing past-dated events not yet completed/finalised.
- [ ] After you **complete** an event, it **drops off** that list.
- [ ] Manage events still lists **everything** (finalised or not), with the right status badges (In Planning / Hares needed / Open / Ready to On-On / Completed / Cancelled).
- [ ] **Cancel** an event (danger zone) → shows **"Cancelled"**; **Delete** (type DELETE) wipes it.

---

## E. Profiles, kennel name, hash virgins

- [ ] As a **new member** (test account), sign up → on the profile form the **Hash name field is hidden** (a friendly note shows instead) because you're a virgin.
- [ ] There's a **"Kennel (home hash)"** field — fill it in, save.
- [ ] Untick **"I'm a hash virgin"** → the **Hash name field appears**.
- [ ] As **admin**, edit that member (Manage members → Edit) → you can set their **Hash name** and **Kennel**; saving a hash name + unticking virgin graduates them.

---

## F. Public event page + WhatsApp + route

- [ ] Open an upcoming event signed out → there's a **"The plan"** blurb, **no route placeholder**, and **no on-on pub** shown (it's secret).
- [ ] Signed in as a member, RSVP **On-on** → a **"Join the WhatsApp group"** button appears (because you set a link in Tab 3).
- [ ] RSVP confirmation **email** still arrives (check spam).

---

## G. Member's "My On-Ons"

- [ ] Past events you attended show **✅ Attended** (or "Didn't make it" if you weren't on the finalised roster).
- [ ] The header on that page no longer has a "What's a hash?" link.

---

## H. Mobile pass (do a few on your phone)

- [ ] The **event tabs** are usable and wrap sensibly.
- [ ] The **attendance roster** paid toggles are big enough to tap; amounts editable.
- [ ] Admin **tables** show as stacked cards (no sideways scrolling).

---

## I. Round 2 — your test-pass feedback (re-test these)

> First: run `0015_event_feedback_round.sql` and redeploy the `rapid-processor`
> Edge Function (see WHERE_WE_LEFT_OFF.md). Then hard-refresh.

**Event details (Tab 1)**
- [ ] The **Status** is labelled "Status", sits top-right, and is big/clear.
- [ ] Set type to **Meet-up** → the **Pace** field disappears (and is gone on the public page too).
- [ ] Tick **Charity event?** → both **Charity per head** and **Which charity?** appear.
- [ ] The **WhatsApp invite link** field is now here (not Tab 3); it saves with the event.
- [ ] After **Save & invite**, **Tab 1 shows a green ✓**. Each later step ticks as you finish it.

**Who's Cumming (Tab 2)**
- [ ] Add a member as a hare → they appear in the list with a **🐇 hare** marker and their **Kennel** column.
- [ ] **Remove that hare** → if they hadn't RSVP'd themselves, they **drop off** the coming list (no more phantom).
- [ ] A member who RSVP'd on-on themselves **stays** even if you add/remove them as a hare.

**Ready to On-On (Tab 3)**
- [ ] Charity box is **red-tinted, bigger**, with **"Total £" / "♥ Charity £"** captions above each box.
- [ ] **Add a walk-up** → you can enter a **hash name + kennel**; the kennel shows under their name.

**After the event (Tab 4) + public page**
- [ ] **On-on pub** field is here. It's hidden on the public page before the event, and **shows on the write-up** once completed.
- [ ] Completed charity event's public badge reads **"Raised £X for <your charity>"** (not always St Luke's).

**Email + WhatsApp**
- [ ] RSVP **On-on** → confirmation email arrives **with a "Join the WhatsApp group" button** (if a link is set).
- [ ] RSVP **Maybe** → you now also get a confirmation email (with the link).
- [ ] On the event page, the **Join WhatsApp** button shows for both **on-on and maybe**.

**Mobile**
- [ ] Tab 1 date/time, charity fields, and Tab 4 money no longer **run off the screen**.
- [ ] Tab 3 roster rows **stack** — paid toggle + amount + charity each tappable, nothing overlaps.

---

## Found a bug?
Jot the page + what you did + what you expected, and we'll fix it. The most
likely rough edges are in the brand-new tabbed event page (Section B).
