// FutaFinance デスクトップ版（Electron）メインプロセス。
//
// 役割:
//  1. ローカル同梱した Flutter Web ビルド(web-dist/)を http://127.0.0.1:固定ポート で配信
//     （固定オリジンにすることで Firebase/IndexedDB のオフライン永続が効く）
//  2. Google ログインを自前 OAuth（ループバック＋PKCE）で実施し、トークンを
//     preload 経由で Flutter に渡す（埋め込み画面は Google に弾かれるため）
//  3. electron-updater で GitHub Releases から完全自動更新（NSIS）
const {
  app, BrowserWindow, ipcMain, shell, dialog, session,
} = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs');
const os = require('os');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const { spawn, exec } = require('child_process');

// ───────────────────────── 設定 ─────────────────────────
const APP_TITLE = 'FutaFinance';
// 固定ポート（IndexedDB のオリジン安定のため）。塞がっていれば動的ポートへ退避。
const PREFERRED_PORT = 50873;

// OAuth クライアント（client_id は公開情報。secret は oauth.json / win_oauth.key から）。
const CLIENT_ID =
  '746983928581-1pg8giqolvjim3v4gogqaf5jh0f0pncf.apps.googleusercontent.com';
const SCOPES = [
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/drive.file',
];
const AUTH_EP = 'https://accounts.google.com/o/oauth2/v2/auth';
const TOKEN_EP = 'https://oauth2.googleapis.com/token';


let mainWindow = null;
let isQuitting = false;

// ─────────────────── client_secret の読込 ───────────────────
function clientSecret() {
  // パッケージ時は oauth.json（ビルド時に win_oauth.key から生成）。
  const packaged = path.join(__dirname, 'oauth.json');
  try {
    return JSON.parse(fs.readFileSync(packaged, 'utf8')).clientSecret || '';
  } catch (_) {}
  // 開発時フォールバック：リポジトリの win_oauth.key を直接読む。
  try {
    return fs.readFileSync(path.join(__dirname, '..', 'win_oauth.key'), 'utf8').trim();
  } catch (_) {}
  return '';
}

// ─────────────────── refresh_token 永続化 ───────────────────
function authCfgPath() {
  return path.join(app.getPath('userData'), 'auth.json');
}
function readAuthCfg() {
  try { return JSON.parse(fs.readFileSync(authCfgPath(), 'utf8')); } catch (_) { return {}; }
}
function writeAuthCfg(cfg) {
  try { fs.writeFileSync(authCfgPath(), JSON.stringify(cfg, null, 2), 'utf8'); }
  catch (e) { console.error('auth.json 書込失敗', e); }
}

// access_token のメモリキャッシュ（Drive用）。
let accessCache = null;
let accessExpiry = 0;
function cacheAccess(token, expiresIn) {
  if (!token) return;
  accessCache = token;
  accessExpiry = Date.now() + ((expiresIn || 3600) - 60) * 1000;
}

// ─────────────────── base64url / トークン交換 ───────────────────
function b64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function tokenRequest(params) {
  return new Promise((resolve, reject) => {
    const body = new URLSearchParams(params).toString();
    const req = https.request(
      TOKEN_EP,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            const j = JSON.parse(data);
            if (res.statusCode !== 200) {
              reject(new Error(`token ${res.statusCode}: ${data}`));
            } else {
              resolve(j);
            }
          } catch (e) { reject(e); }
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ─────────────────── 対話的ログイン（ループバック+PKCE）───────────────────
async function interactiveSignIn() {
  const secret = clientSecret();
  if (!secret) throw new Error('OAuth secret 未設定（oauth.json / win_oauth.key 不在）');

  const verifier = b64url(crypto.randomBytes(48));
  const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
  const state = b64url(crypto.randomBytes(16));

  // ループバックサーバ（空きポート自動割当）。
  const server = await new Promise((resolve) => {
    const s = http.createServer();
    s.listen(0, '127.0.0.1', () => resolve(s));
  });
  const port = server.address().port;
  const redirectUri = `http://127.0.0.1:${port}`;

  const authUrl = `${AUTH_EP}?${new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: SCOPES.join(' '),
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state,
    access_type: 'offline',
    prompt: 'consent select_account',
  }).toString()}`;

  const codePromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      try { server.close(); } catch (_) {}
      reject(new Error('ログインがタイムアウトしました'));
    }, 5 * 60 * 1000);
    server.on('request', (req, res) => {
      let u;
      try { u = new URL(req.url, redirectUri); } catch (_) { u = null; }
      if (!u || u.searchParams.get('state') !== state) {
        res.writeHead(400); res.end('invalid state'); return;
      }
      const code = u.searchParams.get('code');
      const err = u.searchParams.get('error');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(doneHtml(err));
      clearTimeout(timer);
      try { server.close(); } catch (_) {}
      if (err) reject(new Error(`Google ログイン拒否: ${err}`));
      else if (!code) reject(new Error('認可コードを取得できませんでした'));
      else resolve(code);
    });
  });

  await shell.openExternal(authUrl);
  const code = await codePromise;

  const tok = await tokenRequest({
    code,
    client_id: CLIENT_ID,
    client_secret: secret,
    redirect_uri: redirectUri,
    grant_type: 'authorization_code',
    code_verifier: verifier,
  });
  if (!tok.id_token || !tok.access_token) throw new Error('id_token/access_token が空');
  if (tok.refresh_token) {
    const cfg = readAuthCfg();
    cfg.refresh_token = tok.refresh_token;
    writeAuthCfg(cfg);
  }
  cacheAccess(tok.access_token, tok.expires_in);
  return { idToken: tok.id_token, accessToken: tok.access_token };
}

