import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import 'formatters.dart';

/// 同じ種別・同じ日付・同じ金額の既存取引があれば確認ダイアログを出す。
///
/// - 重複なし → true（そのまま保存してよい）
/// - 重複あり＋「追加する」 → true / 「やめる」 → false
///
/// 既存データには Discord 秘書が登録した分も含まれる（同じ Firestore の
/// 取引コレクションを見るため）。手動追加・秘書追加どちらの重複も検知できる。
Future<bool> confirmIfDuplicateTransaction(
  BuildContext context,
  core.Transaction candidate,
) async {
  List<core.Transaction> all;
  try {
    // 通常はキャッシュ即返し。冷えていて通信が遅いときも保存を止めないよう保険。
    all = await TransactionRepository.instance
        .loadAll()
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    return true; // 既存取得に失敗/タイムアウトしたら邪魔せず通す
  }

  final dups = all
      .where((t) =>
          t.id != candidate.id &&
          t.type == candidate.type &&
          t.amount == candidate.amount &&
          t.date.year == candidate.date.year &&
          t.date.month == candidate.date.month &&
          t.date.day == candidate.date.day)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  if (dups.isEmpty) return true;
  if (!context.mounted) return true;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.copy_all_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 8),
          Expanded(child: Text('似たデータがあります')),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同じ日付・同じ金額のデータが、すでに ${dups.length} 件登録されています。'
              'このまま追加してよろしいですか？',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            ...dups.take(5).map(_dupRow),
            if (dups.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('…ほか ${dups.length - 5} 件',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF94A3B8))),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('追加する'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 重複候補1件の明細カード（日付・金額・カテゴリ・店舗/内容・支払方法）。
Widget _dupRow(core.Transaction t) {
  final isIncome = t.type == core.TransactionType.income;
  final sign = isIncome ? '+' : '-';
  final parts = <String>[
    '${t.category.major}・${t.category.sub}',
    if ((t.store ?? '').trim().isNotEmpty) t.store!.trim(),
    if (t.description.trim().isNotEmpty) t.description.trim(),
    if (t.paymentMethod.trim().isNotEmpty) t.paymentMethod.trim(),
  ];
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(formatMonthDay(t.date),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$sign${formatYen(t.amount)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isIncome
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626))),
          ],
        ),
        const SizedBox(height: 2),
        Text(parts.join(' / '),
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
      ],
    ),
  );
}
