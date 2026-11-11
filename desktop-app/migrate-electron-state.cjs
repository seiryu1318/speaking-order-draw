const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const storageKey = 'speaking-draw-v4';

function checkLegacyAppClosed() {
  const command = "if (Get-Process -Name '제비뽑기' -ErrorAction SilentlyContinue) { exit 3 }";
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], {
    windowsHide: true
  });
  if (result.status === 3) throw new Error('제비뽑기 실행 중에는 명단을 옮길 수 없습니다.');
  if (result.error || result.status !== 0) throw new Error('기존 제비뽑기 실행 여부를 확인할 수 없습니다.');
}

function exportLegacyState() {
  if (process.platform !== 'win32' || !process.env.APPDATA || !process.env.LOCALAPPDATA) {
    throw new Error('Windows 사용자 데이터 폴더를 찾을 수 없습니다.');
  }

  const sourceStorage = path.join(process.env.APPDATA, 'speaking-order-draw-desktop', 'Local Storage');
  const sourceHtml = path.join(process.env.LOCALAPPDATA, 'Programs', '제비뽑기', 'resources', 'web', '2학년 말하기 제비뽑기.html');
  const destinationDirectory = path.join(process.env.LOCALAPPDATA, '제비뽑기');
  const destination = path.join(destinationDirectory, 'migration.json');
  const runtime = path.join(__dirname, 'node_modules', 'electron', 'dist', 'electron.exe');

  if (fs.existsSync(destination)) {
    console.log('기존 이전 파일을 보존했습니다.');
    return 0;
  }
  if (!fs.existsSync(sourceHtml) || !fs.existsSync(path.join(sourceStorage, 'leveldb'))) {
    console.log('설치된 기존 앱의 명단 저장소가 없습니다.');
    return 0;
  }
  if (!fs.existsSync(runtime)) throw new Error('기존 앱의 저장소를 읽으려면 이 프로젝트의 Electron 빌드 도구가 필요합니다.');

  const tempRoot = fs.realpathSync(os.tmpdir());
  const workspace = fs.mkdtempSync(path.join(tempRoot, 'jebidraw-migrate-'));
  try {
    checkLegacyAppClosed();
    fs.cpSync(sourceStorage, path.join(workspace, 'Local Storage'), {
      recursive: true,
      filter: source => path.basename(source) !== 'LOCK'
    });

    const electronEnv = { ...process.env };
    delete electronEnv.ELECTRON_RUN_AS_NODE;
    const result = spawnSync(runtime, [__filename, workspace, sourceHtml, destination], {
      env: electronEnv,
      stdio: 'inherit',
      timeout: 45_000,
      windowsHide: true
    });
    if (result.error || result.status === null) throw new Error('기존 앱의 명단 저장소를 읽지 못했습니다.');
    return result.status;
  } finally {
    const resolved = fs.realpathSync(workspace);
    if (path.dirname(resolved) === tempRoot && path.basename(resolved).startsWith('jebidraw-migrate-')) {
      fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
    }
  }
}

async function readLegacyState() {
  const { app, BrowserWindow, session } = require('electron');
  const [workspace, sourceHtml, destination] = process.argv.slice(2);
  app.setPath('userData', workspace);
  app.setPath('sessionData', workspace);
  app.disableHardwareAcceleration();
  app.commandLine.appendSwitch('disable-background-networking');
  const sourceUrl = pathToFileURL(sourceHtml).href;

  await app.whenReady();
  // Keep the original file origin without executing the old app's scripts.
  session.defaultSession.protocol.handle('file', request => {
    if (request.url !== sourceUrl) return new Response(null, { status: 404 });
    return new Response('<!doctype html><meta charset="utf-8">', {
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'" }
    });
  });

  const window = new BrowserWindow({
    show: false,
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  try {
    await window.loadURL(sourceUrl);
    const rawState = await window.webContents.executeJavaScript(`localStorage.getItem(${JSON.stringify(storageKey)})`);
    if (rawState === null) {
      console.log('기존 앱에 저장된 명단이 없습니다.');
      return 0;
    }

    let saved;
    try {
      saved = JSON.parse(rawState);
    } catch {
      throw new Error('기존 앱의 저장 형식을 확인할 수 없습니다.');
    }
    if (!Array.isArray(saved?.room9) || !Array.isArray(saved.room11) || !Array.isArray(saved.customTabs)) {
      throw new Error('기존 앱의 명단 형식을 확인할 수 없습니다.');
    }

    fs.mkdirSync(path.dirname(destination), { recursive: true });
    const temporaryFile = `${destination}.${process.pid}.tmp`;
    fs.writeFileSync(temporaryFile, rawState, { encoding: 'utf8', flag: 'wx' });
    try {
      fs.linkSync(temporaryFile, destination);
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      console.log('기존 이전 파일을 보존했습니다.');
      return 0;
    } finally {
      fs.rmSync(temporaryFile);
    }
    console.log(`기존 명단을 준비했습니다. 강의실 9 ${saved.room9.length}행, 강의실 11 ${saved.room11.length}행, 저장된 탭 ${saved.customTabs.length}개.`);
    return 0;
  } finally {
    window.destroy();
  }
}

if (process.versions.electron) {
  const { app } = require('electron');
  readLegacyState().then(code => app.exit(code)).catch(error => {
    console.error(error.message);
    app.exit(1);
  });
} else {
  try {
    process.exitCode = exportLegacyState();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
