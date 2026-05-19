// Steel City H3 — shared auth/session module.
//
// Imported by every page that needs to know who's signed in. Owns:
//   - The supabase-js client singleton
//   - getSession(), getProfile(), isProfileComplete() helpers
//   - The header login chip + dropdown rendering
//   - signOut()
//
// The supabase client persists the session in localStorage automatically.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js';

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});

// ---------------------------------------------------------------------------
// Session + profile
// ---------------------------------------------------------------------------

export async function getSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    console.warn('[auth] getSession error:', error.message);
    return null;
  }
  return data.session ?? null;
}

export async function getProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .single();
  if (error) {
    console.warn('[auth] getProfile error:', error.message);
    return null;
  }
  return data;
}

export function isProfileComplete(profile) {
  return !!profile
    && !!(profile.real_name && profile.real_name.trim())
    && !!(profile.phone && profile.phone.trim());
}

export async function signOut() {
  await supabase.auth.signOut();
  // Clear the "redirect after sign-in" memo too, just in case.
  try { localStorage.removeItem('sch3-then'); } catch {}
  window.location.href = '/';
}

// ---------------------------------------------------------------------------
// "Where were they heading?" redirect memo — used so that clicking Sign in
// from an event page returns the user there after auth.
// ---------------------------------------------------------------------------

export function rememberThen(pathAndQuery) {
  if (!pathAndQuery) return;
  try { localStorage.setItem('sch3-then', pathAndQuery); } catch {}
}

export function consumeThen() {
  try {
    const value = localStorage.getItem('sch3-then');
    localStorage.removeItem('sch3-then');
    // Only allow same-origin relative paths — defence against open-redirect.
    if (value && value.startsWith('/') && !value.startsWith('//')) {
      return value;
    }
  } catch {}
  return '/';
}

// ---------------------------------------------------------------------------
// Header login chip — renders into the existing <a id="login-chip"> placeholder
// that all three pages already have in their <header>.
// ---------------------------------------------------------------------------

function initials(text) {
  if (!text) return '?';
  return text
    .split(/\s+/)
    .map((p) => p[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase() || '?';
}

function buildDropdown(displayName, av) {
  // Replace the static <a class="login-chip"> with a chip+dropdown component.
  const slot = document.getElementById('login-chip');
  if (!slot) return;

  const wrap = document.createElement('div');
  wrap.className = 'login-chip-wrap';
  wrap.innerHTML = `
    <button type="button" class="login-chip" id="login-chip" aria-haspopup="true" aria-expanded="false">
      <span class="av">${av}</span>
      <span class="login-name">${displayName}</span>
      <span class="caret" aria-hidden="true">▾</span>
    </button>
    <div class="login-dropdown" id="login-dropdown" role="menu" hidden>
      <a role="menuitem" href="/profile.html">▸ Your hash card</a>
      <button type="button" role="menuitem" id="signout-btn">↶ Sign out</button>
    </div>
  `;

  slot.replaceWith(wrap);

  const button = wrap.querySelector('#login-chip');
  const menu = wrap.querySelector('#login-dropdown');
  const signoutBtn = wrap.querySelector('#signout-btn');

  function close() {
    menu.hidden = true;
    button.setAttribute('aria-expanded', 'false');
  }
  function open() {
    menu.hidden = false;
    button.setAttribute('aria-expanded', 'true');
  }

  button.addEventListener('click', (e) => {
    e.stopPropagation();
    if (menu.hidden) open(); else close();
  });

  // Close on outside click and Escape
  document.addEventListener('click', (e) => {
    if (!wrap.contains(e.target)) close();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') close();
  });

  signoutBtn.addEventListener('click', () => {
    close();
    signOut();
  });
}

export async function renderLoginChip() {
  const session = await getSession();
  const chip = document.getElementById('login-chip');
  if (!chip) return;

  if (!session) {
    // Signed out — keep the existing static-link form, just make sure it
    // routes to /login.html with a `then` param if applicable.
    chip.setAttribute('href', '/login.html');
    const av = chip.querySelector('#login-av');
    const name = chip.querySelector('#login-name');
    if (av) av.textContent = '?';
    if (name) name.textContent = 'Sign in';
    return;
  }

  // Signed in — replace the chip with a button+dropdown.
  const profile = await getProfile();
  const displayName =
    (profile?.hash_name && profile.hash_name.trim())
      ? profile.hash_name.trim()
      : (profile?.real_name && profile.real_name.trim())
          ? profile.real_name.trim().split(/\s+/)[0]
          : session.user.email.split('@')[0];
  const av = initials(profile?.hash_name || profile?.real_name || session.user.email);

  buildDropdown(escapeHtml(displayName), escapeHtml(av));
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ---------------------------------------------------------------------------
// Auto-render on DOM ready for any page that imports this module.
// Pages that need finer control (auth-callback, login) can import without
// caring — they don't have a #login-chip in their header to update anyway,
// or they call renderLoginChip() themselves after a state change.
// ---------------------------------------------------------------------------

if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => { renderLoginChip(); });
  } else {
    renderLoginChip();
  }
}
