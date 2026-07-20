import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/household_service.dart';
import '../data/receipt_comment_repository.dart';
import '../screens/receipt_detail_screen.dart';
import '../screens/transaction_chat_screen.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 取引リストを「レシート(receiptId)単位」でまとめるためのエントリ。
/// - [single] != null … 単独取引（まとめ対象でない）
/// - [single] == null … 同じ receiptId が2件以上ある“まとめ”（[members] が品目）
class TxGroup {
  final core.Transaction? single;
  final String? receiptId;
  final List<core.Transaction> members;

  const TxGroup.single(core.Transaction t)
      : single = t,
        receiptId = null,
        members = const [];

  const TxGroup.group(this.receiptId, this.members) : single = null;

  bool get isGroup => single == null;
}

/// 同じ receiptId が2件以上ある取引を1グループにまとめる。
/// 入力リストの並び順は保持し、各レシートは最初に現れた位置に1行で置く。
List<TxGroup> groupByReceipt(List<core.Transaction> rows) {
  final counts = <String, int>{};
  for (final t in rows) {
    final rid = t.receiptId;
    if (rid != null && rid.isNotEmpty) {
      counts[rid] = (counts[rid] ?? 0) + 1;
    }
  }
  final out = <TxGroup>[];
  final seen = <String>{};
  for (final t in rows) {
    final rid = t.receiptId;
    if (rid != null && rid.isNotEmpty && (counts[rid] ?? 0) >= 2) {
      if (seen.add(rid)) {
        out.add(TxGroup.group(
            rid, rows.where((x) => x.receiptId == rid).toList()));
      }
    } else {
      out.add(TxGroup.single(t));
    }
  }
  return out;
}

/// カテゴリ内訳を展開したときの明細リスト（ホーム／支出タブ共通）。
/// 同じレシートの品目は**1レシート＝1行**にまとめ、そのカテゴリ分の合計を出す。
/// タップでレシート詳細（品目全部）／単品は明細チャットへ。
class ReceiptGroupedDetailList extends StatelessWidget {
  /// このカテゴリに属する取引（表示対象）。
  final List<core.Transaction> txns;

  /// レシートの品目を全部引くための母集合（月の全取引など）。
  /// 別カテゴリの品目も含めて「1レシート」を判定するために使う。
  final List<core.Transaction> allTxns;

  final VoidCallback? onChanged;

  const ReceiptGroupedDetailList({
    super.key,
    required this.txns,
    required this.allTxns,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final seen = <String>{};
    for (final t in txns) {
      final rid = t.receiptId;
      final full = (rid == null || rid.isEmpty)
          ? const <core.Transaction>[]
          : allTxns.where((x) => x.receiptId == rid).toList();
      if (full.length >= 2) {
        if (!seen.add(rid!)) continue; // 同じレシートは1行だけ
        final inCat = txns.where((x) => x.receiptId == rid).toList();
        rows.add(_receiptRow(context, full, inCat));
      } else {
        rows.add(_txRow(context, t));
      }
    }
    return Column(children: rows);
  }

  /// レシート1行（店名＋🧾件数／このカテゴリ分の合計）。
  Widget _receiptRow(BuildContext context, List<core.Transaction> full,
      List<core.Transaction> inCat) {
    final first = inCat.first;
    final sum = inCat.fold<int>(0, (s, t) => s + t.amount);
    final store = full
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');
    return _row(
      context: context,
      date: first.date,
      amount: sum,
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => ReceiptDetailScreen(members: full)),
        );
        if (changed == true) onChanged?.call();
      },
      label: Row(
        children: [
          // 「◯件」でレシートまとめ行と分かるので、先頭アイコンは付けない。
          Flexible(
            child: Text(store,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Text('${inCat.length}件',
              style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        ],
      ),
    );
  }

  /// 単品の取引1行。
  Widget _txRow(BuildContext context, core.Transaction t) {
    return _row(
      context: context,
      date: t.date,
      amount: t.amount,
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionChatScreen(transaction: t)),
        );
        if (changed == true) onChanged?.call();
      },
      label: Text(t.description.isEmpty ? t.category.major : t.description,
          style: const TextStyle(fontSize: 12, color: AppColors.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _row({
    required BuildContext context,
    required DateTime date,
    required int amount,
    required VoidCallback onTap,
    required Widget label,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text('${date.month}/${date.day}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
            Expanded(child: label),
            const SizedBox(width: 6),
            Text(formatYen(amount),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }
}

/// レシートまとめ行（親1行 = 店名・合計・🧾○件）。
/// タップで「レシート詳細画面」（1画面に品目一覧＋まとめ編集＋コメント1本）へ。
class ReceiptGroupTile extends StatelessWidget {
  final List<core.Transaction> members;

  /// まとめて編集／削除でデータが変わったときに呼ばれる（一覧の再読み込み用）。
  final VoidCallback? onChanged;

  const ReceiptGroupTile({
    super.key,
    required this.members,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final first = members.first;
    final total = members.fold<int>(0, (s, t) => s + t.amount);
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');
    // 統合前は品目側の commentCount、統合後はレシート側の commentCount を見る。
    final memberSum = members.fold<int>(0, (s, t) => s + t.commentCount);
    final hid = HouseholdService.instance.householdId;
    final rid = first.receiptId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => ReceiptDetailScreen(members: members)),
          );
          if (changed == true) onChanged?.call();
        },
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: AppColors.pinkSoft,
              borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.receipt_long_rounded,
              color: AppColors.pinkDark),
        ),
        title: Text(store,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
            '${first.date.month}/${first.date.day}　🧾 ${members.length}件まとめ',
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hid != null && rid != null && rid.isNotEmpty)
              StreamBuilder<int>(
                stream:
                    ReceiptCommentRepository.instance.watchCount(hid, rid),
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  final count = n > memberSum ? n : memberSum;
                  return _chatBadge(count);
                },
              )
            else
              _chatBadge(memberSum),
            Text('-${formatYen(total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.expense)),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }

  /// コメントが付いているレシートに💬バッジ（件数）。0件のときは何も出さない。
  Widget _chatBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.pinkSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_rounded,
              size: 12, color: AppColors.pinkDark),
          const SizedBox(width: 3),
          Text('$count',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.pinkDark)),
        ],
      ),
    );
  }
}
