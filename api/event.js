// Steel City H3 — per-event link previews (Open Graph / Twitter cards).
//
// Static pages can't give Facebook/WhatsApp a per-event preview: their crawlers
// don't run the JavaScript that loads the event, so they'd only ever see the
// generic tags baked into event.html. This function fixes that.
//
// Routing: vercel.json rewrites  /event/:id  ->  /api/event?id=:id
// It reads the SAME event.html template from disk, fetches the event from
// Supabase (events are public-read), injects event-specific OG/Twitter tags +
// <title>, and injects the id so the page's client JS knows which event to load.
// Humans get the full interactive page; crawlers get a rich preview.
//
// No dependencies, no build step — plain Node (global fetch on Node 18+).
// event.html is bundled into this function via "includeFiles" in vercel.json.

const fs = require('fs');
const path = require('path');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://gxxlnpgvlghypmofualh.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_KXdPysEoJoHK2LRaqh33VQ_m-nOmWcp';
const SITE_URL = (process.env.SITE_URL || 'https://steelcityh3.org').replace(/\/$/, '');
const DEFAULT_IMAGE = SITE_URL + '/logo-original.jpg';

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function formatLongDate(iso) {
  if (!iso) return '';
  const d = new Date(iso + 'T12:00:00Z');
  return `${WEEKDAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

function formatTimeFriendly(t) {
  if (!t) return '';
  const [h, m] = t.split(':').map(Number);
  if (h === 12 && m === 0) return '12 noon';
  if (h === 0 && m === 0) return 'midnight';
  const period = h >= 12 ? 'pm' : 'am';
  const h12 = h % 12 || 12;
  return m === 0 ? `${h12}${period}` : `${h12}:${String(m).padStart(2, '0')}${period}`;
}

let TEMPLATE;
function loadTemplate() {
  if (TEMPLATE !== undefined) return TEMPLATE;
  const candidates = [
    path.join(process.cwd(), 'event.html'),
    path.join(__dirname, '..', 'event.html'),
    path.join(__dirname, 'event.html'),
  ];
  for (const p of candidates) {
    try { TEMPLATE = fs.readFileSync(p, 'utf8'); return TEMPLATE; } catch (_) { /* try next */ }
  }
  TEMPLATE = null;
  return null;
}

function buildOgTags(o) {
  const t = escapeHtml(o.title);
  const d = escapeHtml(o.description);
  const img = escapeHtml(o.image);
  const url = escapeHtml(o.url);
  return [
    '<meta property="og:type" content="website" />',
    '<meta property="og:site_name" content="Steel City H3" />',
    `<meta property="og:title" content="${t}" />`,
    `<meta property="og:description" content="${d}" />`,
    `<meta property="og:image" content="${img}" />`,
    `<meta property="og:url" content="${url}" />`,
    '<meta name="twitter:card" content="summary_large_image" />',
    `<meta name="twitter:title" content="${t}" />`,
    `<meta name="twitter:description" content="${d}" />`,
    `<meta name="twitter:image" content="${img}" />`,
  ].join('\n  ');
}

function injectInto(template, ogHtml, pageTitle, id) {
  let html = template.replace(/<!-- OG_BLOCK_START[\s\S]*?OG_BLOCK_END -->/, ogHtml);
  html = html.replace(/<title>[\s\S]*?<\/title>/, `<title>${escapeHtml(pageTitle)}</title>`);
  if (id) {
    html = html.replace(
      /<!-- SCH3_EVENT_ID -->/,
      `<script>window.__SCH3_EVENT_ID__=${JSON.stringify(String(id))};</script>`,
    );
  }
  return html;
}

module.exports = async (req, res) => {
  const template = loadTemplate();
  if (template == null) {
    // Template unreadable — don't show a broken page; send them to the homepage.
    res.statusCode = 302;
    res.setHeader('location', '/');
    res.end();
    return;
  }

  const id = req.query && req.query.id ? String(req.query.id) : '';

  let og = {
    title: 'Steel City H3 — Sheffield Hash House Harriers',
    description: 'A drinking club with a running problem. Find the next hash and RSVP.',
    image: DEFAULT_IMAGE,
    url: SITE_URL + (id ? `/event/${encodeURIComponent(id)}` : '/'),
  };
  let pageTitle = 'Steel City H3 — Hash detail';

  if (/^\d+$/.test(id)) {
    try {
      const r = await fetch(
        `${SUPABASE_URL}/rest/v1/events?id=eq.${id}&select=run_number,title,event_date,start_time,location_summary,location_full,description,event_type,status&limit=1`,
        { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
      );
      if (r.ok) {
        const rows = await r.json();
        const ev = Array.isArray(rows) ? rows[0] : null;
        if (ev) {
          const runLabel = ev.event_type === 'meetup' ? `Meet-up #${ev.run_number}` : `Run #${ev.run_number}`;
          const where = ev.location_summary || ev.location_full || 'Sheffield';
          const when = `${formatLongDate(ev.event_date)}${ev.start_time ? ' at ' + formatTimeFriendly(ev.start_time) : ''}`;
          const past = ev.status === 'completed';
          let desc = `${runLabel} · ${when} · ${where}.`;
          if (ev.description && ev.description.trim()) desc += ' ' + ev.description.trim();
          if (!past) desc += ' RSVP on the Steel City H3 site.';
          if (desc.length > 280) desc = desc.slice(0, 277) + '…';
          const title = `${runLabel} · ${ev.title} — Steel City H3`;
          og = { title, description: desc, image: DEFAULT_IMAGE, url: `${SITE_URL}/event/${id}` };
          pageTitle = title;
        }
      }
    } catch (_) { /* keep the generic preview */ }
  }

  const html = injectInto(template, buildOgTags(og), pageTitle, id);
  res.statusCode = 200;
  res.setHeader('content-type', 'text/html; charset=utf-8');
  // Edge-cache the rendered HTML briefly; the live event data still loads
  // client-side, so a few minutes of OG-tag staleness is harmless.
  res.setHeader('cache-control', 'public, s-maxage=300, stale-while-revalidate=600');
  res.end(html);
};
