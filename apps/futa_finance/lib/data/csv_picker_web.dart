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
              final res = reader.result;
              if (res == null) {
                finish(null);
                return;
              }
              final bytes = (res as JSArrayBuffer).toDart.asUint8List();
              finish((name: file.name, bytes: bytes));
            }).toJS);
        reader.addEventListener('error', ((web.Event _) => finish(null)).toJS);
        reader.readAsArrayBuffer(file);
      }).toJS);

  // キャンセル（ファイル未選択でダイアログを閉じた）も拾う。
  input.addEventListener(
      'cancel', ((web.Event _) => finish(null)).toJS);

  input.click();
  return completer.future;
}
