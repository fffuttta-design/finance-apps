import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'nav_history.dart';

/// Web/Electron 用。`window.futaGoForward()` を生やし、Electron の
/// app-command（マウス進むボタン）から Flutter の goForward を呼べるようにする。
void registerForwardHook() {
  globalContext.setProperty(
    'futaGoForward'.toJS,
    (() => NavHistory.instance.goForward()).toJS,
  );
}
