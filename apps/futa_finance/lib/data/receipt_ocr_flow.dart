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

/// 読み取り後、確認ダイアログを挟まず直接 入力ポップアップへ。
/// ポップアップ上部のトグル（まとめて1件 / 品目ごと）でその場で切替できる。
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
  // 品目が2件以上あれば既定で「品目ごと」を開く（無ければ単発）。
  var perItem = hasItems;

  while (true) {
    if (!context.mounted) return false;
    final Object? res;
    if (perItem) {
      res = await showInputSheet<Object>(
        context,
        ReceiptSplitScreen(
          items: r.items!,
          date: r.date,
          storeName: r.storeName,
          initialCategoryMajor: r.categoryGuess,
          showModeToggle: true,
        ),
      );
    } else {
      res = await showInputSheet<Object>(
        context,
        ExpenseInputScreen(
          initialAmount: r.amount,
          initialDate: r.date,
          initialDescription: r.storeName,
          initialStore: r.storeName,
          initialCategoryMajor: r.categoryGuess,
          initialMemo: _itemsMemo(r),
          // 品目が2件以上ある時だけトグルを出す。
          receiptItems: hasItems ? r.items : null,
        ),
      );
    }
    // トグルで反対モードへ切替 → ループしてもう片方を開く。
    if (res == kReceiptSwitchMode) {
      perItem = !perItem;
      continue;
    }
    return res == true;
  }
}
