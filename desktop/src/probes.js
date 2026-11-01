// Reads quota for Claude Code, Codex and Antigravity (agy) from the credentials the CLIs already stored.
// Result texts are keys (errorKey / notes[].k) so the UI can translate them.
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFile } = require('child_process');

const HOME = os.homedir();
const DATA = path.join(HOME, '.agent-usage');
const ACC_FILE = path.join(DATA, 'accounts.json');
const IS_WIN = process.platform === 'win32';

const sh = (cmd, args, env = {}, timeout = 20000) => new Promise((resolve) =>
  execFile(cmd, args, { env: { ...process.env, ...env }, timeout, maxBuffer: 8e6, shell: IS_WIN, windowsHide: true },
    (error, out) => resolve({ ok: !error, out: out || '' })));

async function getJSON(url, headers) {
  try {
    const r = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* not json */ }
    return { status: r.status, json };
  } catch {
    return { status: 0, json: null };
  }
}

const readJSON = (file) => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; } };

// ---------- accounts ----------
const extraAccounts = () => readJSON(ACC_FILE) || [];
const saveAccounts = (list) => {
  fs.mkdirSync(DATA, { recursive: true });
  fs.writeFileSync(ACC_FILE, JSON.stringify(list, null, 2), { mode: 0o600 });
};
const allAccounts = () => [
  { id: 'claude-default', agent: 'claude', label: 'Claude', dir: null },
  { id: 'codex-default', agent: 'codex', label: 'Codex', dir: null },
  { id: 'agy-default', agent: 'agy', label: 'Agy', dir: null },
  ...extraAccounts(),
];

// ---------- default model (what each CLI uses when no --model is given) ----------
const configPath = (a) => ({
  claude: path.join(a.dir || path.join(HOME, '.claude'), 'settings.json'),
  codex: path.join(a.dir || path.join(HOME, '.codex'), 'config.toml'),
  agy: path.join(a.dir || HOME, '.gemini', 'antigravity-cli', 'settings.json'),
}[a.agent]);
// line-level regexes so the user's formatting and key order in their config files survive
const configPattern = (a, key) => (a.agent === 'codex'
  ? new RegExp(`^(\\s*${key}\\s*=\\s*")([^"]*)(")`, 'm')
  : new RegExp(`("${key}"\\s*:\\s*")([^"]*)(")`));
function readConfigValue(a, key) {
  try { const m = fs.readFileSync(configPath(a), 'utf8').match(configPattern(a, key)); return m ? m[2] : null; } catch { return null; }
}
function setDefaultModel(a, model) {
  const file = configPath(a);
  try {
    const text = fs.readFileSync(file, 'utf8');
    const re = configPattern(a, 'model');
    if (!re.test(text)) return false;
    fs.writeFileSync(file, text.replace(re, (_, p, __, s) => p + (a.agent === 'agy' ? model.name : model.id) + s));
    return true;
  } catch { return false; }
}
const defaultModel = (a) => ({
  claude: [readConfigValue(a, 'model'), readConfigValue(a, 'effortLevel')],
  codex: [readConfigValue(a, 'model'), readConfigValue(a, 'model_reasoning_effort')],
  agy: [readConfigValue(a, 'model'), null],
}[a.agent]);

// ---------- Claude ----------
async function claudeCreds(a) {
  let svc = 'Claude Code-credentials';
  if (a.dir) svc += '-' + crypto.createHash('sha256').update(a.dir).digest('hex').slice(0, 8);
  if (process.platform === 'darwin') {
    const k = await sh('security', ['find-generic-password', '-s', svc, '-w']);
    if (k.ok) { try { return JSON.parse(k.out).claudeAiOauth; } catch { /* fall through to file */ } }
  }
  const file = readJSON(path.join(a.dir || path.join(HOME, '.claude'), '.credentials.json'));
  return file && file.claudeAiOauth;
}

