const { contextBridge, ipcRenderer } = require('electron');
const { LANGS, S } = require('./i18n');

contextBridge.exposeInMainWorld('api', {
  langs: LANGS,
  strings: S,
  state: () => ipcRenderer.invoke('state'),
  onState: (cb) => ipcRenderer.on('state', (_, s) => cb(s)),
  refresh: () => ipcRenderer.invoke('refresh'),
  set: (patch) => ipcRenderer.invoke('set', patch),
  addAccount: (agent, name) => ipcRenderer.invoke('addAccount', agent, name),
  removeAccount: (id) => ipcRenderer.invoke('removeAccount', id),
  switchModel: (id, model) => ipcRenderer.invoke('switchModel', id, model),
  donate: () => ipcRenderer.invoke('donate'),
  quit: () => ipcRenderer.invoke('quit'),
});
