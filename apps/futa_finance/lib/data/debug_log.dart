import 'package:flutter/foundation.dart';

/// 画面上で見られる簡易デバッグログ。
///
/// Electron(Flutter Web)ではブラウザのコンソールが見えないので、CSV取り込みなどの
/// 処理ステップをここに溜めて、画面のダイアログで確認できるようにする。
class DebugLog {
  DebugLog._();

  static final ValueNotifier<List<String>> notifier =
      ValueNotifier<List<String>>(<String>[]);

  static final List<String> _lines = [];
  static int _seq = 0;

  /// 1行追記する。連番付き（時刻はプラットフォーム差を避け連番で代用）。
  static void add(String msg) {
    _seq++;
    _lines.add('#$_seq  $msg');
    if (_lines.length > 300) _lines.removeAt(0);
    notifier.value = List<String>.from(_lines);
  }

  static void clear() {
    _lines.clear();
    _seq = 0;
    notifier.value = <String>[];
  }

  static String get text => _lines.join('\n');
}
