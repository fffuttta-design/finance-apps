// FutaFinance デスクトップ版 preload。
// レンダラ（Flutter Web）に window.futaDesktop を注入する。
// Flutter 側の desktop_bridge_web.dart がこれを呼び出して
// Google ログイン（自前 OAuth）等をメインプロセスに委譲する。
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('futaDesktop', {
  isDesktop: true,
  // 対話的ログイン → { idToken, accessToken }
  signIn: () => ipcRenderer.invoke('futa:signIn'),
  // 保存済み refresh_token から自動ログイン → { idToken, accessToken } | null
  silent: () => ipcRenderer.invoke('futa:silent'),
  // Drive 用アクセストークン → string | null
  driveToken: (force) => ipcRenderer.invoke('futa:driveToken', !!force),
  // サインアウト（refresh_token 破棄）
  signOut: () => ipcRenderer.invoke('futa:signOut'),
  // 手動アップデート確認（Driveのversion.txtと照合・ネイティブダイアログ表示）
  checkUpdate: () => ipcRenderer.invoke('futa:checkUpdate'),
  // 公開Driveファイル(証憑)をメインプロセスで取得 → base64 | null（CORS/ブラウザ非依存）
  downloadFile: (fileId) => ipcRenderer.invoke('futa:downloadFile', fileId),
});
