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

// Drive 配布フォルダ候補（自己更新用）。
const DRIVE_CANDIDATES = [
  'H:\\マイドライブ\\ツール開発\\FutaFinance-Desktop',
  'G:\\マイドライブ\\ツール開発\\FutaFinance-Desktop',
  'H:\\My Drive\\ツール開発\\FutaFinance-Desktop',
  'G:\\My Drive\\ツール開発\\FutaFinance-Desktop',
];
const RELEASE_EXE_NAME = 'FutaFinance-Setup.exe'; // DriveのNSISインストーラ（固定名）

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

// ─────────────── 自己更新（FutaMemo方式: dir + robocopy + explorer.exe）───────────────
// 配布はNSISではなく「展開済みフォルダ」。Driveの app\ から %LOCALAPPDATA%\FutaFinance へ
// robocopy でコピーし、新版は explorer.exe 経由で起動する。explorer.exe で起動すると新
// プロセスはシェル(explorer)の子になり、終了する旧アプリの道連れにならない＝
// 「更新→落ちて戻らない」ループの根本対策。
const APP_NAME = 'FutaFinance';
const LOCAL_INSTALL_DIR = path.join(process.env.LOCALAPPDATA || '', APP_NAME);
const LOCAL_EXE = path.join(LOCAL_INSTALL_DIR, `${APP_NAME}.exe`);

function findDriveDir() {
  for (const d of DRIVE_CANDIDATES) {
    try { if (fs.statSync(d).isDirectory()) return d; } catch (_) {}
  }
  return null;
}

// このアプリ自身の版情報（build-info.json をアプリ内に同梱）。
function readBuildInfo() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, 'build-info.json'), 'utf8'));
  } catch (_) { return { version: app.getVersion(), buildNumber: 0 }; }
}

// 更新元（Driveの app フォルダ）のパスを覚えておく。
function updateSourceCfgPath() {
  return path.join(app.getPath('userData'), 'update-source.json');
}
function getUpdateSourcePath() {
  try {
    const c = JSON.parse(fs.readFileSync(updateSourceCfgPath(), 'utf8'));
    return typeof c.sourcePath === 'string' ? c.sourcePath : null;
  } catch (_) { return null; }
}
function saveUpdateSourcePath(sourcePath) {
  try {
    fs.writeFileSync(updateSourceCfgPath(), JSON.stringify({ sourcePath }), 'utf8');
  } catch (_) {}
}

// 進捗表示するPowerShellコンソールを新規ウィンドウで実行（✕無効化・末尾自動クローズ）。
function launchPS1(scriptLines) {
  const tmpPath = path.join(app.getPath('temp'), `futafinance-${Date.now()}.ps1`);
  const bom = '﻿';
  const header = [
    '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8',
    '$OutputEncoding = [System.Text.Encoding]::UTF8',
    'Add-Type @"',
    'using System;',
    'using System.Runtime.InteropServices;',
    'public class FfConsole {',
    '    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();',
    '    [DllImport("user32.dll")]   public static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);',
    '    [DllImport("user32.dll")]   public static extern bool RemoveMenu(IntPtr hMenu, uint nPos, uint wFlags);',
    '}',
    '"@',
    '$hwnd = [FfConsole]::GetConsoleWindow()',
    'if ($hwnd -ne [IntPtr]::Zero) {',
    '    $hmenu = [FfConsole]::GetSystemMenu($hwnd, $false)',
    '    [void][FfConsole]::RemoveMenu($hmenu, 0xF060, 0x00000000)',
    '}',
    '',
  ];
  const footer = ['', 'exit 0'];
  try {
    fs.writeFileSync(tmpPath, bom + [...header, ...scriptLines, ...footer].join('\n'), 'utf8');
    exec(`cmd /c start powershell.exe -ExecutionPolicy Bypass -NoProfile -File "${tmpPath}"`);
  } catch (e) { console.error('launchPS1 failed', e); }
}

