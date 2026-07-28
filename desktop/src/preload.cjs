const { contextBridge, ipcRenderer, webUtils } = require('electron');

const jobListeners = new Set();
ipcRenderer.on('job:event', (_event, payload) => {
  for (const listener of jobListeners) listener(payload);
});

contextBridge.exposeInMainWorld('osvcopy', Object.freeze({
  chooseFiles: () => ipcRenderer.invoke('dialog:files'),
  chooseFolders: () => ipcRenderer.invoke('dialog:folders'),
  chooseDestination: () => ipcRenderer.invoke('dialog:destination'),
  pathsForFiles: (files) => Array.from(files, (file) => webUtils.getPathForFile(file)).filter(Boolean),
  loadSettings: () => ipcRenderer.invoke('settings:load'),
  saveSettings: (settings) => ipcRenderer.invoke('settings:save', settings),
  startJob: (payload) => ipcRenderer.invoke('job:start', payload),
  cancelJob: () => ipcRenderer.invoke('job:cancel'),
  onJobEvent: (listener) => {
    jobListeners.add(listener);
    return () => jobListeners.delete(listener);
  }
}));
