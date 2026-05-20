# Admin guide — Steel City H3 site

A short manual for **Queen Myrtle** and **Smutley** (and any future co-admins).

**The site has a full admin UI — use it for everything.** Sign in to https://steelcityh3.org and click **"Admin"** in your header dropdown. The Supabase Dashboard path further down is now only a fallback for raw data fixes or the audit log.

---

## The proper admin UI (use this first)

Sign in to https://steelcityh3.org → click your name in the top-right → **Admin** → you're at the dashboard.

The dashboard has two event lists:
- **Still to wrap up** — hashes that have happened but you haven't finalised yet (attendance + money still to sort). They drop off here automatically once you finalise them.
- **Next up** — the upcoming hashes.

| What you want to do | Where |
|---|---|
| **Schedule the next monthly hash** | Dashboard → "Schedule next hash" (smart-fills the 3rd Saturday and a sensible title) |
| **Add an anniversary or one-off event** | Dashboard → "Add custom event" |
| **Edit an event** | Admin → Events → "Edit" on the row. Or from the live event page, the small "▸ Edit this hash" link. |
| **See who's RSVP'd + their phones** | Open the event → **RSVPs & WhatsApp** section |
| **Copy phones for the WhatsApp group** | Event page → RSVPs & WhatsApp → "Copy phones for WhatsApp" → paste into WhatsApp's New Group dialog |
| **Take attendance + record who paid** | Mark the event **Completed** and Save → the **Attendance & money** section opens (see walkthrough below) |
| **Add the scribe report / distance** | Edit event → set Status to "Completed" → the "After the event" fields appear |
| **Delete an event** | Edit event → bottom → "Danger zone" → "Delete this hash" |
| **Find / edit a member** | Admin → Members → search → "Edit" |
| **Promote / demote an admin** | Member edit page → Admin status *(can't demote yourself or the last admin)* |
| **Delete a member** | Member edit page → "Danger zone" |

Every admin action is audited automatically (`admin_actions` table in Supabase records who did what, when).

## The event page: three sections

When you open an event for editing, it's split into collapsible sections — click a heading to open/close it:

1. **Event details** — date, location, hares, pub, status, etc. *Once you mark the event "Completed" these fields lock (to stop accidental edits while you're collecting money). To edit them again, set the status back to "Ready to On-On".*
2. **RSVPs & WhatsApp** — who said they'd come, and the copy-phones / CSV tools.
3. **Attendance & money** — only appears once the event is Completed. This is the take-attendance tool.

### The status pipeline

`Hares wanted` → `Ready to On-On` (once hares are sorted) → `Completed` (after the day). `Cancelled` is separate, for a hash that's called off.

## Running a hash, start to finish

1. **Schedule it** (Dashboard → Schedule next hash). New hashes usually start as **Hares wanted**.
2. **Hares get sorted** — either you assign them (Event details → "Hares (members)") or a member offers on the event page. Set status to **Ready to On-On**. *(The site offers to flip this for you when hares are added.)*
3. **The day happens.** It now appears under **Still to wrap up** on the dashboard.
4. **Wrap it up:** open the event → set status to **Completed** → Save. The **Attendance & money** section opens, pre-filled from everyone who RSVP'd "on-on" (plus their plus-ones).
5. **Take the register:** tick **Paid** next to each person who turned up and coughed up (the amount defaults to £5 — edit it if someone rounded up). Add walk-ups or plus-ones, remove no-shows. The "Raised so far" total updates as you go.
6. **Finalise** when it all balances → confirm. The hash drops off "Still to wrap up", the charity total goes public, and members see an "Attended" badge on their My On-Ons page.

You can still edit a finalised event's roster afterwards if you spot a mistake.

## Hare assignment

- **Member offers to hare**: once a signed-in member marks themselves **On-On** for an event, an "▸ I'll hare this one" offer appears on the event page (unless the trail's already covered). Members can also withdraw. Offers email on-on@steelcityh3.org.
- **Admin assigns**: edit event → "Hares (members)" → type to search, click to add, × to remove. Adding a hare to a "Hares wanted" event offers to flip the status to "Ready to On-On".
- **Visiting hares** from other clubs: use the **"Hares (other / visitors)"** free-text field.

---

## The legacy Supabase Dashboard path (fallback only)

You shouldn't need this for normal management — the site UI above covers everything. Keep this section as a backup for the rare case where you need to touch raw data, query the audit log, or do something the admin UI doesn't yet support.

You don't need to know any code. You don't need to install anything. Everything happens in the Supabase Dashboard in your web browser.

---

## How to sign in to Supabase

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard) and sign in with your email + password (or magic link, if that's how you set up your account).
2. Top-left, click the **organisation switcher** and pick the org that contains the site (the one set up by Queen Myrtle).
3. Click the **steelcityh3** project tile.

If you can't see the project, ask Adam — you may need an invite to the organisation.

---

## Adding a new event

This is the most common admin task. About 5 minutes per event.

1. In the left sidebar, click **Table Editor** (the spreadsheet icon).
2. Find the **`events`** table in the list (under `public` schema).
3. Click the green **+ Insert** button → **Insert row**.
4. Fill in the fields below. Anything in **bold** is required; everything else can be left blank if you don't know it yet (you can come back and fill it in later).
5. Click **Save**.
6. Open [https://steelcityh3.org](https://steelcityh3.org) in a new tab. The new event should appear in **Up Next** within a few seconds (you may need to refresh).

### Fields explained

| Field | What to put |
|---|---|
| `id` | **Leave blank.** Supabase picks the next number automatically. |
| **`run_number`** | The hash number — e.g. `22` for the next one after #21. |
| **`title`** | Short event name, e.g. `June Hash` or `Sheaf Valley Stagger`. |
| **`event_date`** | Date in `YYYY-MM-DD` format, e.g. `2026-10-17`. |
| `start_time` | Time in 24h, e.g. `12:00` (already defaults to 12:00 noon). |
| **`location_summary`** | Short — shows on the homepage card. E.g. `Sheffield centre — TBC` or `Derbyshire Dales`. |
| `location_full` | Full address once you know it. E.g. `The Old Queen's Head, 40 Pond Hill, Sheffield S1 2BG`. |
| `hares` | Who's haring. Free text: `Bigfoot & Jake the Peg`, `Smutley`, `TBC`, `Volunteers wanted!`. |
| `pace` | `Walk or run`, `Walk`, or whatever fits. Defaults to `Walk or run`. |
| **`status`** | One of: `open` (normal), `hares_wanted` (need volunteers — shows orange warning), `closed`, `completed` (use this for past events). |
| `description` | The short blurb shown on the event page route box. E.g. `Sheffield month! Start point and exact pub announced on the Wednesday before by email.` |
| `distance_miles` | Add **after** the event when you know it. Decimal, e.g. `5.0`. |
| `on_on_pub` | Pub name once known, e.g. `The Plough, Low Bradfield`. |
| `scribe_report` | The write-up (after the event). Long text. Separate paragraphs with **a blank line** between them. |
| `scribe_report_by` | Hash name of whoever wrote the report. |
| `charity_raised` | £ amount raised, decimal e.g. `282.15`. |
| `amount_per_head` | Defaults to `5.00`. Only change if you're doing a special event with a different sub. |
| `created_at`, `updated_at` | **Leave blank.** Supabase fills these in. |

### Status quick reference

*(These are the raw database values. On the site the dropdown shows friendlier labels.)*

- `open` → shown as **"Ready to On-On"** — the normal "it's happening" state, on homepage Up Next
- `hares_wanted` → **"Hares wanted"** badge in red, on Up Next
- `closed` → shown as **"Cancelled"** — won't show on Up Next once the date passes
- `completed` → moves to "Past Hashes" archive on the homepage

---

## Editing an existing event

Same drill — Table Editor → `events` → find the row → click on the cell you want to change → type → press Enter. Changes save immediately.

**After the event** is the usual time to fill in:
- `status` → change from `open` to `completed`
- `distance_miles` → actual distance
- `on_on_pub` → the pub you ended at
- `scribe_report` and `scribe_report_by` → the write-up
- `charity_raised` → £ total

---

## Adding a new admin

Adding admin powers to someone is a **two-step process**:

### Step 1 — Get them to sign up first

Send them to [https://steelcityh3.org/login.html](https://steelcityh3.org/login.html). They sign in with their email, click the magic link, and fill out their profile. This creates their account.

### Step 2 — Promote them to admin

1. Supabase Dashboard → **Authentication** → **Users**. Find them by email.
2. **Copy their UID** (the long `xxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` string next to their email).
3. Go to **Table Editor** → **`user_roles`** table.
4. **+ Insert** → **Insert row**:
   - `user_id` → paste the UID
   - `role` → `admin`
   - `granted_by` → your own UID (find it the same way) — *optional*
   - `granted_at` → leave blank
5. **Save**.

They are now an admin. Next time they sign in, they'll have full read access to all profiles + can edit events. (In Phase 3 they'll get admin buttons on the site itself.)

### Removing admin powers

Table Editor → `user_roles` → find the row → click the **⋯** menu → **Delete row**.

This does **not** delete their account or profile — just their admin powers.

---

## Looking up someone's phone or real name

Privacy on the site is real — non-admins (and the public) can never see real names or phone numbers via the website. **You can** via the dashboard.

1. Table Editor → **`profiles`**.
2. Find the row by hash name (or scroll down).
3. The `real_name`, `phone`, etc columns are visible to you because you're a logged-in admin.

For pulling phones into a WhatsApp group:
1. Table Editor → `profiles`.
2. Click the column header → **Filter** → `is_hash_virgin` is `false` (or whatever subset you want).
3. Tick the rows you want, copy the `phone` column. Phase 3 will add a one-click "copy phones for WhatsApp" button.

---

## When something looks wrong on the live site

Usual culprits:
- **Event not showing on Up Next** → check the `status` is `open` or `hares_wanted`, and the `event_date` is today or later.
- **Wrong date showing on homepage card** → check `event_date` is in `YYYY-MM-DD` format with no extras.
- **Event detail page says "Hash not found"** → check the URL `?id=N` matches an `id` that actually exists in the `events` table.
- **Magic-link email never arrives** → check spam first. If it's not there, ping Adam — could be an IONOS DKIM issue.

For anything else, screenshot it and email Adam.

---

## Things you should NOT touch (yet)

- The **SQL Editor** — schema changes need Adam to review first.
- The **Authentication → SMTP settings** — already configured to send via IONOS. Breaking these means no magic-link emails.
- **Storage** — empty for now; will hold event photos from Phase 4 onwards.
- The **`service_role` API key** in Project Settings → API. That's a master key that bypasses all security. If you ever see it in a browser tab, screenshot it and close it.

---

## The admin UI is live

Everything above (events, members, hares, attendance, money) is now done from the website itself (steelcityh3.org → Admin), no dashboard required. The Supabase Dashboard sections in this guide are just a fallback for raw data fixes or the audit log. Pin the **"Running a hash, start to finish"** walkthrough near the top somewhere handy.

**On-on.**
