// Steel City H3 — RSVP confirmation email
//
// Edge Function invoked directly from the frontend (event.html) after a user
// CONFIRMS an RSVP that transitions them into the on_on status. The frontend
// only invokes this function when:
//
//   * It's a brand new RSVP with status='on_on', OR
//   * It's an UPDATE that changes status FROM something else TO on_on
//
// (Transitions into maybe / not_this_time, and guests_count tweaks while
// already on_on, don't trigger the function — they're just plain DB writes.)
//
// Authentication: the frontend uses supabase.functions.invoke() which auto-
// attaches the user's session JWT. The function then verifies the user
// actually has an on_on RSVP for the eventId in the request body before
// sending — no spoofing other users' emails.
//
// Sends via IONOS SMTP using the same on-on@steelcityh3.org mailbox that
// Supabase Auth uses for magic links — no extra paid service needed.
//
// Required Edge Function secrets:
//
//   SMTP_HOST   = smtp.ionos.co.uk
//   SMTP_PORT   = 587
//   SMTP_USER   = on-on@steelcityh3.org
//   SMTP_PASS   = <the mailbox password>
//   SMTP_FROM   = Steel City H3 <on-on@steelcityh3.org>   (optional)
//   SITE_URL    = https://steelcityh3.org                  (optional)
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by the runtime.
// Verify JWT MUST be ON for this function so the user's session is validated.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// Body can be EITHER an email-send request (event_id + optional notify) or
// an account-delete request (op='delete_account' + optional target_user_id).
// Function discriminates on body.op.
interface EmailBody {
  event_id: number;
  notify?: 'rsvp_confirmation' | 'hare_volunteer';
}
interface DeleteAccountBody {
  op: 'delete_account';
  target_user_id?: string;
}
type InvokeBody = EmailBody | DeleteAccountBody;

// CORS — function is invoked cross-origin from steelcityh3.org by the
// supabase-js client, which means the browser sends an OPTIONS preflight
// before the POST. Without this, the preflight returns 405 and the actual
// POST never fires.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...CORS_HEADERS,
    },
  });
}

