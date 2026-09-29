// Steel City H3 — one way of naming a hash's hares, shared by every page.
//
// Hares are recorded in three places: the member picker (event_hares, resolved
// by the get_events_hares_display RPC), additional_hares_text, and the free-text
// events.hares field used for people with no account. Pages used to read only
// one of these, so a past hash whose hares were picked from members still
// showed "TBC". This merges all three, dropping repeats.

export async function loadHareRows(supabase, ids) {
  const byEvent = new Map();
  if (!ids || !ids.length) return byEvent;
  const { data, error } = await supabase.rpc('get_events_hares_display', { p_event_ids: ids });
  if (error) { console.warn('[hares] display fetch failed:', error); return byEvent; }
  (data || []).forEach((row) => {
    if (!byEvent.has(row.event_id)) byEvent.set(row.event_id, []);
    byEvent.get(row.event_id).push(row);
  });
  return byEvent;
}

// Returns the joined names, or '' when nobody is recorded. The caller decides
// what an empty answer means ("TBC", "Volunteers wanted!", …).
export function composeHares(ev, hareRows) {
  const names = [];
  const seen = new Set();
  const add = (n) => {
    const name = String(n || '').trim();
    const key = name.toLowerCase();
    if (!name || seen.has(key)) return;
    seen.add(key);
    names.push(name);
  };
  (hareRows || []).forEach((h) => add(h.display_name));
  [ev.additional_hares_text, ev.hares].forEach((txt) => {
    String(txt || '').split(/\s*&\s*|\s*,\s*/).forEach(add);
  });
  return names.join(' & ');
}
