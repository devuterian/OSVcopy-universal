import { app, BrowserWindow, dialog, ipcMain, Notification, utilityProcess } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_SETTINGS, SettingsStore } from './settings.mjs';

const directory = path.dirname(fileURLToPath(import.meta.url));
let mainWindow;
let worker;
let settingsStore;

function send(channel, payload) {
  if (!mainWindow?.isDestroyed()) mainWindow.webContents.send(channel, payload);
}

function setTaskbar(message) {
  if (!mainWindow) return;
  if (message.type === 'phase' && message.phase === 'scanning') mainWindow.setProgressBar(2, { mode: 'indeterminate' });
  if (message.type === 'progress') {
    const fraction = message.totalBytes > 0 ? message.completedBytes / message.totalBytes : message.completed / Math.max(message.total, 1);
    mainWindow.setProgressBar(Math.min(Math.max(fraction, 0), 1), { mode: 'normal' });
  }
  if (['done', 'cancelled', 'fatal-error'].includes(message.type)) mainWindow.setProgressBar(-1);
}

function startWorker(payload) {
  if (worker) throw new Error('a job is already running');
  const child = utilityProcess.fork(path.join(directory, 'worker.mjs'));
  worker = child;
  child.on('message', (message) => {
    setTaskbar(message);
    send('job:event', message);
    if (message.type === 'done' && Notification.isSupported()) {
      new Notification({ title: 'OSVcopy Universal', body: `완료 ${message.completed}개, 실패 ${message.failed}개` }).show();
    }
    if (['done', 'cancelled', 'fatal-error'].includes(message.type)) {
      if (worker === child) worker = undefined;
      child.kill();
    }
  });
  child.on('exit', () => {
    if (worker === child) worker = undefined;
    mainWindow?.setProgressBar(-1);
  });
  child.postMessage({ type: 'start', ...payload });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1120,
    height: 820,
    minWidth: 880,
    minHeight: 680,
    title: 'OSVcopy Universal',
    backgroundColor: '#111216',
    webPreferences: {
      preload: path.join(directory, 'preload.cjs'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  });
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.loadFile(path.join(directory, 'renderer', 'index.html'));
}

app.whenReady().then(async () => {
  if (process.platform === 'win32') app.setAppUserModelId('net.marierie.osvcopy.universal');
  settingsStore = new SettingsStore(app.getPath('userData'));
  ipcMain.handle('dialog:files', async () => {
    const result = await dialog.showOpenDialog(mainWindow, { properties: ['openFile', 'multiSelections'] });
    return result.canceled ? [] : result.filePaths;
  });
  ipcMain.handle('dialog:folders', async () => {
    const result = await dialog.showOpenDialog(mainWindow, { properties: ['openDirectory', 'multiSelections'] });
    return result.canceled ? [] : result.filePaths;
  });
  ipcMain.handle('dialog:destination', async () => {
    const result = await dialog.showOpenDialog(mainWindow, { properties: ['openDirectory', 'createDirectory'] });
    return result.canceled ? '' : result.filePaths[0];
  });
  ipcMain.handle('settings:load', () => settingsStore.load());
  ipcMain.handle('settings:save', (_event, value) => settingsStore.save({ ...DEFAULT_SETTINGS, ...value }));
  ipcMain.handle('job:start', (_event, payload) => {
    if (!Array.isArray(payload?.entries) || payload.entries.length === 0) throw new Error('source entries are required');
    if (!payload?.options?.destination) throw new Error('destination is required');
    startWorker(payload);
    return true;
  });
  ipcMain.handle('job:cancel', () => {
    worker?.postMessage({ type: 'cancel' });
    return true;
  });
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('before-quit', () => worker?.kill());

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
