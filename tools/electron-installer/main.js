const { app, BrowserWindow, dialog, ipcMain } = require('electron');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

let mainWindow;

function defaultInstallRoot() {
  return path.join(process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE, 'AppData', 'Local'), 'Programs', 'SCI', 'current');
}

function defaultPluginHome() {
  return path.join(process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE, 'AppData', 'Local'), 'sa_plugins');
}

function resourcePath(...parts) {
  return path.join(process.resourcesPath, ...parts);
}

function runPowerShell(args, send) {
  return new Promise((resolve) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', ...args], {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (text) => send({ stream: 'stdout', text }));
    child.stderr.on('data', (text) => send({ stream: 'stderr', text }));
    child.on('error', (error) => resolve({ code: 1, error: error.message }));
    child.on('close', (code) => resolve({ code: code ?? 1 }));
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 760,
    height: 620,
    minWidth: 680,
    minHeight: 520,
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js')
    }
  });
  mainWindow.loadFile(path.join(__dirname, 'index.html'));
}

ipcMain.handle('installer-defaults', () => ({
  installRoot: defaultInstallRoot(),
  pluginHome: defaultPluginHome(),
  bundle: resourcePath('bundle', 'SCI-windows-x64-full.zip')
}));

ipcMain.handle('choose-directory', async () => {
  const result = await dialog.showOpenDialog(mainWindow, { properties: ['openDirectory', 'createDirectory'] });
  return result.canceled ? null : result.filePaths[0];
});

ipcMain.handle('install', async (_event, values) => {
  const bundle = resourcePath('bundle', 'SCI-windows-x64-full.zip');
  const script = resourcePath('scripts', 'install_bundle_windows.ps1');
  if (!fs.existsSync(bundle) || !fs.existsSync(script)) return { code: 1, error: '安装资源不完整：缺少 bundle 或安装脚本。' };
  const args = ['-File', script, '-Bundle', bundle, '-InstallRoot', values.installRoot, '-PluginHome', values.pluginHome, '-TimeoutSeconds', '300'];
  return runPowerShell(args, (message) => mainWindow.webContents.send('installer-output', message));
});

ipcMain.handle('uninstall', async (_event, values) => {
  const targets = [values.installRoot, values.pluginHome];
  const invalid = targets.some((item) => typeof item !== 'string' || !path.isAbsolute(item));
  if (invalid) return { code: 1, error: '卸载路径必须是绝对路径。' };
  const result = await dialog.showMessageBox(mainWindow, {
    type: 'warning',
    buttons: ['取消', '删除 SCI 文件'],
    defaultId: 0,
    cancelId: 0,
    message: '确认删除 SCI 的程序和插件目录？',
    detail: `${values.installRoot}\n${values.pluginHome}`
  });
  if (result.response !== 1) return { code: 0, cancelled: true };
  for (const target of targets) {
    if (fs.existsSync(target)) fs.rmSync(target, { recursive: true, force: true });
  }
  return { code: 0 };
});

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
