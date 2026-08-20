const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('sciInstaller', {
  defaults: () => ipcRenderer.invoke('installer-defaults'),
  chooseDirectory: () => ipcRenderer.invoke('choose-directory'),
  install: (values) => ipcRenderer.invoke('install', values),
  uninstall: (values) => ipcRenderer.invoke('uninstall', values),
  onOutput: (callback) => ipcRenderer.on('installer-output', (_event, message) => callback(message))
});
