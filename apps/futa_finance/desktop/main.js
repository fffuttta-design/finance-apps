// FutaFinance デスクトップ版（Electron）メインプロセス。
//
// 役割:
//  1. ローカル同梱した Flutter Web ビルド(web-dist/)を http://127.0.0.1:固定ポート で配信
//     （固定オリジンにすることで Firebase/IndexedDB のオフライン永続が効く）
//  2. Google ログインを自前 OAuth（ループバック＋PKCE）で実施し、トークンを
//     preload 経由で Flutter に渡す（埋め込み画面は Google に弾かれるため）
//  3. Drive リリースフォルダを見て自己更新（best-effort）
const {
  app, BrowserWindow, ipcMain, shell, dialog, session,
} = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const { spawn } = require('child_process');

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

// Drive 配布フォルダ候補（自己更新用）。
const DRIVE_CANDIDATES = [
  'H:\\マイドライブ\\ツール開発\\FutaFinance-Desktop',
  'G:\\マイドライブ\\ツール開発\\FutaFinance-Desktop',
  'H:\\My Drive\\ツール開発\\FutaFinance-Desktop',
  'G:\\My Drive\\ツール開発\\FutaFinance-Desktop',
];
const RELEASE_EXE_NAME = 'FutaFinance.exe';

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

// ─────────────────── ウィンドウ ───────────────────
async function createWindow() {
  const port = await startServer();
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 820,
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
  // アプリ外リンクはシステムブラウザで。
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://127.0.0.1')) return { action: 'allow' };
    shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.on('closed', () => { mainWindow = null; });
  mainWindow.loadURL(`http://127.0.0.1:${port}/`);
}

// ─────────────────── 自己更新（Drive・best-effort）───────────────────
function selfExePath() {
  return process.env.PORTABLE_EXECUTABLE_FILE || process.execPath;
}
function findDriveDir() {
  for (const d of DRIVE_CANDIDATES) {
    try { if (fs.statSync(d).isDirectory()) return d; } catch (_) {}
  }
  return null;
}
function cmpVer(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
  }
  return 0;
}
async function checkForUpdate(opts = {}) {
  const manual = opts.manual === true; // 設定画面の「最新バージョンを確認」から呼ぶ時 true
  const auto = opts.auto === true;     // 起動時の自動チェック（見つかれば確認なしで適用）
  if (!app.isPackaged && !manual) return;
  const dir = findDriveDir();
  if (!dir) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'warning', title: '更新確認',
        message: '配布フォルダが見つかりません（Google ドライブの同期を確認してください）。',
      });
    }
    return;
  }
  let remote;
  try {
    remote = fs.readFileSync(path.join(dir, 'version.txt'), 'utf8').trim();
  } catch (_) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'warning', title: '更新確認', message: 'バージョン情報を取得できませんでした。',
      });
    }
    return;
  }
  if (!remote || cmpVer(remote, app.getVersion()) <= 0) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'info', title: '更新確認', message: `最新版です（v${app.getVersion()}）。`,
      });
    }
    return;
  }
  const exeSrc = path.join(dir, RELEASE_EXE_NAME);
  if (!fs.existsSync(exeSrc)) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'warning', title: '更新確認', message: '更新ファイルが見つかりませんでした。',
      });
    }
    return;
  }
  // 起動時の自動チェックで新版が見つかったら、確認なしでそのまま適用＆再起動。
  if (auto) {
    applyUpdate(exeSrc);
    return;
  }
  const choice = await dialog.showMessageBox(mainWindow, {
    type: 'info',
    buttons: ['更新する', '後で'],
    defaultId: 0,
    cancelId: 1,
    title: 'アップデート',
    message: `新しいバージョン v${remote} があります（現在 v${app.getVersion()}）。`,
    detail: '更新すると一度アプリを再起動します。',
  });
  if (choice.response === 0) applyUpdate(exeSrc);
}
function applyUpdate(newExeSrc) {
  const ourPid = process.pid;
  const target = selfExePath();
  const src = newExeSrc.replace(/'/g, "''");
  const dst = target.replace(/'/g, "''");
  const ps =
    "$host.UI.RawUI.WindowTitle = 'FutaFinance アップデート'\n" +
    `try { Wait-Process -Id ${ourPid} -Timeout 15 -ErrorAction Stop } catch {}\n` +
    'for ($i = 0; $i -lt 20; $i++) {\n' +
    `  try { Copy-Item -LiteralPath '${src}' -Destination '${dst}' -Force -ErrorAction Stop; break }\n` +
    '  catch { Start-Sleep -Milliseconds 500 }\n' +
    '}\n' +
    `Start-Process -FilePath '${dst}' -ArgumentList '--updated'\n`;
  const scriptPath = path.join(os.tmpdir(), 'futafinance_update.ps1');
  fs.writeFileSync(scriptPath, ps, { encoding: 'utf8' });
  spawn('powershell.exe', ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptPath], {
    detached: true, stdio: 'ignore',
  }).unref();
  isQuitting = true;
  app.quit();
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
ipcMain.handle('futa:checkUpdate', () => checkForUpdate({ manual: true }));

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
    // SW のキャッシュで更新後も古い画面が出るのを防ぐため、起動毎に破棄。
    // ※ IndexedDB（Firebase の認証/オフライン永続）は消さない。
    try {
      await session.defaultSession.clearStorageData({ storages: ['serviceworkers'] });
    } catch (_) {}
    await createWindow();
    // 自己置換更新で再起動してきた時は、完了をさりげなく通知。
    if (process.argv.includes('--updated')) {
      dialog.showMessageBox(mainWindow, {
        type: 'info', title: 'FutaFinance',
        message: `最新版 v${app.getVersion()} に更新しました。`,
      }).catch(() => {});
    }
    // 起動時の自動更新チェック（新版があれば確認なしで適用＆再起動）。
    setTimeout(() => { checkForUpdate({ auto: true }).catch((e) => console.error(e)); }, 2500);
  });
  app.on('window-all-closed', () => { if (!isQuitting) app.quit(); });
  app.on('activate', () => { if (mainWindow === null) createWindow(); });
}
