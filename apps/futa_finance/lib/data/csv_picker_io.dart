import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// モバイル/ネイティブ向け：file_picker でCSVを選ぶ。
Future<({String name, Uint8List bytes})?> pickCsvFile() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  final b = f.bytes;
  if (b == null) return null;
  return (name: f.name, bytes: b);
}
