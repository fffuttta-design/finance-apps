/// Electron デスクトップ版のネイティブ機能ブリッジ（ファサード）。
///
/// FutaFinance の Web ビルドを Electron の中で動かすとき、Electron の preload が
/// `window.futaDesktop` を注入する。そのときだけ [isDesktopShell] が true になり、
/// Google ログイン等を Electron メインプロセス側の自前 OAuth に委譲する。
///
/// Android / iOS / 通常のブラウザでは window.futaDesktop が無いので
/// [isDesktopShell] は false。既存の挙動は一切変わらない。
///
/// 実装は web（js_interop あり）と非web（スタブ）で条件付き切替。
library;

export 'desktop_bridge_stub.dart'
    if (dart.library.js_interop) 'desktop_bridge_web.dart';
