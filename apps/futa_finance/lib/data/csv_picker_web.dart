import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web/Electron 向け：ブラウザ標準の `<input type=file>` を直接使ってCSVを選ぶ。
/// file_picker が Electron で結果を返さない問題を回避するため、自前で実装する。
Future<({String name, Uint8List bytes})?> pickCsvFile() {
  final completer = Completer<({String name, Uint8List bytes})?>();

  final input = web.HTMLInputElement();
  input.type = 'file';
  input.accept = '.csv,text/csv';
  // 一部環境では DOM に付いていないと click が効かないため、隠して付与。
  input.style.display = 'none';
  web.document.body?.append(input);

  void finish(({String name, Uint8List bytes})? value) {
    if (!completer.isCompleted) completer.complete(value);
    input.remove();
  }

  input.addEventListener(
      'change',
      ((web.Event _) {
        try {
          final files = input.files;
          if (files == null || files.length == 0) {
            finish(null);
            return;
          }
          final file = files.item(0);
          if (file == null) {
            finish(null);
            return;
          }
          final reader = web.FileReader();
          reader.addEventListener(
              'load',
              ((web.Event _) {
                try {
                  final res = reader.result;
                  if (res == null) {
                    finish(null);
                    return;
                  }
                  final bytes = (res as JSArrayBuffer).toDart.asUint8List();
                  finish((name: file.name, bytes: bytes));
                } catch (_) {
                  finish(null);
                }
              }).toJS);
          reader.addEventListener(
              'error', ((web.Event _) => finish(null)).toJS);
          reader.readAsArrayBuffer(file);
        } catch (_) {
          finish(null);
        }
      }).toJS);

  // ※ 'cancel' イベントは一部 Electron/Chromium で選択時にも発火し、せっかく選んだ
  //   ファイルを null で潰す不具合があるため購読しない（キャンセル時は Future 未完了＝無害）。

  input.click();
  return completer.future;
}
