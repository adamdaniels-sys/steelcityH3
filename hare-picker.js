// Hare picker — searchable multi-select of members for the admin event form.
//
// Usage:
//   import { HarePicker } from './hare-picker.js';
//   const picker = new HarePicker(hostElement, allMembers);
//   picker.setSelected([id1, id2]);
//   picker.onChange(ids => { ... });
//
// Each `member` is { id, hash_name, real_name }. Admins are allowed to see
// real names (RLS lets admins read all profiles); the picker searches both.

export class HarePicker {
  constructor(host, members) {
    this.host = host;
    this.members = members;
    this.selectedIds = new Set();
    this.changeListeners = [];
    this.activeIndex = -1;
    this._render();
  }

  setSelected(ids) {
    this.selectedIds = new Set(ids);
    this._render();
  }

  getSelected() {
    return [...this.selectedIds];
  }

  onChange(fn) {
    this.changeListeners.push(fn);
  }

  _emit() {
    for (const fn of this.changeListeners) fn(this.getSelected());
  }

  _escapeHtml(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  _displayName(m) {
    return (m.hash_name && m.hash_name.trim()) || m.real_name || m.email || 'Member';
  }

  _matches(member, q) {
    const needle = q.toLowerCase().trim();
    if (!needle) return true;
    return (member.hash_name || '').toLowerCase().includes(needle)
        || (member.real_name || '').toLowerCase().includes(needle);
  }

  _render() {
    this.host.classList.add('combobox');
    this.host.innerHTML = `
      <div class="combobox-pills" data-role="pills"></div>
      <div class="combobox-results" data-role="results" hidden></div>
    `;
    this._renderPills();
    this._wireUp();
  }

  _renderPills() {
    const wrap = this.host.querySelector('[data-role="pills"]');
    const pills = [...this.selectedIds].map((id) => {
      const m = this.members.find((x) => x.id === id);
      if (!m) return '';
      return `
        <span class="combobox-pill">
          ${this._escapeHtml(this._displayName(m))}
          <button type="button" aria-label="Remove ${this._escapeHtml(this._displayName(m))}" data-remove="${id}">×</button>
        </span>
      `;
    }).join('');

    wrap.innerHTML = `
      ${pills}
      <input type="text" class="combobox-input" placeholder="${this.selectedIds.size > 0 ? 'Add another…' : 'Search members by hash or real name…'}" />
    `;
  }

  _wireUp() {
    const wrap = this.host.querySelector('[data-role="pills"]');
    const results = this.host.querySelector('[data-role="results"]');
    const input = wrap.querySelector('.combobox-input');

    // Click the host to focus input
    this.host.addEventListener('click', (e) => {
      if (e.target === this.host) input.focus();
    });

    // Remove pill
    wrap.addEventListener('click', (e) => {
      const removeBtn = e.target.closest('button[data-remove]');
      if (removeBtn) {
        e.stopPropagation();
        const id = removeBtn.dataset.remove;
        this.selectedIds.delete(id);
        this._renderPills();
        this._wireUp();
        this._emit();
        return;
      }
    });

    // Open results on focus + as user types
    input.addEventListener('focus', () => this._showResults(input.value));
    input.addEventListener('input', () => this._showResults(input.value));
    input.addEventListener('keydown', (e) => this._handleKey(e, input));

    // Click outside closes results
    document.addEventListener('click', (e) => {
      if (!this.host.contains(e.target)) {
        results.hidden = true;
      }
    });

    results.addEventListener('click', (e) => {
      const btn = e.target.closest('button[data-pick]');
      if (!btn) return;
      this._pick(btn.dataset.pick, input);
    });
  }

  _availableMembers(q) {
    return this.members
      .filter((m) => !this.selectedIds.has(m.id))
      .filter((m) => this._matches(m, q))
      .slice(0, 15);
  }

  _showResults(q) {
    const results = this.host.querySelector('[data-role="results"]');
    const available = this._availableMembers(q);
    this.activeIndex = -1;
    if (available.length === 0) {
      results.innerHTML = `<div class="empty">No matches — try a different name.</div>`;
    } else {
      results.innerHTML = available.map((m) => {
        const hash = m.hash_name && m.hash_name.trim() ? m.hash_name : '';
        const real = m.real_name || '';
        const primary = hash || real || 'Member';
        const secondary = hash && real ? real : '';
        return `
          <button type="button" data-pick="${m.id}">
            ${this._escapeHtml(primary)}
            ${secondary ? `<span class="name-secondary">${this._escapeHtml(secondary)}</span>` : ''}
          </button>
        `;
      }).join('');
    }
    results.hidden = false;
  }

  _pick(id, input) {
    this.selectedIds.add(id);
    if (input) input.value = '';
    this._renderPills();
    this._wireUp();
    this._emit();
    const newInput = this.host.querySelector('.combobox-input');
    if (newInput) {
      newInput.focus();
      this._showResults('');
    }
  }

  _handleKey(e, input) {
    const results = this.host.querySelector('[data-role="results"]');
    if (results.hidden) return;
    const buttons = [...results.querySelectorAll('button[data-pick]')];
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      this.activeIndex = Math.min(buttons.length - 1, this.activeIndex + 1);
      this._highlight(buttons);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      this.activeIndex = Math.max(0, this.activeIndex - 1);
      this._highlight(buttons);
    } else if (e.key === 'Enter' && this.activeIndex >= 0) {
      e.preventDefault();
      const btn = buttons[this.activeIndex];
      if (btn) this._pick(btn.dataset.pick, input);
    } else if (e.key === 'Escape') {
      results.hidden = true;
    } else if (e.key === 'Backspace' && input.value === '' && this.selectedIds.size > 0) {
      // Backspace on empty input removes last pill
      const last = [...this.selectedIds].pop();
      if (last !== undefined) {
        this.selectedIds.delete(last);
        this._renderPills();
        this._wireUp();
        this._emit();
        const newInput = this.host.querySelector('.combobox-input');
        if (newInput) newInput.focus();
      }
    }
  }

  _highlight(buttons) {
    buttons.forEach((b, i) => b.classList.toggle('highlighted', i === this.activeIndex));
    if (this.activeIndex >= 0 && buttons[this.activeIndex]) {
      buttons[this.activeIndex].scrollIntoView({ block: 'nearest' });
    }
  }
}
