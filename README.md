# Steel City H3

The website and member portal for **Steel City H3**, Sheffield's youngest Hash House
Harriers chapter — a drinking club with a walking problem.

Live at **[steelcityh3.org](https://steelcityh3.org)**, running on real club data.

## What it is

A plain static site — HTML, CSS and vanilla JS, **no build step and no bundler** —
deployed on **Vercel** and backed by **Supabase** for everything dynamic:

| Concern | How |
|---|---|
| Accounts | Supabase Auth, email one-time-code (no passwords) |
| Data | Supabase Postgres, row-level security on every table |
| Photos | Supabase Storage, bucket `event-photos` |
| Transactional email | Supabase Edge Function `rapid-processor` |
| Link previews | `api/event.js` injects per-event Open Graph tags |

The no-build constraint is deliberate: every page opens as a plain file, and anyone
can read the source without a toolchain.

## The shape of it

**Public** — `index.html` (upcoming and past hashes, hashing 101, jargon, contacts),
`event.html` (one hash, upcoming or past, via `?id=`), `login.html`.

**Members** — `profile.html`, `complete-profile.html`, `my-on-ons.html`.

**Admin** — `admin.html` is the dashboard; `admin-event.html` runs the four-tab event
workflow (event details → who's cumming → ready to on-on → after the event), with
`admin-events.html`, `admin-members.html`, `admin-member.html`, `admin-legacy.html`
and `admin-attendance.html` alongside.

**Shared** — `spice.css` holds the whole design system; `auth.js`, `config.js` and
`hare-picker.js` are the only extracted scripts. Most page logic still lives in
inline `<script>` blocks.

**Backend** — `supabase/migrations/` is the numbered schema history, applied in order
by hand through the Supabase SQL editor. `supabase/functions/rapid-processor/` is the
email edge function. `api/` holds the two Vercel serverless functions.

## Running it locally

No install, no build. Open `index.html` in a browser, or serve the folder so query
params behave:

```bash
python3 -m http.server 8000   # then http://localhost:8000/
```

Supabase credentials live in `config.js` and point at the live project, so a local
copy reads and writes **real club data**. Take care.

## Design system

"Spice & Steel" — cream Henderson's-Relish-buff backgrounds, Sheffield-steel grey
accents, hot-orange highlights, and Beano-style comic display type (Bangers, Lilita
One, Nunito, with Caveat for handwritten photo captions).

## For admins

Queen Myrtle and Smutley: everything you need is in the admin UI, and the walkthrough
is in **`ADMIN_GUIDE.md`**.

## For contributors

Project state — what's done, what's open, decisions and conventions — is tracked in
**Acta**, not in markdown. Run `node .claude/acta.cjs now` to see where things stand,
or just ask Claude.
