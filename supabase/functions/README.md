# Supabase Edge Functions

Server-side bits for Steel City H3. Each subfolder is one Edge Function.

| Function | What it does | Triggered by |
|---|---|---|
| `rsvp-email` | Sends an on-brand "You're on-on for X" email when a user transitions into the `on_on` status on the `rsvps` table | Database Webhook on `public.rsvps` |

## Deploying `rsvp-email`

You can deploy via the Supabase dashboard UI or via the Supabase CLI. The dashboard path is easier — no CLI install needed.

### Option A — Supabase Dashboard (recommended)

1. Open the Supabase dashboard → steelcityh3 project → **Edge Functions** (left sidebar)
2. Click **Deploy a new function**
3. **Name**: `rsvp-email`
4. **Verify JWT**: **OFF** (the Database Webhook authenticates with a header instead, see Step 4 below)
5. **Editor**: open `supabase/functions/rsvp-email/index.ts` in any text editor → copy entire contents → paste into the dashboard editor → click **Deploy function**
6. The deployment usually completes in 10–20 seconds. You should see a green tick.

### Option B — Supabase CLI

If you ever want to do this from the command line:

```bash
# Install once
npm i -g supabase

# Login
supabase login

# Link to the project
supabase link --project-ref gxxlnpgvlghypmofualh

# Deploy
supabase functions deploy rsvp-email --no-verify-jwt
```

## Configuring secrets

The function needs SMTP credentials to send via IONOS. **None of these are checked into git.**

In the dashboard → Edge Functions → `rsvp-email` → **Manage secrets** (or **Settings** depending on UI version), add:

| Name | Value |
|---|---|
| `SMTP_HOST` | `smtp.ionos.co.uk` |
| `SMTP_PORT` | `587` |
| `SMTP_USER` | `on-on@steelcityh3.org` |
| `SMTP_PASS` | *the mailbox password* (same one Supabase Auth uses for magic links) |
| `SMTP_FROM` | `Steel City H3 <on-on@steelcityh3.org>` *(optional — defaults to SMTP_USER)* |
| `SITE_URL` | `https://steelcityh3.org` *(optional — defaults to that)* |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are automatically injected by the Edge Functions runtime — don't set those manually.

After adding secrets, click **Save**. The function picks them up on its next invocation; no redeploy needed.

## Wiring up the Database Webhook

Last step is to make Postgres call the function whenever someone's RSVP row changes.

1. Supabase dashboard → **Database** → **Webhooks** → **Create a new hook**
2. **Name**: `rsvp-email-on-change`
3. **Table**: `public.rsvps`
4. **Events**: tick **Insert** and **Update**. Leave **Delete** unticked.
5. **Type**: **HTTP Request**
6. **Method**: `POST`
7. **URL**: copy the URL of your deployed function from the Edge Functions page. Looks like `https://gxxlnpgvlghypmofualh.supabase.co/functions/v1/rsvp-email`
8. **HTTP Headers**: add one header
   - Header name: `Authorization`
   - Header value: `Bearer <SUPABASE_ANON_KEY>` (paste the anon key from Project Settings → API. NOT the service-role key.)
9. Leave other settings at defaults
10. Click **Create webhook**

## Testing

1. Sign into the site as yourself
2. Open an upcoming event that you have not yet RSVP'd to
3. Click **▸ On-on!** — within 30 seconds, an email should arrive at the address tied to your account
4. Click **+** a couple of times to add guests, then sign out and back in to the event page — **no second email should arrive**. The function deliberately ignores guests_count tweaks while already on_on.
5. Change your RSVP to Maybe, then back to On-on — a fresh email arrives (it's a transition into on_on again)

Logs are visible in the Edge Functions section of the dashboard. If something errors, the log will say what.

## Local dev

You can run the function locally with the Supabase CLI:

```bash
supabase functions serve rsvp-email --env-file .env.local --no-verify-jwt
```

Then POST a fake webhook payload to `http://localhost:54321/functions/v1/rsvp-email`:

```bash
curl -X POST http://localhost:54321/functions/v1/rsvp-email \
  -H "Content-Type: application/json" \
  -d '{
    "type": "INSERT",
    "table": "rsvps",
    "schema": "public",
    "record": {
      "id": "test-id",
      "user_id": "your-user-uuid",
      "event_id": 18,
      "status": "on_on",
      "guests_count": 2
    },
    "old_record": null
  }'
```

`.env.local` should have `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and optionally `SMTP_FROM`, `SITE_URL`.

(For Phase 2 you almost certainly don't need to run this locally — the dashboard logs make debugging easy enough.)
