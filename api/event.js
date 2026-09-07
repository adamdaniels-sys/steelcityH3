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
const DEFAULT_IMAGE = SITE_URL + '/og-cover.jpg';

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

// Schema.org Event JSON-LD.
//
// Why here and not in event.html: this function already has the event row in
// hand, so every event gets structured data with nothing for admins to author.
// It's also server-rendered, so crawlers and AI assistants that never run our
// client JS still see the date, place and status as machine-readable fields
// rather than prose they'd have to infer from.
//
// eventStatus/eventAttendanceMode/startDate are the fields Google and the
// assistants actually read; the rest is bonus context.
//
// The event_status enum is: planning | hares_wanted | open | ready | closed |
// completed. Only "closed" means cancelled — event.html shows the "this hash
// was cancelled" banner on it. Everything else is a live or finished hash, and
// schema.org has no "finished" status, so a past hash stays EventScheduled.
const EVENT_STATUS_LD = {
  closed: 'https://schema.org/EventCancelled',
};

function buildEventJsonLd(ev, o) {
  // A hash is a physical trail round Sheffield — never online.
  const ld = {
    '@context': 'https://schema.org',
    '@type': 'SportsEvent',
    name: o.title,
    description: o.description,
    url: o.url,
    image: o.image,
    eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode',
    eventStatus: EVENT_STATUS_LD[ev.status] || 'https://schema.org/EventScheduled',
    organizer: {
      '@type': 'SportsClub',
      name: 'Steel City H3',
      alternateName: 'Steel City Hash House Harriers',
      url: SITE_URL + '/',
    },
    location: {
      '@type': 'Place',
      // location_full is the real address when set; location_summary is the
      // public teaser ("a pub in Hathersage"). Fall back to the city.
      name: ev.location_summary || ev.location_full || 'Sheffield',
      address: {
        '@type': 'PostalAddress',
        streetAddress: ev.location_full || undefined,
        addressLocality: 'Sheffield',
        addressCountry: 'GB',
      },
    },
  };

  // startDate: date alone is valid, but date+time is far more useful to an
  // assistant answering "when is the next hash?". Times are UK local.
  if (ev.event_date) {
    ld.startDate = ev.start_time
      ? `${ev.event_date}T${String(ev.start_time).slice(0, 8)}`
      : ev.event_date;
  }

  // The sub is per head and payable on the day, not a ticketed sale. Marking
  // it up as an Offer still tells an assistant what it costs to turn up.
  if (ev.amount_per_head != null && Number(ev.amount_per_head) > 0) {
    ld.offers = {
      '@type': 'Offer',
      price: String(Number(ev.amount_per_head).toFixed(2)),
      priceCurrency: 'GBP',
      availability: 'https://schema.org/InStock',
      url: o.url,
    };
  }

  if (ev.distance_miles != null) {
    ld.distance = { '@type': 'Distance', name: `${ev.distance_miles} miles` };
  }

  // Strip undefined so they don't serialise as nulls.
  return JSON.stringify(ld, (_k, v) => (v === undefined ? undefined : v), 2);
}

function buildOgTags(o, isEvent) {
  const t = escapeHtml(o.title);
  const d = escapeHtml(o.description);
  const img = escapeHtml(o.image);
  const url = escapeHtml(o.url);
  return [
    `<meta property="og:type" content="${isEvent ? 'event' : 'website'}" />`,
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

function injectInto(template, ogHtml, pageTitle, id, jsonLd, canonical) {
  let html = template.replace(/<!-- OG_BLOCK_START[\s\S]*?OG_BLOCK_END -->/, ogHtml);
  html = html.replace(/<title>[\s\S]*?<\/title>/, `<title>${escapeHtml(pageTitle)}</title>`);
  if (canonical) {
    html = html.replace(
      /<!-- SCH3_CANONICAL -->/,
      `<link rel="canonical" href="${escapeHtml(canonical)}" />`,
    );
  }
  if (jsonLd) {
    // </script> inside the JSON would close this block early; \u003c is the
    // standard escape and stays valid JSON.
    html = html.replace(
      /<!-- SCH3_JSONLD -->/,
      `<script type="application/ld+json">\n${jsonLd.replace(/</g, '\\u003c')}\n</script>`,
    );
  }
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
  let jsonLd = null;

  if (/^\d+$/.test(id)) {
    try {
      const r = await fetch(
        `${SUPABASE_URL}/rest/v1/events?id=eq.${id}&select=run_number,title,event_date,start_time,location_summary,location_full,description,event_type,status,amount_per_head,distance_miles&limit=1`,
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
          jsonLd = buildEventJsonLd(ev, og);
        }
      }
    } catch (_) { /* keep the generic preview */ }
  }

  // Canonical: /event/:id is the real address — event.html?id= is the same page.
  const canonical = /^\d+$/.test(id) ? `${SITE_URL}/event/${id}` : null;
  const html = injectInto(template, buildOgTags(og, jsonLd != null), pageTitle, id, jsonLd, canonical);
  res.statusCode = 200;
  res.setHeader('content-type', 'text/html; charset=utf-8');
  // Edge-cache the rendered HTML briefly; the live event data still loads
  // client-side, so a few minutes of OG-tag staleness is harmless.
  res.setHeader('cache-control', 'public, s-maxage=300, stale-while-revalidate=600');
  // Write an explicit UTF-8 Buffer, and send its true byte length. Passing the
  // string straight to res.end() let the runtime re-encode it, which turned
  // every "·" into "Â·" and every "—" into "â€"" in the live page — visible in
  // the JSON-LD name and in link previews.
  const body = Buffer.from(html, 'utf8');
  res.setHeader('content-length', body.length);
  res.end(body);
};
