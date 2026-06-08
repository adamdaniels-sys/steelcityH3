// Steel City H3 — dynamic sitemap.xml
//
// Routing: vercel.json rewrites  /sitemap.xml  ->  /api/sitemap
// Lists the homepage plus every public (non-draft) event, straight from
// Supabase (events are public-read), so search engines can discover each hash.
//
// No dependencies, no build step — plain Node (global fetch on Node 18+).

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://gxxlnpgvlghypmofualh.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_KXdPysEoJoHK2LRaqh33VQ_m-nOmWcp';
const SITE_URL = (process.env.SITE_URL || 'https://steelcityh3.org').replace(/\/$/, '');

function urlTag(loc, lastmod) {
  return `  <url>\n    <loc>${loc}</loc>${lastmod ? `\n    <lastmod>${lastmod}</lastmod>` : ''}\n  </url>`;
}

module.exports = async (req, res) => {
  const urls = [urlTag(`${SITE_URL}/`)];

  try {
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/events?select=id,event_date,status&status=neq.planning&order=event_date.desc`,
      { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
    );
    if (r.ok) {
      const rows = await r.json();
      for (const ev of Array.isArray(rows) ? rows : []) {
        if (ev && ev.id != null) {
          const lastmod = ev.event_date ? String(ev.event_date).slice(0, 10) : null;
          urls.push(urlTag(`${SITE_URL}/event/${encodeURIComponent(ev.id)}`, lastmod));
        }
      }
    }
  } catch (_) {
    /* Supabase unreachable — still emit a valid sitemap with the homepage. */
  }

  const xml =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    urls.join('\n') +
    '\n</urlset>\n';

  res.statusCode = 200;
  res.setHeader('content-type', 'application/xml; charset=utf-8');
  res.setHeader('cache-control', 'public, s-maxage=3600, stale-while-revalidate=86400');
  res.end(xml);
};
