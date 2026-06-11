import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web（Electron 内）向けブリッジ実装。
/// Electron の preload が注入する `window.futaDesktop` を呼び出す。
class DesktopTokens {
  const DesktopTokens(this.idToken, this.accessToken);
  final String idToken;
  final String accessToken;
}

/// window.futaDesktop（無ければ null）。
JSObject? get _bridge {
  if (!globalContext.has('futaDesktop')) return null;
  final b = globalContext['futaDesktop'];
  return b.isDefinedAndNotNull ? b as JSObject : null;
}

/// Electron デスクトップ版で動いているか（ブリッジが注入されているか）。
bool get isDesktopShell => _bridge != null;

/// 対話的ログイン（ブラウザで Google 同意 → トークン取得）。
Future<DesktopTokens> desktopSignIn() async {
  final res = await _bridge!
      .callMethod<JSPromise<JSObject?>>('signIn'.toJS)
      .toDart;
  if (res == null) {
    throw StateError('デスクトップのログインに失敗しました');
  }
  return _toTokens(res);
}

/// 保存済み refresh_token から黙ってトークンを取得（起動時の自動ログイン用）。
Future<DesktopTokens?> desktopSilentTokens() async {
  final res = await _bridge!
      .callMethod<JSPromise<JSObject?>>('silent'.toJS)
      .toDart;
  if (res == null) return null;
  return _toTokens(res);
}

/// Drive 用アクセストークン（refresh_token から更新）。無ければ null。
Future<String?> desktopDriveToken({bool forceRefresh = false}) async {
  final res = await _bridge!
      .callMethod<JSPromise<JSString?>>('driveToken'.toJS, forceRefresh.toJS)
      .toDart;
  return res?.toDart;
}

/// サインアウト（保存済み refresh_token を破棄）。
Future<void> desktopSignOut() async {
  await _bridge!.callMethod<JSPromise<JSAny?>>('signOut'.toJS).toDart;
}

DesktopTokens _toTokens(JSObject o) {
  final id = (o['idToken'] as JSString?)?.toDart ?? '';
  final ac = (o['accessToken'] as JSString?)?.toDart ?? '';
  return DesktopTokens(id, ac);
}
