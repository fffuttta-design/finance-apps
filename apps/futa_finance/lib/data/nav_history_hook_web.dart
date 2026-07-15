import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'nav_history.dart';

/// Web/Electron 用。`window.futaGoBack()` / `window.futaGoForward()` を生やし、
/// Electron の app-command（マウスの戻る/進むボタン）から Flutter の画面遷移を呼べるようにする。
/// ⚠ `window.history.back()` ではダメ。Flutter(Navigator 1.0)は画面遷移を
///    ブラウザ履歴に積まないので、何も起きないかアプリ自体が前のURLへ飛んでしまう。
void registerForwardHook() {
  globalContext.setProperty(
    'futaGoBack'.toJS,
    (() => NavHistory.instance.goBack()).toJS,
  );
  globalContext.setProperty(
    'futaGoForward'.toJS,
    (() => NavHistory.instance.goForward()).toJS,
  );
}
