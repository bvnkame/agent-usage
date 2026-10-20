// Renderer: draws the popup (cards) and the settings page from the state pushed by the main process.
const { langs, strings } = window.api;
const AGENTS = [['claude', 'Claude', '--claude'], ['codex', 'Codex', '--codex'], ['agy', 'Agy', '--agy']];
const PRESETS = [10, 30, 60, 120, 300, 900, 1800];

let state = { results: [], updated: 0, loading: false, settings: { lang: 'vi', refreshSeconds: 60, showAgent: 'all', showEmail: false } };
let page = 'main';          // 'main' | 'settings'
let revealed = new Set();    // account ids whose email was clicked open
let adding = false;
let draftAgent = 'claude';
let draftName = '';

const T = (key) => {
  const row = strings[key];
  if (!row) return key;
  const i = Math.max(0, langs.findIndex((l) => l[0] === state.settings.lang));
  return row[i] || row[0];
};
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const css = (agent) => `var(${AGENTS.find((a) => a[0] === agent)[2]})`;
const level = (p) => (p >= 90 ? 'var(--bad)' : p >= 70 ? 'var(--warn)' : 'var(--ok)');

function maskEmail(e) {
  const at = e.indexOf('@');
  return at < 0 ? '••••••' : e[0] + '•••••' + e.slice(at);
}
function resetIn(ms) {
  if (!ms) return '';
  const s = Math.floor((ms - Date.now()) / 1000);
  if (s <= 0) return T('reset_done');
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return `${T('reset_in')} ${d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`}`;
}
const isCurrent = (m, raw) => !!raw && (raw === m.id || raw === m.name || (raw.length > 2 && m.id.includes(raw) && !m.id.includes('[')));

function limitHTML(l) {
  const pct = Math.round(l.percent);
  return `<div class="limit"><div class="row"><span>${esc(l.label)} ${l.note ? `<small class="note">${esc(l.note)}</small>` : ''}</span><b>${T('left')} ${100 - pct}%</b></div>
    <div class="bar"><i style="width:${Math.min(100, Math.max(0, l.percent))}%;background:${level(l.percent)}"></i></div>
    <div class="reset">${esc(resetIn(l.resetsAt))}</div></div>`;
}

function noteText(n) {
  if (n.raw) return n.raw;
  return n.n ? `${n.n} ${T(n.k)}` : T(n.k);
}

function cardHTML(r) {
  const a = r.account.agent, c = css(a);
  const shown = state.settings.showEmail || revealed.has(r.account.id);
  const cur = r.defaultModel && (r.models.find((m) => isCurrent(m, r.defaultModel)) || { name: r.defaultModel }).name;
  return `<div class="card">
    <div class="who"><span class="dot" style="background:${c}"></span>
      <div class="grow"><span class="name">${esc(r.account.label)}</span>
      ${r.email ? `<span class="email" data-reveal="${esc(r.account.id)}" title="${shown ? '' : esc(T('tap_reveal'))}">${esc(shown ? r.email : maskEmail(r.email))}</span>` : ''}</div>
      ${r.plan ? `<span class="plan" style="background:color-mix(in srgb, ${c} 18%, transparent);color:${c}">${esc(r.plan)}</span>` : ''}</div>
    ${cur ? `<div class="using">${T('in_use')} <span class="model" style="background:color-mix(in srgb, ${c} 18%, transparent);color:${c};border:1px solid color-mix(in srgb, ${c} 50%, transparent)">${esc(cur)}${r.defaultEffort ? ` · ${esc(r.defaultEffort)}` : ''}</span></div>` : ''}
    ${r.errorKey || r.errorRaw ? `<div class="err">${esc(r.errorKey ? T(r.errorKey) : r.errorRaw)}</div>` : ''}
    ${r.limitReached ? `<div class="hit">${T('limit_hit')}</div>` : ''}
    ${r.limits.map(limitHTML).join('')}
    ${r.notes.map((n) => `<div class="note">${esc(noteText(n))}</div>`).join('')}
    ${r.models.length ? `<details><summary>${T('models')} (${r.models.length}) · ${T('models_hint')}</summary>
      ${r.models.map((m) => `<div class="m" data-switch="${esc(r.account.id)}" data-model="${esc(m.id)}" title="${esc(isCurrent(m, r.defaultModel) ? T('in_use') : T('set_default'))}">
        <span>${isCurrent(m, r.defaultModel) ? '●' : '○'}</span><span>${esc(m.name)}<small>${esc(m.id)}</small></span>
        ${m.blockedUntil ? `<span class="blocked">${T('blocked_until')} ${new Date(m.blockedUntil).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>` : ''}</div>`).join('')}
    </details>` : ''}
  </div>`;
}

function mainHTML() {
  const cols = AGENTS.map(([agent, title]) => `<div class="col"><h2><span class="dot" style="background:${css(agent)}"></span>${title}</h2>
    <div class="list">${state.results.filter((r) => r.account.agent === agent).map(cardHTML).join('')}</div></div>`).join('');
  return `<div class="cols">${cols}</div>`;
}

function seg(options, value, attr) {
  return `<div class="seg">${options.map(([v, label]) => `<button class="${v === value ? 'on' : ''}" ${attr}="${esc(v)}">${esc(label)}</button>`).join('')}</div>`;
}

function settingsHTML() {
  const s = state.settings;
  const secLabel = (n) => (n < 60 ? `${n} ${T('sec')}` : `${n / 60} ${T('min')}`);
  const accounts = state.results.map((r) => `<div class="acc"><span class="dot" style="background:${css(r.account.agent)}"></span><b>${esc(r.account.label)}</b>
    <span class="email">${esc(r.email ? (s.showEmail ? r.email : maskEmail(r.email)) : r.account.dir ? '' : T('default_acc'))}</span>
    ${r.account.dir ? `<button class="danger" data-remove="${esc(r.account.id)}">${T('remove')}</button>` : ''}</div>`).join('');
  return `<div class="page">
    <div class="section"><h3>${T('language')}</h3>${seg(langs, s.lang, 'data-lang')}</div>
    <div class="section"><h3>${T('refresh_every')}</h3>${seg(PRESETS.map((n) => [String(n), secLabel(n)]), String(s.refreshSeconds), 'data-refresh')}</div>
    <div class="section"><h3>${T('menubar_show')}</h3>${seg([['all', T('all3')], ['claude', 'Claude'], ['codex', 'Codex'], ['agy', 'Agy']], s.showAgent, 'data-show')}</div>
    <div class="section"><h3>${T('accounts')}</h3>
      <label><input type="checkbox" id="showEmail" ${s.showEmail ? 'checked' : ''}> ${T('show_email')}</label>
      ${accounts}
      ${adding ? `<div class="acc"><select id="newAgent">${AGENTS.map(([a, t]) => `<option value="${a}" ${a === draftAgent ? 'selected' : ''}>${t}</option>`).join('')}</select>
        <input id="newName" placeholder="${esc(T('name_hint'))}" value="${esc(draftName)}"><button id="doAdd"><b>${T('login')}</b></button></div><div class="note">${T('login_hint')}</div>`
        : `<button id="startAdd">+ ${T('add_account')}</button>`}
    </div>
    <button id="coffee" class="coffee" style="color:var(--warn);font-weight:600;text-align:left">☕ ${T('coffee')}</button>
  </div>`;
}

function render() {
  const time = state.updated ? new Date(state.updated).toLocaleTimeString() : '';
  document.getElementById('app').innerHTML = `
    <header><h1>${page === 'settings' ? T('settings') : 'Agent Usage'}</h1>
      <span class="time">${state.loading ? '…' : ''} ${time}</span>
      <button id="refresh" title="Refresh">↻</button>
      <button id="gear" title="${esc(page === 'settings' ? T('back') : T('settings'))}">${page === 'settings' ? '‹' : '⚙'}</button></header>
    ${page === 'settings' ? settingsHTML() : mainHTML()}
    <footer><span></span><button id="quit">${T('quit')}</button></footer>`;
}

document.addEventListener('click', (e) => {
  const t = e.target.closest('button, [data-reveal], [data-switch]');
  if (!t) return;
  const d = t.dataset;
  if (t.id === 'refresh') window.api.refresh();
  else if (t.id === 'gear') { page = page === 'settings' ? 'main' : 'settings'; render(); }
  else if (t.id === 'quit') window.api.quit();
  else if (t.id === 'coffee') window.api.donate();
  else if (t.id === 'startAdd') { adding = true; render(); }
  else if (t.id === 'doAdd') {
    window.api.addAccount(document.getElementById('newAgent').value, document.getElementById('newName').value.trim());
    adding = false; draftName = ''; render();
  }
  else if (d.reveal) { revealed.has(d.reveal) ? revealed.delete(d.reveal) : revealed.add(d.reveal); render(); }
  else if (d.lang) window.api.set({ lang: d.lang });
  else if (d.refresh) window.api.set({ refreshSeconds: Number(d.refresh) });
  else if (d.show) window.api.set({ showAgent: d.show });
  else if (d.remove) window.api.removeAccount(d.remove);
  else if (d.switch) {
    const r = state.results.find((x) => x.account.id === d.switch);
    const m = r && r.models.find((x) => x.id === d.model);
    if (m && !isCurrent(m, r.defaultModel)) window.api.switchModel(d.switch, m);
  }
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'showEmail') window.api.set({ showEmail: e.target.checked });
  if (e.target.id === 'newAgent') draftAgent = e.target.value;
});
document.addEventListener('input', (e) => { if (e.target.id === 'newName') draftName = e.target.value; });

window.api.onState((s) => {
  const typing = document.activeElement && document.activeElement.id === 'newName';
  state = s;
  if (!typing) render();
});
window.api.state().then((s) => { state = s; render(); });
setInterval(() => { if (page === 'main' && !document.querySelector('details[open]')) render(); }, 30000);   // keep reset countdowns fresh
