// Writes src/build-info.json (build number = commit count, short hash) before packaging.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const git = (cmd) => { try { return execSync(`git ${cmd}`, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { return ''; } };
const info = { build: git('rev-list --count HEAD') || '0', commit: git('rev-parse --short HEAD') || 'dev' };
fs.writeFileSync(path.join(__dirname, '..', 'src', 'build-info.json'), JSON.stringify(info));
