import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/receipt_ocr.dart';
import '../data/tx_repository.dart';
import 'receipt_camera_screen.dart';
import 'receipt_split_screen.dart';

/// レシートで記録：画像選択 → Gemini読み取り → 入力画面をプリフィルして開く。
/// 何か記録できたら true を返す。
Future<bool> runReceiptFlow(BuildContext context) async {
  if (!ReceiptOcr.available) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('レシート読み取りはアプリ版でご利用ください')),
    );
    return false;
  }

  // 自前カメラ画面（デフォ=カメラ起動 / 右下=ギャラリー）で撮影 or 選択。
  final bytes = await Navigator.push<Uint8List>(
    context,
    MaterialPageRoute(builder: (_) => const ReceiptCameraScreen()),
  );
  if (bytes == null || !context.mounted) return false;
  const mime = 'image/jpeg';

  // 撮影画像を一度だけ軽く圧縮（OCR送信・Drive保存・表示すべてを高速化）。
  // 失敗時は元画像をそのまま使う。
  final imgBytes = await _compressReceipt(bytes);
  if (!context.mounted) return false;

  // ★ Drive保存は“完全に裏で”実行（ユーザーは一切待たない）。
  //   撮影直後に開始し、完了したら その receiptId の取引へ画像URLを後付けする。
  //   - 保存より先にアップロード完了 → urlForキャッシュ経由で保存時に付与
  //   - アップロードより先に保存 → attachReceiptUrl で後から付与
  final receiptId = DateTime.now().microsecondsSinceEpoch.toString();
  final hidForUpload = HouseholdService.instance.householdId;
  unawaited(() async {
    final url = await DriveReceiptService.instance
        .uploadReceiptImage(bytes: imgBytes, date: DateTime.now());
    if (url == null) return;
    DriveReceiptService.instance.rememberUrl(receiptId, url);
    if (hidForUpload != null) {
      try {
        await TxRepository.instance
            .attachReceiptUrl(hidForUpload, receiptId, url);
      } catch (_) {/* 後付け失敗は無視（画像リンクが付かないだけ） */}
    }
  }());

  // 読み取り中インジケータ
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 16),
        Text('レシートを読み取り中...'),
      ]),
    ),
  );

  ReceiptResult? result;
  String? error;
  try {
    result = await ReceiptOcr.instance.recognize(imgBytes, mime: mime);
  } catch (e) {
    error = '$e';
  }
  // Drive保存は裏で継続中（待たない）。OCRが終わり次第すぐ画面へ。
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop(); // インジケータを閉じる

  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('読み取りに失敗しました: $error')),
    );
    return false;
  }
  if (result == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('うまく読み取れませんでした。手入力でお願いします')),
    );
    return false;
  }

  if (!context.mounted) return false;

  final r = result; // ここまでで null チェック済み（非null確定）

  // レシートは常に「品目ごと」に記録（1品目=1記録）。まとめて1件は廃止。
  final changed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => ReceiptSplitScreen(
        result: r,
        receiptId: receiptId,
      ),
    ),
  );
  return changed == true;
}

/// レシート画像を軽く圧縮してバイト列を返す（品質70・長辺〜1920px）。
/// レシートの文字が潰れない範囲でサイズを落とし、OCR送信/保存/表示を速くする。
/// 圧縮に失敗、または逆に大きくなった場合は元の画像をそのまま返す。
Future<Uint8List> _compressReceipt(Uint8List src) async {
  try {
    final out = await FlutterImageCompress.compressWithList(
      src,
      quality: 70,
      minWidth: 1080,
      minHeight: 1920,
      format: CompressFormat.jpeg,
    );
    if (out.isNotEmpty && out.length < src.length) {
      return Uint8List.fromList(out);
    }
  } catch (_) {/* 圧縮失敗時は元画像を使う */}
  return src;
}