// ─────────────────── 自動ログイン（refresh_token）───────────────────
async function silentTokens() {
  const secret = clientSecret();
  const cfg = readAuthCfg();
  if (!secret || !cfg.refresh_token) return null;
  try {
    const tok = await tokenRequest({
      client_id: CLIENT_ID,
      client_secret: secret,
      refresh_token: cfg.refresh_token,
      grant_type: 'refresh_token',
    });
    if (tok.refresh_token) { cfg.refresh_token = tok.refresh_token; writeAuthCfg(cfg); }
    cacheAccess(tok.access_token, tok.expires_in);
    if (!tok.id_token || !tok.access_token) return null;
    return { idToken: tok.id_token, accessToken: tok.access_token };
  } catch (e) {
    console.error('silentTokens 失敗', e.message);
    return null;
  }
}

async function driveToken(force) {
  if (!force && accessCache && Date.now() < accessExpiry) return accessCache;
  const secret = clientSecret();
  const cfg = readAuthCfg();
  if (!secret || !cfg.refresh_token) return null;
  try {
    const tok = await tokenRequest({
      client_id: CLIENT_ID,
      client_secret: secret,
      refresh_token: cfg.refresh_token,
      grant_type: 'refresh_token',
    });
    cacheAccess(tok.access_token, tok.expires_in);
    return tok.access_token || null;
  } catch (e) {
    console.error('driveToken 失敗', e.message);
    return null;
  }
}

function doneHtml(error) {
  const ok = !error;
  const title = ok ? 'ログイン完了' : 'ログインに失敗しました';
  const msg = ok
    ? 'このタブを閉じて、FutaFinance に戻ってください。'
    : `アプリに戻ってもう一度お試しください。（${error}）`;
  return `<!DOCTYPE html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>body{font-family:'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;display:flex;
align-items:center;justify-content:center;height:100vh;margin:0}.card{background:#1e293b;
padding:40px 48px;border-radius:16px;text-align:center;box-shadow:0 10px 40px rgba(0,0,0,.4)}
h1{font-size:20px;margin:0 0 12px}p{font-size:14px;color:#94a3b8;margin:0}
.mark{font-size:48px;margin-bottom:8px}</style></head><body><div class="card">
<div class="mark">${ok ? '✅' : '⚠️'}</div><h1>${title}</h1><p>${msg}</p></div></body></html>`;
}

// ─────────────────── ローカル静的配信サーバ ───────────────────
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream', '.map': 'application/json', '.txt': 'text/plain; charset=utf-8',
};

function webDir() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'web-dist')
    : path.join(__dirname, 'web-dist');
}

function startServer() {
  const root = webDir();
  const handler = (req, res) => {
    let urlPath;
    try { urlPath = decodeURIComponent(req.url.split('?')[0]); } catch (_) { urlPath = '/'; }
    if (urlPath === '/' || urlPath === '') urlPath = '/index.html';
    const file = path.join(root, path.normalize(urlPath).replace(/^([/\\])+/, ''));
    if (!file.startsWith(root)) { res.writeHead(403); res.end(); return; }
    fs.readFile(file, (err, data) => {
      if (err) {
        // 未知パスは index.html へフォールバック（SPA ルーティング）。
        fs.readFile(path.join(root, 'index.html'), (e2, idx) => {
          if (e2) { res.writeHead(404); res.end('not found'); return; }
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(idx);
        });
        return;
      }
      const ext = path.extname(file).toLowerCase();
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
      res.end(data);
    });
  };
  return new Promise((resolve) => {
    const srv = http.createServer(handler);
    srv.once('error', () => {
      // 固定ポートが塞がっていれば動的ポートへ（永続は失うが起動優先）。
      const srv2 = http.createServer(handler);
      srv2.listen(0, '127.0.0.1', () => resolve(srv2.address().port));
    });
    srv.listen(PREFERRED_PORT, '127.0.0.1', () => resolve(PREFERRED_PORT));
  });
}

// ─────────────────── ウィンドウ状態の記憶/復元 ───────────────────
function windowStatePath() {
  return path.join(app.getPath('userData'), 'window.json');
}
function readWindowState() {
  try { return JSON.parse(fs.readFileSync(windowStatePath(), 'utf8')); } catch (_) { return {}; }
}
function saveWindowState(win) {
  if (!win || win.isDestroyed()) return;
  try {
    // 最大化前の通常サイズ/位置を保存（最大化フラグも別に持つ）。
    const b = win.getNormalBounds();
    const state = {
      x: b.x, y: b.y, width: b.width, height: b.height,
      isMaximized: win.isMaximized(),
    };
    fs.writeFileSync(windowStatePath(), JSON.stringify(state), 'utf8');
  } catch (_) {}
}

