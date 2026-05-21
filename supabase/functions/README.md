# Supabase Edge Functions

Server-side bits for Steel City H3. Each subfolder is one Edge Function.

| Function | What it does | Invoked by |
|---|---|---|
| `rapid-processor` | Sends an on-brand confirmation email when a user RSVPs **on-on or maybe** (with the WhatsApp link + charity name), notifies admins when someone volunteers to hare, and handles full account deletion (snapshotting any unsettled debt first) | Frontend (`event.html`, `admin-member.html`) via `supabase.functions.invoke()` |

> The folder is now `rapid-processor` (matches the deployed function name). It used to be `rsvp-email`, which caused endless deploy confusion — see the ⚠️ in **Redeploying** below.

## Architecture

The frontend invokes the function directly after a successful RSVP confirm, *only* when:
- It's a new RSVP with `status='on_on'`, OR
- It's an UPDATE that changes status FROM something else TO `on_on`

(Transitions into `maybe` / `not_this_time`, and `guests_count` tweaks while already `on_on`, don't trigger the function.)

The function authenticates the caller via their Supabase session JWT (`supabase.functions.invoke` attaches it automatically), then verifies they actually have an `on_on` RSVP for the `event_id` in the request body before sending — no spoofing other users' emails.

**We deliberately don't use a Database Webhook.** That path had irrecoverable authentication quirks with both publishable (`sb_publishable_*`) and JWT-format anon keys in this project's Supabase configuration. Frontend invocation is simpler and uses standard Edge Function auth.

## Redeploying the function

After making code changes:

### Option A — Supabase Dashboard

⚠️ **The dashboard's code editor is a SEPARATE copy from this repo.** "Deploy
updates" only ships whatever is *currently in that editor box*. If you click it
without pasting the latest code first, you just re-deploy the old code (this is
exactly why the email kept saying the wrong thing).

1. Dashboard → steelcityh3 → **Edge Functions** → click **`rapid-processor`**
2. Open the editor → **select all → paste the full current contents of
   `supabase/functions/rapid-processor/index.ts` over it.** Sanity-check: it's
   ~740 lines and contains **no** "St Luke" and the text "Join the WhatsApp group".
3. **Verify JWT**: should be **ON** (it's what authenticates the caller)
4. **Deploy updates**

### Option B — Supabase CLI

```bash
supabase functions deploy rapid-processor
# Verify JWT defaults to ON — that's what we want
```

## Required secrets

Same as before. Edge Functions → `rapid-processor` → Manage secrets:

| Name | Value |
|---|---|
| `SMTP_HOST` | `smtp.ionos.co.uk` |
| `SMTP_PORT` | `587` |
| `SMTP_USER` | `on-on@steelcityh3.org` |
| `SMTP_PASS` | *the IONOS mailbox password* |
| `SMTP_FROM` | `Steel City H3 <on-on@steelcityh3.org>` *(optional)* |
| `SITE_URL` | `https://steelcityh3.org` *(optional)* |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected by the runtime.

## Database Webhook setup (no longer needed)

**You can delete the `rsvp-email-on-change` webhook from Database → Webhooks.** The frontend handles invocation directly now, so the webhook is dead weight.

## Testing

1. Sign in to https://steelcityh3.org
2. Find an upcoming event you've not RSVP'd to (or set yourself to "Can't make it" to reset)
3. Click **▸ On-on!** → form opens
4. Set guest count → **▸ Confirm**
5. Within ~10s, the email lands at the address tied to your account
6. Click + or − on guests in the confirmed state (currently no edit mode shown there — see below) → **no extra email**
7. Edit → switch to Maybe → Confirm → **no email**
8. Edit → flip back to On-on → Confirm → **fresh email** (it's a new transition)

Logs are visible in the Edge Functions section of the dashboard. If something errors, `[rapid-processor]` log lines from `console.log` / `console.error` will appear there.

## Why the function is named `rapid-processor`

Supabase's "Deploy a new function" dialog pre-filled this random name and we kept it. The internal URL is `https://gxxlnpgvlghypmofualh.supabase.co/functions/v1/rapid-processor`, and the frontend invokes by that name. The repo folder now matches (`supabase/functions/rapid-processor/`), so "the source" and "the deployed function" are the same word. To rename properly, delete this function and redeploy under a new name, rename the folder to match, and update the `invoke('rapid-processor', …)` calls in `event.html` / `admin-member.html`.
