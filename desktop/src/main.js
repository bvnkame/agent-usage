const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, screen, shell, nativeTheme } = require('electron');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { DATA, allAccounts, extraAccounts, saveAccounts, probe, setDefaultModel } = require('./probes');
const { barData } = require('./bar');

const SETTINGS_FILE = path.join(DATA, 'settings.json');
const DEFAULTS = { lang: 'vi', refreshSeconds: 60, showAgent: 'all', showEmail: false };
const POPUP = { width: 800, height: 480 };
const DONATE_URL = 'https://buymeacoffee.com/bvnkame';

let settings = { ...DEFAULTS };
let results = [];
let updated = 0;
let loading = false;
let tray, popup, barWin, timer;

function loadSettings() {
  try { settings = { ...DEFAULTS, ...JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')) }; } catch { settings = { ...DEFAULTS }; }
}
function saveSettings() {
  fs.mkdirSync(DATA, { recursive: true });
  fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2));
}

const snapshot = () => ({ results, updated, loading, settings });
function push() {
  if (popup && !popup.isDestroyed()) popup.webContents.send('state', snapshot());
  updateTray();
}

async function refresh() {
  if (loading) return;
  loading = true; push();
  try { results = await Promise.all(allAccounts().map(probe)); } finally { loading = false; }
  updated = Date.now();
  push();
}
function schedule() {
  clearInterval(timer);
  timer = setInterval(refresh, Math.max(10, settings.refreshSeconds) * 1000);
}

// ---------- tray image, drawn in a hidden window (canvas) so it works on every OS ----------
async function updateTray() {
  if (!tray || !barWin || barWin.isDestroyed()) return;
  const data = barData(results, settings.showAgent);
  const wide = process.platform === 'darwin';
  try {
    const url = await barWin.webContents.executeJavaScript(`draw(${JSON.stringify(data)}, ${wide}, ${nativeTheme.shouldUseDarkColors})`);
    tray.setImage(nativeImage.createFromDataURL(url));
  } catch { /* window still loading */ }
  const tip = data.map((d) => `${d.agent}: 5h ${d.h5 == null ? '—' : Math.round(d.h5) + '%'} · week ${d.wk == null ? '—' : Math.round(d.wk) + '%'}`).join('\n');
  tray.setToolTip(tip || 'Agent Usage');
}

function createPopup() {
  popup = new BrowserWindow({
    ...POPUP, show: false, frame: false, resizable: false, skipTaskbar: true, alwaysOnTop: true, fullscreenable: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  popup.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  popup.on('blur', () => { if (!popup.webContents.isDevToolsOpened()) popup.hide(); });
  popup.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
}

function showPopup() {
  const b = tray.getBounds();
  const display = screen.getDisplayNearestPoint({ x: b.x, y: b.y });
  const wa = display.workArea;
  const w = Math.min(POPUP.width, wa.width - 16), h = Math.min(POPUP.height, wa.height - 16);
  let x = Math.round(b.x + b.width / 2 - w / 2);
  x = Math.min(Math.max(x, wa.x + 8), wa.x + wa.width - w - 8);
  const atTop = b.y < wa.y + wa.height / 2;           // menu bar / top panel vs bottom taskbar
  const y = atTop ? wa.y + 4 : wa.y + wa.height - h - 4;
  popup.setBounds({ x, y, width: w, height: h });
  popup.show(); popup.focus();
  push();
  if (Date.now() - updated > 15000) refresh();
}

function openTerminal(command) {
  if (process.platform === 'darwin') {
    spawn('osascript', ['-e', `tell application "Terminal" to do script "${command.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`, '-e', 'tell application "Terminal" to activate'], { stdio: 'ignore' }).unref();
  } else if (process.platform === 'win32') {
    spawn('cmd.exe', ['/c', 'start', 'cmd.exe', '/k', command], { stdio: 'ignore', detached: true }).unref();
  } else {
    const terms = [['x-terminal-emulator', '-e'], ['gnome-terminal', '--'], ['konsole', '-e'], ['xterm', '-e']];
    const [bin, flag] = terms.find(([t]) => require('child_process').spawnSync('which', [t]).status === 0) || terms[3];
    spawn(bin, [flag, 'bash', '-lc', `${command}; exec bash`], { stdio: 'ignore', detached: true }).unref();
  }
}

function addAccount(agent, name) {
  const id = `${agent}-${crypto.randomBytes(3).toString('hex')}`;
  const dir = path.join(DATA, id);
  fs.mkdirSync(dir, { recursive: true });
  const list = extraAccounts();
  saveAccounts([...list, { id, agent, label: name || `${agent} #${list.filter((a) => a.agent === agent).length + 1}`, dir }]);
  const win = process.platform === 'win32';
  const cmd = {
    claude: win ? `set CLAUDE_CONFIG_DIR=${dir}&& claude auth login` : `CLAUDE_CONFIG_DIR='${dir}' claude auth login`,
    codex: win ? `set CODEX_HOME=${dir}&& codex login` : `CODEX_HOME='${dir}' codex login`,
    agy: win ? `set USERPROFILE=${dir}&& agy` : `HOME='${dir}' agy`,
  }[agent];
  openTerminal(cmd);
}

function ipc() {
  ipcMain.handle('state', () => snapshot());
  ipcMain.handle('refresh', () => refresh());
  ipcMain.handle('set', (_, patch) => {
    settings = { ...settings, ...patch };
    saveSettings();
    if ('refreshSeconds' in patch) schedule();
    push();
  });
  ipcMain.handle('addAccount', (_, agent, name) => addAccount(agent, name));
  ipcMain.handle('removeAccount', (_, id) => { saveAccounts(extraAccounts().filter((a) => a.id !== id)); return refresh(); });
  ipcMain.handle('switchModel', (_, id, model) => {
    const acc = allAccounts().find((a) => a.id === id);
    if (acc && setDefaultModel(acc, model)) return refresh();
  });
  ipcMain.handle('donate', () => shell.openExternal(DONATE_URL));
  ipcMain.handle('quit', () => app.quit());
}

if (!app.requestSingleInstanceLock()) app.quit();
if (process.platform === 'darwin') app.dock.hide();

app.whenReady().then(() => {
  loadSettings();
  barWin = new BrowserWindow({ show: false, width: 400, height: 60, webPreferences: { offscreen: false, backgroundThrottling: false } });
  barWin.loadFile(path.join(__dirname, 'renderer', 'bar.html'));
  tray = new Tray(nativeImage.createFromPath(path.join(__dirname, '..', 'assets', 'icon.png')).resize({ width: 18, height: 18 }));
  tray.on('click', () => (popup.isVisible() ? popup.hide() : showPopup()));
  tray.on('right-click', () => tray.popUpContextMenu(Menu.buildFromTemplate([{ label: 'Refresh', click: refresh }, { label: 'Quit', click: () => app.quit() }])));
  createPopup();
  ipc();
  nativeTheme.on('updated', updateTray);
  barWin.webContents.once('did-finish-load', () => { refresh(); });
  schedule();
});

app.on('window-all-closed', (e) => e.preventDefault());   // tray app: stay alive