// `claude -p /usage` prints "Current week (Fable): 6% used · resets Nov 7 at 1:59pm (Asia/Saigon)".
// It is what the CLI itself shows, so it has per-model windows the OAuth API does not return.
function parseClaudeReset(raw) {
  const m = raw.match(/^(?:([A-Za-z]{3}) (\d{1,2}) (?:at )?)?(?:at )?(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*\(([^)]+)\)\s*$/i);
  if (!m) return null;
  const [, mon, day, h, min = '0', ap, tz] = m;
  const hour = (Number(h) % 12) + (ap.toLowerCase() === 'pm' ? 12 : 0);
  const now = new Date();
  const parts = (d) => Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' })
    .formatToParts(d).filter((x) => x.type !== 'literal').map((x) => [x.type, Number(x.value)]));
  let y; let mo; let dd;
  const np = parts(now);
  if (mon) { mo = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(mon.toLowerCase()) + 1; dd = Number(day); y = np.year; }
  else { y = np.year; mo = np.month; dd = np.day; }
  const toDate = (yy, mm, d2) => { // wall time in tz -> instant
    const guess = Date.UTC(yy, mm - 1, d2, hour, Number(min));
    const g = parts(new Date(guess));
    return new Date(guess - (Date.UTC(g.year, g.month - 1, g.day, g.hour, g.minute) - guess));
  };
  let t = toDate(y, mo, dd);
  if (mon && t < now - 30 * 864e5) t = toDate(y + 1, mo, dd);
  if (!mon && t < now) t = new Date(t.getTime() + 864e5);
  return t.getTime();
}
async function claudeCLILimits(a) {
  const out = await sh('claude', ['-p', '/usage'], a.dir ? { CLAUDE_CONFIG_DIR: a.dir } : {}, 45000);
  if (!out.ok) return [];
  const limits = [];
  for (const line of out.out.split('\n')) {
    const m = line.trim().match(/^Current ([^:]+):\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+(.+))?$/);
    if (!m) continue;
    let label = m[1];
    if (label === 'session') label = 'Session (5h)';
    else if (label.startsWith('week')) { const i = label.match(/\(([^)]+)\)/); label = i ? 'Weekly – ' + i[1] : 'Weekly'; }
    limits.push({ label, percent: Number(m[2]), resetsAt: m[3] ? parseClaudeReset(m[3]) : null });
  }
  return limits;
}

async function probeClaude(a) {
  const r = { limits: [], models: [], notes: [] };
  const c = await claudeCreds(a);
  if (!c || !c.accessToken) return { ...r, errorKey: 'not_logged_claude' };
  r.plan = c.subscriptionType;
  const h = { Authorization: 'Bearer ' + c.accessToken, 'anthropic-beta': 'oauth-2025-04-20', 'anthropic-version': '2023-06-01', 'User-Agent': 'claude-code/2.1' };
  const [u, m, p, cliLimits] = await Promise.all([
    getJSON('https://api.anthropic.com/api/oauth/usage', h),
    getJSON('https://api.anthropic.com/v1/models?limit=100', h),
    getJSON('https://api.anthropic.com/api/oauth/profile', h),
    claudeCLILimits(a)]);
  // the profile says who is logged in; the stored subscriptionType can be stale
  if (p.json && p.json.account) r.email = p.json.account.email;
  const org = p.json && p.json.organization;
  if (org) {
    const tier = org.rate_limit_tier || '';
    const mx = tier.match(/max_(\d+x)/);
    r.plan = mx ? 'max ' + mx[1] : (org.organization_type || r.plan || '').replace('claude_', '');
  }
  const mapModels = () => ((m.json && m.json.data) || []).map((x) => ({ id: x.id, name: x.display_name || x.id, detail: x.max_input_tokens ? `${Math.round(x.max_input_tokens / 1000)}k ctx` : undefined }));
  if (cliLimits.length) {
    r.limits = cliLimits;
    if (u.json && u.json.extra_usage) r.notes.push({ k: u.json.extra_usage.is_enabled ? 'extra_on' : 'extra_off' });
    r.models = mapModels();
    return r;
  }
  if (u.status === 401) return { ...r, errorKey: 'expired_claude' };
  const U = u.json || {};
  const names = { five_hour: 'Session (5h)', seven_day: 'Weekly – all models', seven_day_opus: 'Weekly – Opus', seven_day_sonnet: 'Weekly – Sonnet', seven_day_oauth_apps: 'Weekly – OAuth apps', seven_day_cowork: 'Weekly – Cowork' };
  for (const [k, label] of Object.entries(names)) {
    if (U[k] && typeof U[k].utilization === 'number') r.limits.push({ label, percent: U[k].utilization, resetsAt: Date.parse(U[k].resets_at) || null });
  }
  for (const [k, v] of Object.entries(U)) { // other windows the API exposes (credits, promos...)
    if (names[k] || !v || typeof v !== 'object' || typeof v.utilization !== 'number' || !v.resets_at) continue;
    const dollars = v.limit_dollars != null;
    r.limits.push({ label: dollars ? 'Credits (USD)' : k.replace(/_/g, ' '), percent: v.utilization, resetsAt: Date.parse(v.resets_at) || null,
      note: dollars ? `$${Math.round(v.used_dollars || 0)}/$${Math.round(v.limit_dollars)}` : undefined });
  }
  if (U.extra_usage) r.notes.push({ k: U.extra_usage.is_enabled ? 'extra_on' : 'extra_off' });
  r.models = ((m.json && m.json.data) || []).map((x) => ({ id: x.id, name: x.display_name || x.id, detail: x.max_input_tokens ? `${Math.round(x.max_input_tokens / 1000)}k ctx` : undefined }));
  return r;
}

