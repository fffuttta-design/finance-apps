import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../screens/receipt_edit_screen.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 長押し／⋮メニューの結果。
/// - changed … データを変更した（一覧を再読み込みしてほしい）
/// - none    … 何もしなかった
enum ReceiptActionResult { changed, none }

/// 「まとめレシート（同じ receiptId の品目が複数）」の⋮／長押しメニュー。
/// 「レシートを編集」（1画面でまとめて編集）／「レシートを削除」を出す。
Future<ReceiptActionResult> showReceiptActionsSheet(
    BuildContext context, List<core.Transaction> members) async {
  if (members.isEmpty) return ReceiptActionResult.none;
  final total = members.fold<int>(0, (s, t) => s + t.amount);
  final store = members
      .map((t) => t.store?.trim() ?? '')
      .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');

  final action = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.pinkSoft,
                      borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: AppColors.pinkDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      Text('🧾 ${members.length}件まとめ・合計 ${formatYen(total)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppColors.pinkDark),
            title: const Text('レシートを編集',
                style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded,
                color: AppColors.expense),
            title: Text('レシートを削除（${members.length}件すべて）',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.expense)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted) return ReceiptActionResult.none;
  switch (action) {
    case 'edit':
      final c = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ReceiptEditScreen(members: members)),
      );
      return c == true ? ReceiptActionResult.changed : ReceiptActionResult.none;
    case 'delete':
      final c = await _confirmDeleteReceipt(context, members);
      return c ? ReceiptActionResult.changed : ReceiptActionResult.none;
    default:
      return ReceiptActionResult.none;
  }
}

/// レシートを丸ごと削除する確認 → 削除。
Future<bool> _confirmDeleteReceipt(
    BuildContext context, List<core.Transaction> members) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('このレシートを削除しますか？'),
      content: Text('品目 ${members.length}件をまとめて削除します。\nこの操作は取り消せません。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('やめる')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('削除する'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final hid = HouseholdService.instance.householdId;
  final uid = AuthService.instance.currentUser?.uid ?? '';
  if (hid == null) return false;
  for (final m in members) {
    await TxRepository.instance.delete(hid, m.id, uid);
  }
  return true;
}