// 新版を robocopy で適用してから explorer.exe で起動（進捗コンソールあり）。
function applyUpdate(sourcePath, newVersion, newBuild) {
  launchPS1([
    'Write-Host ""',
    'Write-Host "=====================================" -ForegroundColor Cyan',
    'Write-Host "  FutaFinance  アップデート" -ForegroundColor Cyan',
    'Write-Host "=====================================" -ForegroundColor Cyan',
    'Write-Host ""',
    'Write-Host "[1/3] アプリを終了しました" -ForegroundColor Green',
    'Start-Sleep -Seconds 2',
    `Write-Host "[2/3] 最新版をコピー中... (v${newVersion} / build ${newBuild})" -ForegroundColor Yellow`,
    `robocopy "${sourcePath}" "${LOCAL_INSTALL_DIR}" /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS /NP`,
    'if ($LASTEXITCODE -ge 8) {',
    '  Write-Host "  [エラー] コピーに失敗しました (code: $LASTEXITCODE)" -ForegroundColor Red',
    '  Read-Host "  Enterキーで閉じる"; exit 1',
    '}',
    'Write-Host "    コピーしました" -ForegroundColor Green',
    'Start-Sleep -Seconds 1',
    'Write-Host "[3/3] アプリを起動します..." -ForegroundColor Cyan',
    `explorer.exe "${LOCAL_EXE}"`,
    'Start-Sleep -Seconds 1',
  ]);
  isQuitting = true;
  setTimeout(() => app.exit(0), 400);
}

// Drive等から直接起動されたら、ローカル(%LOCALAPPDATA%\FutaFinance)へ入れて起動し直す。
// 戻り値 true なら終了シーケンスに入っているので呼び出し側はそのまま return する。
async function autoInstallIfNeeded() {
  if (!app.isPackaged) return false;
  const exeDir = path.dirname(app.getPath('exe'));
  if (exeDir.toLowerCase() === LOCAL_INSTALL_DIR.toLowerCase()) return false;

  // 次回更新の参照元として、今起動した場所(=Driveのappフォルダ)を保存。
  saveUpdateSourcePath(exeDir);

  // ローカルに既にあり最新なら、窓を出さず静かにローカル版を起動。
  if (fs.existsSync(LOCAL_EXE)) {
    let driveBuild = 0; let localBuild = 0;
    try { driveBuild = JSON.parse(fs.readFileSync(path.join(exeDir, 'version.json'), 'utf8')).buildNumber || 0; } catch (_) {}
    try { localBuild = JSON.parse(fs.readFileSync(path.join(LOCAL_INSTALL_DIR, 'version.json'), 'utf8')).buildNumber || 0; } catch (_) {}
    if (localBuild >= driveBuild) {
      try { app.releaseSingleInstanceLock(); } catch (_) {}
      await shell.openPath(LOCAL_EXE);
      setTimeout(() => app.exit(0), 600);
      return true;
    }
  }
  // 初回 or Driveが新しい → インストール(robocopy)＋ショートカット作成＋explorer起動。
  launchPS1([
    'Write-Host ""',
    'Write-Host "  FutaFinance インストール" -ForegroundColor Cyan',
    'Write-Host "[1/2] ローカルにインストール中..." -ForegroundColor Yellow',
    `robocopy "${exeDir}" "${LOCAL_INSTALL_DIR}" /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS /NP`,
    'if ($LASTEXITCODE -ge 8) { Write-Host "  [エラー] インストール失敗 (code: $LASTEXITCODE)" -ForegroundColor Red; Read-Host "Enterで閉じる"; exit 1 }',
    '$ws = New-Object -ComObject WScript.Shell',
    '$dt = [Environment]::GetFolderPath("Desktop")',
    `$sc = $ws.CreateShortcut((Join-Path $dt "FutaFinance.lnk")); $sc.TargetPath = "${LOCAL_EXE}"; $sc.Save()`,
    '$sm = Join-Path $env:APPDATA "Microsoft\\Windows\\Start Menu\\Programs"',
    `$sc2 = $ws.CreateShortcut((Join-Path $sm "FutaFinance.lnk")); $sc2.TargetPath = "${LOCAL_EXE}"; $sc2.Save()`,
    'Write-Host "    完了" -ForegroundColor Green',
    'Write-Host "[2/2] アプリを起動します..." -ForegroundColor Cyan',
    `explorer.exe "${LOCAL_EXE}"`,
    'Start-Sleep -Seconds 1',
  ]);
  isQuitting = true;
  setTimeout(() => app.exit(0), 400);
  return true;
}