function formatLongDate(iso: string): string {
  // Renders as "Saturday 20 June 2026" (locale-stable, UK conventions)
  const d = new Date(iso + "T12:00:00Z");
  const weekdays = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
  const months   = ["January","February","March","April","May","June","July","August","September","October","November","December"];
  return `${weekdays[d.getUTCDay()]} ${d.getUTCDate()} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

function formatTimeFriendly(t: string | null): string {
  if (!t) return "TBC";
  const [hStr, mStr] = t.split(":");
  const h = parseInt(hStr, 10);
  const m = parseInt(mStr, 10);
  if (h === 12 && m === 0) return "12 noon";
  if (h === 0  && m === 0) return "midnight";
  const period = h >= 12 ? "pm" : "am";
  const h12 = h % 12 || 12;
  return m === 0 ? `${h12}${period}` : `${h12}:${String(m).padStart(2, "0")}${period}`;
}

function escapeHtml(s: string | null | undefined): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function buildEmailHtml(opts: {
  greetingName: string;
  eventTitle: string;
  dateLong: string;
  timeFriendly: string;
  locationSummary: string;
  hares: string;
  onOnPub: string;
  guestsCount: number;
  amountPerHead: number;
  eventUrl: string;
  status: "on_on" | "maybe";
  whatsappLink: string;
}): string {
  const isMaybe = opts.status === "maybe";
  const eyebrow = isMaybe ? "▸ You're a maybe" : "▸ You're on-on!";
  const bigHeadline = isMaybe ? "Pencilled in," : "You're on-on,";
  const introLead = isMaybe
    ? "Cheers — we've pencilled you in for"
    : "Right then — you're booked in for";
  const introTail = isMaybe
    ? " Flip to on-on on the page when you know for sure."
    : "";
  const shoesLine = opts.whatsappLink
    ? "Wear shoes you don't love. Jump into the event WhatsApp group below to keep up with the plan."
    : "Wear shoes you don't love. We'll add you to the event WhatsApp group nearer the time.";
  const whatsappBlock = opts.whatsappLink ? `
    <tr><td align="center" style="padding: 0 32px 24px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td>
        <a href="${escapeHtml(opts.whatsappLink)}" style="display: inline-block; background: #25d366; color: #0b3d1f; padding: 13px 26px; font-family: 'Bangers', 'Impact', sans-serif; font-size: 20px; letter-spacing: 0.05em; text-transform: uppercase; text-decoration: none; border: 3px solid #15110a; box-shadow: 5px 5px 0 #15110a;">
          ▸ Join the WhatsApp group
        </a>
      </td></tr></table>
    </td></tr>
  ` : "";
  const guestsBlock = opts.guestsCount > 0 ? `
    <tr><td style="padding: 0 32px 24px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #ffd23a; border: 3px solid #15110a; box-shadow: 4px 4px 0 #15110a;"><tr>
        <td style="padding: 16px 20px;">
          <div style="font-family: 'Bangers', 'Impact', sans-serif; font-size: 22px; color: #15110a; letter-spacing: 0.04em; line-height: 0.95; margin-bottom: 6px;">
            ▸ Bringing ${opts.guestsCount} hash virgin${opts.guestsCount === 1 ? "" : "s"}
          </div>
          <p style="margin: 0; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 14px; color: #3a2e1f; line-height: 1.5; font-weight: 600;">
            They're on your tab for subs — about
            <b>£${(opts.guestsCount * opts.amountPerHead).toFixed(2)}</b>
            cash on the day. Plus your own £${opts.amountPerHead.toFixed(2)}.
          </p>
        </td>
      </tr></table>
    </td></tr>
  ` : "";

  return `<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="color-scheme" content="light only" />
<meta name="supported-color-schemes" content="light only" />
<title>You're on-on for ${escapeHtml(opts.eventTitle)}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Bangers&family=Lilita+One&family=Nunito:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;700&display=swap');
  body, table, td { margin: 0; padding: 0; }
  table { border-collapse: collapse; }
  img { display: block; border: 0; }
  a { color: #ee5a17; }
</style>
</head>
<body style="background: #f4e5b8; margin: 0; padding: 0; font-family: 'Nunito', 'Segoe UI', Helvetica, Arial, sans-serif; color: #15110a;">
  <div style="display: none; max-height: 0; overflow: hidden; mso-hide: all;">
    ${isMaybe ? "You're pencilled in for" : "You're on-on for"} ${escapeHtml(opts.eventTitle)} — ${escapeHtml(opts.dateLong)}. ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌
  </div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #f4e5b8; padding: 30px 12px;">
    <tr><td align="center">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width: 600px; max-width: 100%;">

        <tr><td style="background: #15110a; border-bottom: 6px solid #ee5a17; padding: 18px 28px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td valign="middle" style="font-family: 'Bangers', 'Impact', sans-serif; font-size: 22px; color: #f4e5b8; letter-spacing: 0.06em; text-transform: uppercase;">
              Steel City H3
            </td>
            <td align="right" valign="middle" style="font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">
              ${eyebrow}
            </td>
          </tr></table>
        </td></tr>

        <tr><td style="padding: 30px 0 18px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #faefcc; border: 4px solid #15110a;">

            <tr><td align="center" style="padding: 40px 32px 12px;">
              <div style="font-family: 'Bangers', 'Impact', sans-serif; font-size: 48px; line-height: 0.92; letter-spacing: 0.025em; color: #15110a; text-transform: uppercase;">
                ${bigHeadline}<br/>
                <span style="color: #ee5a17;">${escapeHtml(opts.greetingName)}!</span>
              </div>
            </td></tr>

            <tr><td align="center" style="padding: 8px 32px 22px;">
              <p style="margin: 0; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 16px; font-weight: 600; color: #3a2e1f; line-height: 1.5;">
                ${introLead}
                <b style="color: #15110a;">${escapeHtml(opts.eventTitle)}</b> on
                <b style="color: #15110a;">${escapeHtml(opts.dateLong)}</b>
                at <b style="color: #15110a;">${escapeHtml(opts.timeFriendly)}</b>.${introTail}
              </p>
            </td></tr>

            <!-- details strip -->
            <tr><td style="padding: 0 32px 24px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #f4e5b8; border: 3px solid #15110a;">
                <tr>
                  <td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700; width: 90px;">Where</td>
                  <td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(opts.locationSummary)}</td>
                </tr>
                <tr>
                  <td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">Hares</td>
                  <td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(opts.hares)}</td>
                </tr>
                <tr>
                  <td style="padding: 12px 18px; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">On-on</td>
                  <td style="padding: 12px 18px; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(opts.onOnPub)}</td>
                </tr>
              </table>
            </td></tr>

            ${guestsBlock}

            <tr><td style="padding: 0 32px 22px;">
              <p style="margin: 0; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 15px; color: #3a2e1f; line-height: 1.55; font-weight: 500;">
                ${shoesLine}
              </p>
            </td></tr>

            ${whatsappBlock}

            <tr><td align="center" style="padding: 0 32px 36px;">
              <table role="presentation" cellpadding="0" cellspacing="0"><tr>
                <td>
                  <a href="${escapeHtml(opts.eventUrl)}" style="display: inline-block; background: #ee5a17; color: #15110a; padding: 14px 28px; font-family: 'Bangers', 'Impact', sans-serif; font-size: 22px; letter-spacing: 0.06em; text-transform: uppercase; text-decoration: none; border: 3px solid #15110a; box-shadow: 5px 5px 0 #15110a;">
                    ▸ View the hash
                  </a>
                </td>
              </tr></table>
              <p style="margin: 14px 0 0; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 13px; color: #6e5f48; font-weight: 600;">
                Can't make it after all? Update your on-on on the same page.
              </p>
            </td></tr>

          </table>
        </td></tr>

        <tr><td>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td align="center" style="font-family: 'Bangers', 'Impact', sans-serif; font-size: 32px; letter-spacing: 0.04em; color: #ee5a17; text-transform: uppercase;">
              ON-ON!
            </td>
          </tr><tr>
            <td align="center" style="padding-top: 10px; font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 11px; letter-spacing: 0.14em; text-transform: uppercase; color: #6e5f48; font-weight: 700;">
              Steel City H3 · Sheffield · Year 1
            </td>
          </tr></table>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildEmailText(opts: {
  greetingName: string;
  eventTitle: string;
  dateLong: string;
  timeFriendly: string;
  locationSummary: string;
  hares: string;
  onOnPub: string;
  guestsCount: number;
  amountPerHead: number;
  eventUrl: string;
  status: "on_on" | "maybe";
  whatsappLink: string;
}): string {
  // Plain-text fallback for clients that don't render HTML
  const isMaybe = opts.status === "maybe";
  const lead = isMaybe
    ? `Cheers, ${opts.greetingName} — we've pencilled you in for ${opts.eventTitle} on ${opts.dateLong} at ${opts.timeFriendly}. Flip to on-on on the page when you know for sure.`
    : `Right then, ${opts.greetingName} — you're booked in for ${opts.eventTitle} on ${opts.dateLong} at ${opts.timeFriendly}.`;
  const guestsLine = opts.guestsCount > 0
    ? `\nBringing: ${opts.guestsCount} hash virgin${opts.guestsCount === 1 ? "" : "s"}. They're on your tab for subs — about £${(opts.guestsCount * opts.amountPerHead).toFixed(2)} cash on the day. Plus your own £${opts.amountPerHead.toFixed(2)}.\n`
    : "";
  const whatsappLine = opts.whatsappLink
    ? `\nJoin the event WhatsApp group: ${opts.whatsappLink}\n`
    : "";
  return `${lead}

Where: ${opts.locationSummary}
Hares: ${opts.hares}
On-on: ${opts.onOnPub}
${guestsLine}${whatsappLine}
Wear shoes you don't love.

Changed your mind? Update your on-on here: ${opts.eventUrl}

On-on!
Steel City H3`;
}

