# Steel City H3

The website for **Steel City H3**, Sheffield's youngest Hash House Harriers chapter — a drinking club with a walking problem.

## What's in here

- **`home.html`** — the main landing page (upcoming hashes, past hashes, hashing 101, jargon, mismanagement contacts, other groups, about)
- **`event.html`** — single-event detail page. Takes a `?id=` query param (e.g. `event.html?id=18`). Handles upcoming + past states from one template.
- **`login.html`** — sign-in / sign-up mockup with email + 6-digit OTP flow
- **`spice.css`** — shared stylesheet (Spice & Steel design system)
- **`logo-original.jpg`** — the club crest

## Running it

Open `home.html` in any modern browser. No build step, no server required — it's all static HTML + CSS + a small amount of vanilla JS.

To preview locally with a tiny dev server (optional, recommended so query params work cleanly):

```bash
# Python 3
python3 -m http.server 8000
# then open http://localhost:8000/home.html

# or with Node
npx serve .
```

## How the prototype works

**RSVPs, accounts, and admin mode are all mocked in `localStorage`** — they live only in the browser of whoever is using the site. Useful for showing the shape of the experience; not real persistence.

- **Sign up flow:** email + hash name → any 6-digit code → logged in
- **Sign in flow:** existing email → any 6-digit code → logged in
- **Admin mode:** sign in as `smutley@hotmail.co.uk` to see admin-only UI (edit event, upload photos, post write-up). Buttons are placeholders.
- **RSVPs:** logged-in users can click "Yes, I'll be there!" on upcoming event pages. The RSVP list is stored per-event in localStorage.

## When you're ready to make it real

For real accounts, shared RSVPs, photo uploads, and a content editor for Smutley, I'd recommend:

- **Backend:** [Supabase](https://supabase.com) — its built-in email-OTP login matches the prototype's flow almost exactly. Free tier is plenty for a small club.
- **Hosting:** [Netlify](https://netlify.com), [Cloudflare Pages](https://pages.cloudflare.com) or [Vercel](https://vercel.com) — all have free tiers for static sites with one-click git deploys.

The HTML/CSS in this repo lifts-and-shifts onto any of those — only the localStorage calls in `event.html` and `login.html` need to be swapped for Supabase queries.

## Credits

Design system: cream Henderson's-Relish-buff backgrounds, Sheffield-steel grey accents, hot-orange highlights, and Beano-style comic display type (Bangers + Lilita One + Nunito).
