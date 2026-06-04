import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../screens/expense_input_screen.dart';
import '../screens/receipt_camera_screen.dart';
import '../screens/receipt_split_screen.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import 'app_mode.dart';
import 'drive_receipt_service.dart';
import 'receipt_ocr.dart';
import 'receipt_ocr_cloud.dart';
import 'settings_repository.dart';

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

  // 自前カメラ画面を直接起動（中央下=シャッター / 右下=ギャラリー）。
  final bytes = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => const ReceiptCameraScreen()),
  );
  if (bytes == null || !context.mounted) return false;

  // カテゴリ自動予測用に、ユーザーの大→小カテゴリ一覧を用意（Geminiに渡す）。
  Map<String, List<String>>? catMenu;
  try {
    final cfg = await SettingsRepository().loadCategories();
    final m = <String, List<String>>{};
    for (var i = 0; i < cfg.majors.length; i++) {
      final mj = cfg.majors[i];
      if (mj.inactive) continue;
      m[mj.displayName(i)] = mj.subs;
    }
    if (m.isNotEmpty) catMenu = m;
  } catch (_) {}
  if (!context.mounted) return false;

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
    result = await ReceiptOcrCloud.instance
        .recognizeBytes(bytes, categories: catMenu);
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
    return items.map((it) {
      final bd = (it.unitPrice != null &&
              it.quantity != null &&
              it.quantity! > 1)
          ? '（¥${it.unitPrice}×${it.quantity}）'
          : '';
      return '・${it.name} ${formatYen(it.price)}$bd';
    }).join('\n');
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

  // 撮影画像を Google Drive に保存（親レシート）。まとめ1件でも品目ごとでも
  // 同じ receiptId で束ね、receiptUrl から後で画像を開ける。失敗しても続行。
  final receiptId = DateTime.now().microsecondsSinceEpoch.toString();
  String? receiptUrl;
  if (r.imageBytes != null) {
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
          Text('レシート画像を保存中...'),
        ]),
      ),
    );
    receiptUrl = await DriveReceiptService.instance.uploadReceiptImage(
      bytes: r.imageBytes!,
      date: r.date ?? DateTime.now(),
      isBusiness: AppModeManager.instance.current == AppMode.business,
      store: r.storeName,
      amount: r.amount,
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (receiptUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('レシート画像のDrive保存はスキップしました（記録は続行）')),
        );
      }
    }
  }

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
          initialCategoryMajor: r.categoryMajor ?? r.categoryGuess,
          initialCategorySub: r.categorySub,
          showModeToggle: true,
          receiptId: receiptId,
          receiptUrl: receiptUrl,
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
          initialCategoryMajor: r.categoryMajor ?? r.categoryGuess,
          initialCategorySub: r.categorySub,
          initialMemo: _itemsMemo(r),
          // 品目が2件以上ある時だけトグルを出す。
          receiptItems: hasItems ? r.items : null,
          receiptId: receiptId,
          initialReceiptUrl: receiptUrl,
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