// ---------------------------------------------------------------------------
// Path B helper: send the admin-facing "X offered to hare Y" email
// ---------------------------------------------------------------------------

async function sendHareVolunteerEmail(opts: {
  event: { id: number; run_number: number; title: string; event_date: string; start_time: string; location_summary: string | null; location_full: string | null; status: string };
  profile: { real_name: string | null; hash_name: string | null; phone: string | null };
  userEmail: string;
}): Promise<Response> {
  const smtpHost = Deno.env.get("SMTP_HOST");
  const smtpPort = Number(Deno.env.get("SMTP_PORT") || "465");
  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPass = Deno.env.get("SMTP_PASS");
  const smtpFrom = Deno.env.get("SMTP_FROM") || `Steel City H3 <${smtpUser}>`;
  const adminTo  = Deno.env.get("HARE_NOTIFY_EMAIL") || "on-on@steelcityh3.org";
  if (!smtpHost || !smtpUser || !smtpPass) {
    return jsonResponse(500, { error: "missing_smtp_env" });
  }

  const siteUrl = (Deno.env.get("SITE_URL") || "https://steelcityh3.org").replace(/\/$/, "");
  const adminEventUrl = `${siteUrl}/admin-event.html?id=${opts.event.id}`;
  const publicEventUrl = `${siteUrl}/event.html?id=${opts.event.id}`;

  const greetingName =
    (opts.profile.hash_name && opts.profile.hash_name.trim()) ||
    opts.profile.real_name ||
    opts.userEmail;
  const realName = opts.profile.real_name || "(no real name set)";
  const phone = opts.profile.phone || "(no phone set)";
  const dateLong = formatLongDate(opts.event.event_date);
  const timeFriendly = formatTimeFriendly(opts.event.start_time);
  const where = opts.event.location_full || opts.event.location_summary || "TBC";

  const subject = `Hare volunteer: ${greetingName} for ${opts.event.title}`;

  const html = `<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
  @import url('https://fonts.googleapis.com/css2?family=Bangers&family=Nunito:wght@500;600;700;800&family=JetBrains+Mono:wght@500;700&display=swap');
  body { margin: 0; background: #f4e5b8; font-family: 'Nunito', Helvetica, Arial, sans-serif; color: #15110a; }
  a { color: #ee5a17; }
</style>
</head>
<body style="background: #f4e5b8; padding: 30px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width: 600px; max-width: 100%;">

        <tr><td style="background: #15110a; border-bottom: 6px solid #ee5a17; padding: 18px 28px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td valign="middle" style="font-family: 'Bangers', sans-serif; font-size: 22px; color: #f4e5b8; letter-spacing: 0.06em; text-transform: uppercase;">Steel City H3</td>
            <td align="right" valign="middle" style="font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">▸ Hare volunteer</td>
          </tr></table>
        </td></tr>

        <tr><td style="padding: 30px 0 18px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #faefcc; border: 4px solid #15110a;">

            <tr><td align="center" style="padding: 36px 32px 8px;">
              <div style="font-family: 'Bangers', sans-serif; font-size: 42px; line-height: 0.92; letter-spacing: 0.025em; color: #15110a; text-transform: uppercase;">
                Volunteer hare!
              </div>
            </td></tr>

            <tr><td style="padding: 16px 32px 6px;">
              <p style="margin: 0; font-size: 16px; font-weight: 600; color: #3a2e1f; line-height: 1.55;">
                <b style="color: #15110a;">${escapeHtml(greetingName)}</b> has offered to hare Run #${opts.event.run_number} — <b style="color: #15110a;">${escapeHtml(opts.event.title)}</b>.
              </p>
            </td></tr>

            <tr><td style="padding: 18px 32px 24px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #f4e5b8; border: 3px solid #15110a;">
                <tr><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700; width: 110px;">Event</td><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-size: 15px; color: #15110a; font-weight: 700;">Run #${opts.event.run_number} · ${escapeHtml(opts.event.title)}</td></tr>
                <tr><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">When</td><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(dateLong)} · ${escapeHtml(timeFriendly)}</td></tr>
                <tr><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">Where</td><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(where)}</td></tr>
                <tr><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">Hash name</td><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(opts.profile.hash_name || "—")}</td></tr>
                <tr><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">Real name</td><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(realName)}</td></tr>
                <tr><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">Phone</td><td style="padding: 12px 18px; border-bottom: 2px solid #15110a; font-size: 15px; color: #15110a; font-weight: 700;">${escapeHtml(phone)}</td></tr>
                <tr><td style="padding: 12px 18px; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #ee5a17; font-weight: 700;">Email</td><td style="padding: 12px 18px; font-size: 15px; color: #15110a; font-weight: 700;"><a href="mailto:${escapeHtml(opts.userEmail)}" style="color: #a72020;">${escapeHtml(opts.userEmail)}</a></td></tr>
              </table>
            </td></tr>

            <tr><td align="center" style="padding: 0 32px 32px;">
              <a href="${adminEventUrl}" style="display: inline-block; background: #ee5a17; color: #15110a; padding: 14px 28px; font-family: 'Bangers', sans-serif; font-size: 20px; letter-spacing: 0.06em; text-transform: uppercase; text-decoration: none; border: 3px solid #15110a; box-shadow: 5px 5px 0 #15110a;">▸ Manage in admin</a>
              <p style="margin: 12px 0 0; font-size: 13px; color: #6e5f48;">Or view publicly: <a href="${publicEventUrl}" style="color: #a72020;">${publicEventUrl}</a></p>
            </td></tr>

          </table>
        </td></tr>

        <tr><td>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td align="center" style="font-family: 'Bangers', sans-serif; font-size: 28px; letter-spacing: 0.04em; color: #ee5a17; text-transform: uppercase;">ON-ON!</td>
          </tr><tr>
            <td align="center" style="padding-top: 10px; font-family: 'JetBrains Mono', monospace; font-size: 11px; letter-spacing: 0.14em; text-transform: uppercase; color: #6e5f48; font-weight: 700;">Auto-sent from Steel City H3 admin</td>
          </tr></table>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;

  const text =
    `Hare volunteer: ${greetingName} for ${opts.event.title}\n\n` +
    `Event:     Run #${opts.event.run_number} · ${opts.event.title}\n` +
    `When:      ${dateLong} · ${timeFriendly}\n` +
    `Where:     ${where}\n` +
    `Hash name: ${opts.profile.hash_name || "—"}\n` +
    `Real name: ${realName}\n` +
    `Phone:     ${phone}\n` +
    `Email:     ${opts.userEmail}\n\n` +
    `Manage:    ${adminEventUrl}\n` +
    `Public:    ${publicEventUrl}\n\n` +
    `On-on!`;

  const useImplicitTls = smtpPort !== 587;
  const client = new SMTPClient({
    connection: {
      hostname: smtpHost, port: smtpPort, tls: useImplicitTls,
      auth: { username: smtpUser, password: smtpPass },
    },
  });

  try {
    await client.send({
      from:    smtpFrom,
      to:      adminTo,
      subject,
      content: text,
      html,
      mimeContent: [
        { mimeType: "text/plain; charset=utf-8",                 content: text },
        { mimeType: "text/html;  charset=utf-8; format=flowed",  content: html },
      ],
      headers: {
        "List-Unsubscribe":      "<mailto:on-on@steelcityh3.org?subject=Unsubscribe%20me>",
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        "X-Entity-Ref-ID":       `hare-${opts.event.id}`,
      },
    });
  } catch (err) {
    console.error("[rsvp-email] hare-notify SMTP send failed:", err);
    return jsonResponse(500, { error: "smtp_send_failed", detail: String(err) });
  } finally {
    try { await client.close(); } catch (_) { /* ignore */ }
  }

  return jsonResponse(200, { sent: true, to: adminTo, kind: "hare_volunteer", event_id: opts.event.id });
}

