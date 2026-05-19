# Supabase Auth email templates

Two on-brand email templates, adapted from the Claude-Design designs in `design-references/` to work with Supabase Auth's template engine.

**Important:** Don't add HTML comments containing `{{ ... }}` patterns at the top of these files. Supabase's Go template parser scans the whole file for `{{ }}` actions including inside HTML comments, and any unrecognised actions (like `{{ magic_link }}` with no leading dot) cause the template to fail compilation and Supabase silently falls back to its stock default. Keep the templates strictly to valid HTML.

## How to plumb these into Supabase

Supabase Dashboard → Authentication → Emails → Templates.

### `magic-link.html` → Magic Link template

Sent when an **existing** user signs in via `signInWithOtp({ email })`.

- **Subject**: `Your sign-in link for Steel City H3`
- **Message body**: paste the entire contents of `magic-link.html`

### `confirm-signup.html` → Confirm signup template

Sent the first time a user clicks "sign in" with an email that doesn't yet have an account. The confirmation link in this email both verifies the email **and** signs the user in (one tap), so the same `{{ .ConfirmationURL }}` placeholder used in the Magic Link template works here.

- **Subject**: `On-on! Confirm your email and you're in`
- **Message body**: paste the entire contents of `confirm-signup.html`

## Differences from the Claude-Design originals

These templates are adapted from `design-references/magic-link.html` and `design-references/registration.html`. Key changes:

- **Placeholder syntax** — Claude Design used `{{ hash_name }}`, `{{ magic_link }}`, `{{ otp_code }}`, `{{ next_event_date }}` etc. Supabase Auth exposes only a few placeholders:
  - `{{ .ConfirmationURL }}` — the magic / confirmation link
  - `{{ .Token }}` — the 6-digit OTP code paired with the link
  - `{{ .Email }}` — the recipient's email address
  - `{{ .SiteURL }}` — site URL configured in Authentication → URL Configuration
  - `{{ .RedirectTo }}` — the redirect URL passed by the client
- **No `{{ hash_name }}`** — Supabase Auth can't read our `profiles` table at email-send time, so any greeting that depended on a hash name has been rephrased to neutral copy.
- **No `{{ next_event_date }}` / `{{ next_event_url }}`** — Supabase can't query the `events` table either. The welcome panels use generic copy.
- **No `<img src="logo-original.jpg">`** — Supabase emails can't reach static assets in our Vercel project. To re-add a logo, upload it to a public URL (Supabase Storage works) and paste the full `https://` URL into the `src` attribute.
- **OTP code section removed** from `magic-link.html` because `/login.html` doesn't currently have a code-entry input (link-click only). To re-enable, add `{{ .Token }}` to the template and add an OTP input form to `/login.html` that calls `supabase.auth.verifyOtp()`.

## Re-using these for `signUp()` etc

The current site uses `signInWithOtp` only, so only the Magic Link and Confirm signup templates fire. If you later add password-based signup (`supabase.auth.signUp`), email change, or password reset flows, customise those templates in the dashboard too — same approach, just don't add HTML comments containing `{{ ... }}`.

## Future phases

`design-references/` also includes:

- `registration.html` — fuller welcome email; if we ever want to send a post-sign-up welcome (rather than just the confirm-and-go email), this would be sent from a Supabase Edge Function triggered by a database webhook on first `profiles` row update.
- `event.html` — RSVP confirmation / event reminders. Phase 2/3 work.
- `newsletter.html` — Phase 6 work.

None of those are wired in yet.