async function checkForUpdate(opts = {}) {
  const manual = opts.manual === true;
  if (!app.isPackaged) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'info', title: '更新確認', message: '開発モードでは更新チェックは無効です。',
      });
    }
    return;
  }
  // 更新元(Driveのappフォルダ)。記録が無ければ Drive 候補の app\ を探す。
  let sourcePath = getUpdateSourcePath();
  if (!sourcePath || !fs.existsSync(path.join(sourcePath, 'version.json'))) {
    const dir = findDriveDir();
    if (dir && fs.existsSync(path.join(dir, 'app', 'version.json'))) {
      sourcePath = path.join(dir, 'app');
      saveUpdateSourcePath(sourcePath);
    }
  }
  if (!sourcePath || !fs.existsSync(path.join(sourcePath, 'version.json'))) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'warning', title: '更新確認',
        message: '更新情報が見つかりません（Google ドライブの同期を確認してください）。',
      });
    }
    return;
  }
  let remote; let local;
  try {
    remote = JSON.parse(fs.readFileSync(path.join(sourcePath, 'version.json'), 'utf8'));
    local = readBuildInfo();
  } catch (_) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'warning', title: '更新確認', message: '更新情報の読込に失敗しました。',
      });
    }
    return;
  }
  const remoteNum = remote.buildNumber || 0;
  const localNum = local.buildNumber || 0;
  if (remoteNum <= localNum) {
    if (manual) {
      await dialog.showMessageBox(mainWindow, {
        type: 'info', title: '更新確認', message: `最新版です（v${local.version}）。`,
      });
    }
    return;
  }
  if (!mainWindow || mainWindow.isDestroyed()) return;
  if (!mainWindow.isVisible()) { mainWindow.show(); mainWindow.focus(); }
  const { response } = await dialog.showMessageBox(mainWindow, {
    type: 'info',
    title: 'FutaFinance - アップデート',
    message: '新しいバージョンがあります',
    detail: `現在 : v${local.version}\n最新 : v${remote.version}\n\n`
        + '今すぐ更新しますか？（進捗が表示され、自動で開き直します）',
    buttons: ['今すぐ更新', '後で'],
    defaultId: 0, cancelId: 1, noLink: true,
  });
  if (response === 0) applyUpdate(sourcePath, remote.version, remoteNum);
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
    // Drive等から直接起動された場合は %LOCALAPPDATA% へ入れて起動し直す（安定起動）。
    // 戻り値 true なら終了シーケンス中なのでここで終わる。
    if (await autoInstallIfNeeded()) return;
    // Service Worker は使わない（ローカル配信なので不要）。過去に登録された
    // SW のキャッシュで更新後も古い画面が出るのを防ぐため、起動毎に破棄。
    // ※ IndexedDB（Firebase の認証/オフライン永続）は消さない。
    try {
      await session.defaultSession.clearStorageData({ storages: ['serviceworkers'] });
    } catch (_) {}
    await createWindow();
    // 起動後しばらくして更新チェック（新版があれば「今すぐ更新/後で」ダイアログ）。
    setTimeout(() => { checkForUpdate({}).catch((e) => console.error(e)); }, 3000);
  });
  app.on('window-all-closed', () => { if (!isQuitting) app.quit(); });
  app.on('activate', () => { if (mainWindow === null) createWindow(); });
}
