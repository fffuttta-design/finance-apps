import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import 'receipt_flow.dart';

/// 「きろく」共通メニュー（手で入力 / レシートで記録）。中央ダイアログ。
/// 何か記録できたら true を返す。ホームと支出タブで共用。
Future<bool> showRecordMenu(BuildContext context) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text('どうやって記録する？ ♡',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.pinkSoft,
                child: Icon(Icons.receipt_long_rounded, color: AppColors.pink),
              ),
              title: const Text('レシートで記録',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('写真を撮って自動で読み取り'),
              onTap: () => Navigator.pop(ctx, 'receipt'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.pinkSoft,
                child: Icon(Icons.edit_rounded, color: AppColors.pink),
              ),
              title: const Text('手で入力',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('支出・収入をその場で入力'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice == 'manual') {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
    );
    return changed == true;
  } else if (choice == 'receipt') {
    return runReceiptFlow(context);
  }
  return false;
}
