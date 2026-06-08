import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/receipt_ocr.dart';
import '../data/tx_repository.dart';
import 'add_transaction_screen.dart';
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

  // ★ Drive保存は“完全に裏で”実行（ユーザーは一切待たない）。
  //   撮影直後に開始し、完了したら その receiptId の取引へ画像URLを後付けする。
  //   - 保存より先にアップロード完了 → urlForキャッシュ経由で保存時に付与
  //   - アップロードより先に保存 → attachReceiptUrl で後から付与
  final receiptId = DateTime.now().microsecondsSinceEpoch.toString();
  final hidForUpload = HouseholdService.instance.householdId;
  unawaited(() async {
    final url = await DriveReceiptService.instance
        .uploadReceiptImage(bytes: bytes, date: DateTime.now());
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
    result = await ReceiptOcr.instance.recognize(bytes, mime: mime);
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

  // 品目が2件以上 → ダイアログを挟まず、まず「品目ごと」を全部表示。
  // 画面上部のトグルで「まとめて1件」に切り替えられる（FutaFinance方式）。
  if (result.items.length >= 2) {
    var perItem = true; // 既定は品目ごと
    while (true) {
      if (!context.mounted) return false;
      final Object? res;
      if (perItem) {
        res = await Navigator.push<Object>(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptSplitScreen(
              result: result!,
              receiptId: receiptId,
              showModeToggle: true,
            ),
          ),
        );
      } else {
        res = await Navigator.push<Object>(
          context,
          MaterialPageRoute(
            builder: (_) => AddTransactionScreen(
              initialType: core.TransactionType.expense,
              initialAmount: result!.amount,
              initialDate: result.date,
              initialCategory: result.category,
              initialDescription: result.store,
              initialReceiptId: receiptId,
              receiptItems: result.items,
            ),
          ),
        );
      }
      // トグルで反対モードへ → ループして開き直す。
      if (res == kReceiptSwitchMode) {
        perItem = !perItem;
        continue;
      }
      return res == true;
    }
  }

  // 品目0〜1件 → まとめて1件（トグルなし）。
  if (!context.mounted) return false;
  final changed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => AddTransactionScreen(
        initialType: core.TransactionType.expense,
        initialAmount: result!.amount,
        initialDate: result.date,
        initialCategory: result.category,
        initialDescription: result.store,
        initialReceiptId: receiptId,
      ),
    ),
  );
  return changed == true;
}