// ─────────────────── ウィンドウ ───────────────────
async function createWindow() {
  const port = await startServer();
  const st = readWindowState();
  mainWindow = new BrowserWindow({
    width: st.width || 1180,
    height: st.height || 820,
    x: st.x,            // 未保存なら undefined → 中央
    y: st.y,
    minWidth: 760,
    minHeight: 560,
    backgroundColor: '#F7F8FA',
    title: APP_TITLE,
    icon: path.join(__dirname, 'assets', 'icon.ico'),
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js'),
    },
  });
  // 前回が最大化なら最大化で開く。
  if (st.isMaximized) mainWindow.maximize();

  // アプリ外リンクはシステムブラウザで。
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://127.0.0.1')) return { action: 'allow' };
    shell.openExternal(url);
    return { action: 'deny' };
  });

  // サイズ/位置/最大化の変化を保存（連続イベントはデバウンス）。
  let saveTimer = null;
  const scheduleSave = () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => saveWindowState(mainWindow), 400);
  };
  mainWindow.on('resize', scheduleSave);
  mainWindow.on('move', scheduleSave);
  mainWindow.on('maximize', () => saveWindowState(mainWindow));
  mainWindow.on('unmaximize', () => saveWindowState(mainWindow));
  mainWindow.on('close', () => saveWindowState(mainWindow));
  mainWindow.on('closed', () => { mainWindow = null; });
  mainWindow.loadURL(`http://127.0.0.1:${port}/`);
}

// ─────────────── 自動更新（electron-updater + GitHub Releases NSIS）───────────────
// NSIS インストーラが %LOCALAPPDATA%\Programs\FutaFinance に配置する。
// electron-updater が latest.yml を GitHub Releases から取得し、バックグラウンドで
// 自動ダウンロード → アプリ終了時（または今すぐ）にサイレントインストール。

// このアプリ自身の版情報（build-info.json をアプリ内に同梱）。
function readBuildInfo() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, 'build-info.json'), 'utf8'));
  } catch (_) { return { version: app.getVersion(), buildNumber: 0 }; }
}

function setupAutoUpdater() {
  if (!app.isPackaged) return;

  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;

  autoUpdater.on('update-downloaded', (info) => {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    dialog.showMessageBox(mainWindow, {
      type: 'info',
      title: 'FutaFinance - アップデート準備完了',
      message: `v${info.version} の準備ができました`,
      detail: '今すぐ再起動してインストールしますか？',
      buttons: ['今すぐ再起動', '後で'],
      defaultId: 0, cancelId: 1,
    }).then(({ response }) => {
      if (response === 0) autoUpdater.quitAndInstall();
    });
  });

  autoUpdater.on('error', (err) => console.warn('[update]', err.message));
}

// ─────────────────── IPC ───────────────────
ipcMain.handle('futa:signIn', () => interactiveSignIn());
ipcMain.handle('futa:silent', () => silentTokens());
ipcMain.handle('futa:driveToken', (_e, force) => driveToken(force));
ipcMain.handle('futa:signOut', () => {
  const cfg = readAuthCfg();
  delete cfg.refresh_token;
  writeAuthCfg(cfg);
  accessCache = null; accessExpiry = 0;
  return true;
});
ipcMain.handle('futa:checkUpdate', async () => {
  if (!app.isPackaged) {
    await dialog.showMessageBox(mainWindow, {
      type: 'info', title: '更新確認', message: '開発モードでは更新チェックは無効です。',
    });
    return;
  }
  try {
    await autoUpdater.checkForUpdates();
  } catch (e) {
    await dialog.showMessageBox(mainWindow, {
      type: 'warning', title: '更新確認',
      message: '更新確認に失敗しました（インターネット接続を確認してください）。',
    });
  }
});

// ─────────────────── 起動 ───────────────────
// 二重起動防止。
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
  app.setAppUserModelId('jp.runstrategy.futafinance.desktop');
  app.whenReady().then(async () => {
    // Service Worker は使わない（ローカル配信なので不要）。過去に登録された
    // SW のキャッシュで更新後も古い画面が出るのを防ぐため破棄するが、
    // ウィンドウ表示を待たせないよう非同期で投げる（起動を速く）。
    session.defaultSession
        .clearStorageData({ storages: ['serviceworkers'] })
        .catch(() => {});
    setupAutoUpdater();
    await createWindow();
    // 起動 3 秒後に更新チェック、以降 3 分ごとに定期チェック。
    setTimeout(() => autoUpdater.checkForUpdates().catch(() => {}), 3000);
    setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 3 * 60 * 1000);
  });
  app.on('window-all-closed', () => { if (!isQuitting) app.quit(); });
  app.on('activate', () => { if (mainWindow === null) createWindow(); });
}
