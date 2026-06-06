import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/receipt_ocr.dart';
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

  // 品目が2件以上なら「まとめて1件」か「品目ごと」を選べる。
  if (result.items.length >= 2) {
    final mode = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('品目が${result!.items.length}件 見つかりました'),
        content: const Text('どうやって記録しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, 'single'),
            child: const Text('まとめて1件'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, 'split'),
            child: const Text('品目ごと'),
          ),
        ],
      ),
    );
    if (mode == null || !context.mounted) return false;
    if (mode == 'split') {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptSplitScreen(result: result!),
        ),
      );
      return changed == true;
    }
  }

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
      ),
    ),
  );
  return changed == true;
}
