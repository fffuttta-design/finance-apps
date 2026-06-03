import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/expense_input_screen.dart';
import '../screens/receipt_split_screen.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import 'receipt_ocr.dart';
import 'receipt_ocr_cloud.dart';

/// レシートOCRの一連の流れ（撮影/選択 → クラウド解析 → 記録方法選択 → 入力）。
///
/// 「+ 記録」メニューや支出画面から呼び出す正式な導線。
/// 何か記録できたら true を返す。
Future<bool> runReceiptOcrFlow(BuildContext context) async {
  if (!ReceiptOcrCloud.available) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('レシート読み取りはAndroidアプリでご利用ください')),
    );
    return false;
  }

  // 取得元（カメラ/ギャラリー）を選択。
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('カメラで撮影'),
            onTap: () => Navigator.pop(sheet, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('ギャラリーから選択'),
            onTap: () => Navigator.pop(sheet, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return false;

  // 読取中インジケータ。
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

  ReceiptOcrResult? result;
  String? error;
  try {
    result =
        await ReceiptOcrCloud.instance.captureAndRecognize(source: source);
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop(); // インジケータを閉じる

  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('読取に失敗しました: $error')),
    );
    return false;
  }
  if (result == null) return false; // キャンセル

  return _showOcrResult(context, result);
}

/// 単発記録時に備考へ入れる明細テキスト（・品名 ¥金額）。
String? _itemsMemo(ReceiptOcrResult r) {
  final items = r.items;
  if (items != null && items.isNotEmpty) {
    return items.map((it) => '・${it.name} ${formatYen(it.price)}').join('\n');
  }
  return r.memo;
}

/// 読み取り結果を確認し、記録方法（単発 / 品目ごと）を選ばせて入力画面へ。
Future<bool> _showOcrResult(BuildContext context, ReceiptOcrResult r) async {
  final nothing = r.amount == null &&
      (r.storeName == null || r.storeName!.trim().isEmpty);
  if (nothing) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('うまく読み取れませんでした。フォームで手入力してください')),
    );
  }

  final hasItems = r.items != null && r.items!.length >= 2;

  // 合計額を必ず表示し、その場で記録方法を選べるダイアログ。
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('読み取り結果'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.storeName != null && r.storeName!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('店名: ${r.storeName!.trim()}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF374151))),
            ),
          if (r.date != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                  '日付: ${r.date!.year}/${r.date!.month}/${r.date!.day}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF374151))),
            ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('合計 ',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              Text(
                r.amount != null ? formatYen(r.amount!) : '—',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          if (hasItems) ...[
            const SizedBox(height: 8),
            Text('品目 ${r.items!.length}件を読み取りました',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ],
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('キャンセル')),
        if (hasItems)
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'each'),
              child: const Text('品目ごとに記録')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'single'),
            child: const Text('単発で記録')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;

  final changed = choice == 'each'
      ? await showInputSheet<bool>(
          context,
          ReceiptSplitScreen(
            items: r.items!,
            date: r.date,
            storeName: r.storeName,
          ),
        )
      : await showInputSheet<bool>(
          context,
          ExpenseInputScreen(
            initialAmount: r.amount,
            initialDate: r.date,
            initialDescription: r.storeName,
            initialMemo: _itemsMemo(r),
          ),
        );
  return changed == true;
}