// ---------- Codex ----------
async function probeCodex(a) {
  const r = { limits: [], models: [], notes: [] };
  const dir = a.dir || path.join(HOME, '.codex');
  const auth = readJSON(path.join(dir, 'auth.json'));
  if (!auth || !auth.tokens || !auth.tokens.access_token) return { ...r, errorKey: 'not_logged_codex' };
  const h = { Authorization: 'Bearer ' + auth.tokens.access_token, 'chatgpt-account-id': auth.tokens.account_id || '', 'User-Agent': 'codex-cli' };
  const [u, m] = await Promise.all([getJSON('https://chatgpt.com/backend-api/wham/usage', h), sh('codex', ['debug', 'models'], { CODEX_HOME: dir })]);
  if (u.status === 401 || u.status === 403) return { ...r, errorKey: 'expired_codex' };
  const U = u.json || {};
  r.plan = U.plan_type; r.email = U.email;
  const span = (s) => (s >= 6 * 86400 ? 'Weekly' : s >= 3600 ? Math.round(s / 3600) + 'h' : Math.round((s || 0) / 60) + 'm');
  const win = (label, w) => {
    if (!w || typeof w.used_percent !== 'number') return;
    r.limits.push({ label: label.replace('{}', span(w.limit_window_seconds)), percent: w.used_percent, resetsAt: w.reset_at ? w.reset_at * 1000 : null });
  };
  const rl = U.rate_limit || {};
  win('Primary ({})', rl.primary_window); win('Secondary ({})', rl.secondary_window);
  r.limitReached = rl.limit_reached === true;
  const cr = U.code_review_rate_limit || {};
  win('Code review ({})', cr.primary_window); win('Code review ({})', cr.secondary_window);
  for (const e of U.additional_rate_limits || []) {
    const n = e.limit_name || 'extra';
    win(`${n} ({})`, e.rate_limit && e.rate_limit.primary_window); win(`${n} ({})`, e.rate_limit && e.rate_limit.secondary_window);
  }
  const blocked = {};
  for (const [k, v] of Object.entries(U.model_usage || {})) if (v && v.available === false) blocked[k] = Date.parse(v.available_at) || null;
  if (U.credits) r.notes.push({ raw: U.credits.unlimited ? 'Credits: unlimited' : `Credits: ${U.credits.balance ?? 0}` });
  const resets = U.rate_limit_reset_credits && U.rate_limit_reset_credits.available_count;
  if (resets > 0) r.notes.push({ k: 'resets_left', n: resets });
  try {
    r.models = (JSON.parse(m.out).models || []).map((x) => ({ id: x.slug, name: x.display_name || x.slug, detail: x.slug, blockedUntil: blocked[x.slug] }));
  } catch { /* codex cli missing: no model list */ }
  return r;
}

// ---------- Agy (Antigravity) ----------
// `agy -p /usage` prints "<group>\t<limit>\t<N>%\t<reset iso>" (N = remaining) without calling a model.
async function probeAgy(a) {
  const r = { limits: [], models: [], notes: [] };
  const env = a.dir ? { HOME: a.dir, USERPROFILE: a.dir } : {};
  const m = await sh('agy', ['models'], env);
  r.models = m.out.split('\n').map((l) => l.split('\t')).filter((p) => p.length === 2 && /^[a-z0-9.-]+$/.test(p[0])).map(([id, name]) => ({ id, name: name.trim() }));
  if (!r.models.length) return { ...r, errorKey: 'not_logged_agy' };
  const token = readJSON(path.join(a.dir || HOME, '.gemini', 'antigravity-cli', 'antigravity-oauth-token'));
  try { r.email = JSON.parse(Buffer.from(token.id_token.split('.')[1], 'base64url').toString()).email; } catch { /* no token */ }
  const u = await sh('agy', ['-p', '/usage'], env, 30000);
  for (const line of u.out.split('\n')) {
    const c = line.split('\t').map((x) => x.trim());
    if (c.length < 3 || !c[2].endsWith('%')) continue;
    const group = c[0].startsWith('Gemini 4') ? 'Argon' : c[0].startsWith('Gemini') ? 'Gemini' : 'Claude/GPT';
    r.limits.push({ label: `${group} · ${c[1].includes('Five Hour') ? '5h' : 'Weekly'}`, percent: 100 - parseFloat(c[2]), resetsAt: Date.parse(c[3]) || null });
  }
  if (!r.limits.length) r.notes.push({ k: 'agy_unreadable' });
  return r;
}

async function probe(a) {
  const fn = { claude: probeClaude, codex: probeCodex, agy: probeAgy }[a.agent];
  let r;
  try { r = await fn(a); } catch (e) { r = { limits: [], models: [], notes: [], errorRaw: String(e.message || e) }; }
  const [model, effort] = defaultModel(a);
  return { account: a, ...r, defaultModel: model, defaultEffort: effort };
}

module.exports = { DATA, allAccounts, extraAccounts, saveAccounts, probe, setDefaultModel };
