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

interface InvokeBody {
  event_id: number;
}

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
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
}): string {
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
            cash on the day, all to St Luke's. Plus your own £${opts.amountPerHead.toFixed(2)}.
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
    You're on-on for ${escapeHtml(opts.eventTitle)} — ${escapeHtml(opts.dateLong)}. ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌ ‌
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
              ▸ You're on-on!
            </td>
          </tr></table>
        </td></tr>

        <tr><td style="padding: 30px 0 18px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #faefcc; border: 4px solid #15110a;">

            <tr><td align="center" style="padding: 40px 32px 12px;">
              <div style="font-family: 'Bangers', 'Impact', sans-serif; font-size: 48px; line-height: 0.92; letter-spacing: 0.025em; color: #15110a; text-transform: uppercase;">
                You're on-on,<br/>
                <span style="color: #ee5a17;">${escapeHtml(opts.greetingName)}!</span>
              </div>
            </td></tr>

            <tr><td align="center" style="padding: 8px 32px 22px;">
              <p style="margin: 0; font-family: 'Nunito', Helvetica, Arial, sans-serif; font-size: 16px; font-weight: 600; color: #3a2e1f; line-height: 1.5;">
                Right then — you're booked in for
                <b style="color: #15110a;">${escapeHtml(opts.eventTitle)}</b> on
                <b style="color: #15110a;">${escapeHtml(opts.dateLong)}</b>
                at <b style="color: #15110a;">${escapeHtml(opts.timeFriendly)}</b>.
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
                Wear shoes you don't love. We'll add you to the event WhatsApp
                group nearer the time.
              </p>
            </td></tr>

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
}): string {
  // Plain-text fallback for clients that don't render HTML
  const guestsLine = opts.guestsCount > 0
    ? `\nBringing: ${opts.guestsCount} hash virgin${opts.guestsCount === 1 ? "" : "s"}. They're on your tab for subs — about £${(opts.guestsCount * opts.amountPerHead).toFixed(2)} cash on the day, all to St Luke's. Plus your own £${opts.amountPerHead.toFixed(2)}.\n`
    : "";
  return `Right then, ${opts.greetingName} — you're booked in for ${opts.eventTitle} on ${opts.dateLong} at ${opts.timeFriendly}.

Where: ${opts.locationSummary}
Hares: ${opts.hares}
On-on: ${opts.onOnPub}
${guestsLine}
Wear shoes you don't love. We'll add you to the event WhatsApp group nearer the time.

Can't make it after all? Update your on-on here: ${opts.eventUrl}

On-on!
Steel City H3`;
}

serve(async (req) => {
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

  // Parse the request body — frontend passes just event_id
  let body: InvokeBody;
  try {
    body = await req.json();
  } catch (err) {
    return jsonResponse(400, { error: "invalid_json", detail: String(err) });
  }
  if (!body?.event_id || typeof body.event_id !== "number") {
    return jsonResponse(400, { error: "missing_event_id" });
  }

  // Use the service-role client for the actual data fetch so RLS doesn't
  // get in the way of reading the user's own profile (it would normally,
  // but service role bypasses).
  const supabase = createClient(supabaseUrl, serviceKey);

  // Verify the user actually has an on_on RSVP for this event — guards
  // against someone calling the function with arbitrary event_ids
  const rsvpRes = await supabase
    .from("rsvps")
    .select("status, guests_count")
    .eq("user_id", user.id)
    .eq("event_id", body.event_id)
    .maybeSingle();

  if (rsvpRes.error) {
    return jsonResponse(500, { error: "rsvp_check_failed", detail: rsvpRes.error.message });
  }
  if (!rsvpRes.data) {
    return jsonResponse(200, { skipped: true, reason: "no rsvp for this user+event" });
  }
  if (rsvpRes.data.status !== "on_on") {
    return jsonResponse(200, { skipped: true, reason: "rsvp not on_on" });
  }
  const guestsCount = rsvpRes.data.guests_count || 0;

  // Fetch event + profile in parallel
  const [eventRes, profileRes] = await Promise.all([
    supabase.from("events").select("*").eq("id", body.event_id).single(),
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
  };

  const html = buildEmailHtml(opts);
  const text = buildEmailText(opts);

  const smtpHost = Deno.env.get("SMTP_HOST");
  const smtpPort = Number(Deno.env.get("SMTP_PORT") || "587");
  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPass = Deno.env.get("SMTP_PASS");
  const smtpFrom = Deno.env.get("SMTP_FROM") || `Steel City H3 <${smtpUser}>`;

  if (!smtpHost || !smtpUser || !smtpPass) {
    return jsonResponse(500, { error: "missing_smtp_env" });
  }

  const client = new SMTPClient({
    connection: {
      hostname: smtpHost,
      port:     smtpPort,
      tls:      false,  // port 587 uses STARTTLS — denomailer upgrades automatically
      auth: { username: smtpUser, password: smtpPass },
    },
  });

  try {
    await client.send({
      from:    smtpFrom,
      to:      user.email,
      subject: `You're on-on for ${event.title}`,
      content: text,
      html,
    });
  } catch (err) {
    console.error("[rsvp-email] SMTP send failed:", err);
    return jsonResponse(500, { error: "smtp_send_failed", detail: String(err) });
  } finally {
    try { await client.close(); } catch (_) { /* ignore */ }
  }

  return jsonResponse(200, { sent: true, to: user.email, event_id: event.id });
});