serve(async (req) => {
  // CORS preflight — must respond before any auth/method checks
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse(500, { error: "missing_supabase_env" });
  }

  // Identify the caller from their session JWT (supabase.functions.invoke
  // attaches this automatically). Verify JWT must be ON for the function.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return jsonResponse(401, { error: "unauthorized", detail: userErr?.message });
  }
  const user = userData.user;

  // Parse the request body — could be email request OR account-delete
  let body: InvokeBody;
  try {
    body = await req.json() as InvokeBody;
  } catch (err) {
    return jsonResponse(400, { error: "invalid_json", detail: String(err) });
  }

  // Service-role client bypasses RLS for the data fetches + admin auth ops
  const supabase = createClient(supabaseUrl, serviceKey);

  // ---- Op: delete_account ------------------------------------------------
  if ((body as DeleteAccountBody)?.op === "delete_account") {
    const dBody = body as DeleteAccountBody;
    const targetUid = dBody.target_user_id || user.id;
    const isSelf = targetUid === user.id;

    if (!isSelf) {
      // Admin path — caller must be admin
      const { data: roleRow } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", user.id)
        .eq("role", "admin")
        .maybeSingle();
      if (!roleRow) {
        return jsonResponse(403, { error: "forbidden", detail: "Admin role required to delete other users." });
      }
    }

    // Delete the auth.users row — cascade handles profiles → rsvps,
    // event_hares, user_roles. admin_actions.actor_id is ON DELETE SET NULL
    // so the audit log survives but anonymises.
    const { error: delErr } = await supabase.auth.admin.deleteUser(targetUid);
    if (delErr) {
      console.error("[rsvp-email] admin.deleteUser failed:", delErr);
      return jsonResponse(500, { error: "delete_failed", detail: delErr.message });
    }
    return jsonResponse(200, { deleted: true, user_id: targetUid, self: isSelf });
  }

  // ---- Otherwise: email request (existing logic) ------------------------
  const eBody = body as EmailBody;
  if (!eBody?.event_id || typeof eBody.event_id !== "number") {
    return jsonResponse(400, { error: "missing_event_id" });
  }

  const notifyType = eBody.notify === "hare_volunteer" ? "hare_volunteer" : "rsvp_confirmation";

  // ---- Path A: hare_volunteer → notify admin mailbox ---------------------
  if (notifyType === "hare_volunteer") {
    // Verify the user is actually a volunteer hare for this event
    const hareRes = await supabase
      .from("event_hares")
      .select("volunteered")
      .eq("event_id", eBody.event_id)
      .eq("user_id", user.id)
      .maybeSingle();
    if (hareRes.error || !hareRes.data) {
      return jsonResponse(200, { skipped: true, reason: "no hare row for this user+event" });
    }

    const [eventRes2, profileRes2] = await Promise.all([
      supabase.from("events").select("*").eq("id", eBody.event_id).single(),
      supabase.from("profiles").select("real_name, hash_name, phone").eq("id", user.id).single(),
    ]);
    if (eventRes2.error || !eventRes2.data) {
      return jsonResponse(500, { error: "event_fetch_failed", detail: eventRes2.error?.message });
    }
    const event2 = eventRes2.data;
    const profile2 = profileRes2.data || {};

    return await sendHareVolunteerEmail({
      event: event2,
      profile: profile2,
      userEmail: user.email,
    });
  }

  // ---- Path B: rsvp_confirmation (default) — user "You're on-on" --------
  const rsvpRes = await supabase
    .from("rsvps")
    .select("status, guests_count")
    .eq("user_id", user.id)
    .eq("event_id", eBody.event_id)
    .maybeSingle();

  if (rsvpRes.error) {
    return jsonResponse(500, { error: "rsvp_check_failed", detail: rsvpRes.error.message });
  }
  if (!rsvpRes.data) {
    return jsonResponse(200, { skipped: true, reason: "no rsvp for this user+event" });
  }
  // Confirmation goes out for on_on AND maybe (both get the WhatsApp link so
  // they can jump into the group early). not_this_time gets nothing.
  if (rsvpRes.data.status !== "on_on" && rsvpRes.data.status !== "maybe") {
    return jsonResponse(200, { skipped: true, reason: "rsvp not on_on/maybe" });
  }
  const rsvpStatus = rsvpRes.data.status as "on_on" | "maybe";
  const guestsCount = rsvpRes.data.guests_count || 0;

  const [eventRes, profileRes] = await Promise.all([
    supabase.from("events").select("*").eq("id", eBody.event_id).single(),
    supabase.from("profiles").select("real_name, hash_name").eq("id", user.id).single(),
  ]);

  if (eventRes.error || !eventRes.data) {
    return jsonResponse(500, { error: "event_fetch_failed", detail: eventRes.error?.message });
  }

  const event = eventRes.data;
  const profile = profileRes.data || {};

  if (!user.email) {
    return jsonResponse(200, { skipped: true, reason: "user has no email" });
  }

  // Decide on a greeting name — hash name if they have one, else real name's
  // first word, else fall back to "hasher"
  const greetingName =
    (profile.hash_name && profile.hash_name.trim()) ||
    (profile.real_name && profile.real_name.trim().split(/\s+/)[0]) ||
    "hasher";

  const siteUrl = (Deno.env.get("SITE_URL") || "https://steelcityh3.org").replace(/\/$/, "");
  const eventUrl = `${siteUrl}/event.html?id=${event.id}`;
  const amountPerHead = Number(event.amount_per_head ?? 5);

  const opts = {
    greetingName,
    eventTitle:      event.title,
    dateLong:        formatLongDate(event.event_date),
    timeFriendly:    formatTimeFriendly(event.start_time),
    locationSummary: event.location_summary || "TBC",
    hares:           event.hares || "TBC",
    onOnPub:         event.on_on_pub || "TBC — confirmed on the day",
    guestsCount,
    amountPerHead,
    eventUrl,
    status:          rsvpStatus,
    whatsappLink:    event.whatsapp_group_link || "",
  };

  const html = buildEmailHtml(opts);
  const text = buildEmailText(opts);

  const smtpHost = Deno.env.get("SMTP_HOST");
  const smtpPort = Number(Deno.env.get("SMTP_PORT") || "465");
  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPass = Deno.env.get("SMTP_PASS");
  const smtpFrom = Deno.env.get("SMTP_FROM") || `Steel City H3 <${smtpUser}>`;

  if (!smtpHost || !smtpUser || !smtpPass) {
    return jsonResponse(500, { error: "missing_smtp_env" });
  }

  // Use implicit TLS on port 465 (SMTPS). STARTTLS on port 587 fails in the
  // Edge Functions runtime due to a known Deno startTls() resource-ID bug:
  //   BadResource: Bad resource ID at Object.startTls
  // 465 connects with TLS from the start — no upgrade dance, no broken call.
  // IONOS supports both ports; we just pick the one that works here.
  const useImplicitTls = smtpPort !== 587;

  const client = new SMTPClient({
    connection: {
      hostname: smtpHost,
      port:     smtpPort,
      tls:      useImplicitTls,
      auth: { username: smtpUser, password: smtpPass },
    },
  });

  try {
    // mimeContent forces denomailer to emit explicit multipart/alternative
    // with both text/plain and text/html parts (mail-tester was flagging
    // MIME_HTML_ONLY even though we passed `content` + `html`, suggesting
    // the auto-MIME wasn't building the plain-text part properly). Custom
    // headers add List-Unsubscribe so receiving filters recognise it as
    // legitimate transactional mail.
    await client.send({
      from:    smtpFrom,
      to:      user.email,
      subject: rsvpStatus === "maybe"
        ? `You're a maybe for ${event.title}`
        : `You're on-on for ${event.title}`,
      content: text,
      html,
      mimeContent: [
        { mimeType: "text/plain; charset=utf-8",                 content: text },
        { mimeType: "text/html;  charset=utf-8; format=flowed",  content: html },
      ],
      headers: {
        "List-Unsubscribe":      "<mailto:on-on@steelcityh3.org?subject=Unsubscribe%20me>",
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        "X-Entity-Ref-ID":       `rsvp-${event.id}-${user.id}`,
      },
    });
  } catch (err) {
    console.error("[rsvp-email] SMTP send failed:", err);
    return jsonResponse(500, { error: "smtp_send_failed", detail: String(err) });
  } finally {
    try { await client.close(); } catch (_) { /* ignore */ }
  }

  return jsonResponse(200, { sent: true, to: user.email, event_id: event.id });
});
