# Admin guide — Steel City H3 site

A short manual for **Queen Myrtle** and **Smutley** (and any future co-admins).

**Phase 3 update:** The site itself now has a full admin UI. **For day-to-day management, sign in to https://steelcityh3.org and click "Admin" in your header dropdown.** Everything below describes the legacy Supabase Dashboard path, which still works as a fallback for anything the site UI doesn't expose yet (audit log queries, manual data fixes, raw SQL).

---

## The proper admin UI (use this first)

Sign in to https://steelcityh3.org → click your name in the top-right → **Admin** → you're at the dashboard.

| What you want to do | Where |
|---|---|
| **Schedule the next monthly hash** | Dashboard → "Schedule next hash" (smart-fills the 3rd Saturday and a sensible title) |
| **Add an anniversary or one-off event** | Dashboard → "Add custom event" |
| **Edit an event** | Admin → Events → click "Edit" on the row. Or from the live event page, click the small "▸ Edit this hash" link. |
| **See who's coming to an event + their phones** | Open the event in Admin → Events → Edit → "Attendees" section at the bottom |
| **Copy phones for the WhatsApp group** | On the event admin page → "Copy phones for WhatsApp" → paste into WhatsApp's New Group dialog |
| **Export attendees as CSV** | Same page → "Export CSV" |
| **Mark an event as completed and add the scribe report** | Edit event → change Status to "Completed" → fill in distance, on-on pub, scribe report fields that appear |
| **Delete an event** | Edit event → bottom of page → "Danger zone" → "Delete this hash" |
| **Find a member** | Admin → Members → search by hash name / real name / email |
| **Edit a member's profile** | Members → click "Edit" on the row |
| **Promote a member to admin** | Member edit page → "Admin status" section → "Promote to admin" |
| **Demote an admin** | Member edit page → "Demote from admin" *(can't demote yourself or the last admin — site guards both)* |
| **Delete a member** | Member edit page → "Danger zone" → "Delete this member" |

Every admin action is audited automatically — the `admin_actions` table in Supabase records who did what, when, with before/after values. There's no UI for browsing it yet (Phase 6+ feature) but admins can query it directly in Supabase if a question ever needs answering.

## Hare assignment

There are two paths for assigning hares to an event:

- **Member self-nominates**: when an event's status is "Hares wanted" and no hares are assigned yet, signed-in members see an "▸ I'll hare this one" button on the event page. Clicking it adds them as a volunteer hare. You can override or add to this from the admin UI any time.
- **Admin assigns**: edit event → "Hares (members)" multi-select → type to search by hash or real name, click to add, click × on a pill to remove. When you add a hare to an event marked "Hares wanted", the site offers to flip status to "Open" for you.

For visiting hares from other clubs (e.g. Manchester H3 visiting), use the **"Hares (other / visitors)"** free-text field — it's separate from the structured hare list.

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

- `open` → "▸ Open!" badge, shown on homepage Up Next
- `hares_wanted` → "▸ Hares wanted" badge in red, shown on Up Next
- `closed` → "Closed" — won't show on homepage Up Next once the date passes
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

## When the proper admin UI ships (Phase 3)

You'll be able to do all of the above from the actual website (steelcityh3.org), no dashboard required. This guide will still be here as a fallback. Until then — pin it somewhere handy.

**On-on.**
