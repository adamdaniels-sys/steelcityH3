# Supabase Edge Functions

Server-side bits for Steel City H3. Each subfolder is one Edge Function.

| Function | What it does | Invoked by |
|---|---|---|
| `rsvp-email` (deployed as `rapid-processor`) | Sends an on-brand "You're on-on for X" email when a user confirms an RSVP that transitions into `on_on` | Frontend (`event.html`) via `supabase.functions.invoke()` |

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

1. Dashboard → steelcityh3 → **Edge Functions** → click **`rapid-processor`**
2. Open the editor → paste fresh contents of `supabase/functions/rsvp-email/index.ts`
3. **Verify JWT**: this should be **ON** for the new architecture (it's what authenticates the caller)
4. **Deploy**

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

Logs are visible in the Edge Functions section of the dashboard. If something errors, `[rsvp-email]` log lines from `console.log` / `console.error` will appear there.

## Why the function is named `rapid-processor`

Supabase's "Deploy a new function" dialog pre-fills a random name and we kept that one for now. The internal URL is `https://gxxlnpgvlghypmofualh.supabase.co/functions/v1/rapid-processor`. The frontend invokes by name (`rapid-processor`), so as long as that matches the deployed function name, all is well. To rename, delete this function and redeploy with a new name, then update the `invoke('rapid-processor', …)` call in `event.html` to match.
