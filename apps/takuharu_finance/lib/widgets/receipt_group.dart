import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'receipt_actions.dart';

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

/// レシートまとめ行（親1行 = 店名・合計・🧾○件 → タップで子品目を展開）。
/// 子品目の見た目は画面ごとに違うので、[childTileBuilder] で各画面の tile を描く。
class ReceiptGroupTile extends StatefulWidget {
  final List<core.Transaction> members;
  final Widget Function(core.Transaction) childTileBuilder;
  final double childIndent;

  /// まとめて編集／削除でデータが変わったときに呼ばれる（一覧の再読み込み用）。
  final VoidCallback? onChanged;

  const ReceiptGroupTile({
    super.key,
    required this.members,
    required this.childTileBuilder,
    this.childIndent = 20,
    this.onChanged,
  });

  @override
  State<ReceiptGroupTile> createState() => _ReceiptGroupTileState();
}

class _ReceiptGroupTileState extends State<ReceiptGroupTile> {
  bool _expanded = false;

  Future<void> _openMenu() async {
    final r = await showReceiptActionsSheet(context, widget.members);
    if (!mounted) return;
    if (r == ReceiptActionResult.changed) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final first = members.first;
    final total = members.fold<int>(0, (s, t) => s + t.amount);
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            onTap: () => setState(() => _expanded = !_expanded),
            onLongPress: _openMenu,
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
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
                '${first.date.month}/${first.date.day}　'
                '🧾 ${members.length}件まとめ',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textSub)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('-${formatYen(total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.expense)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: AppColors.textSub),
                  tooltip: '編集メニュー',
                  onPressed: _openMenu,
                ),
                const SizedBox(width: 2),
                Icon(_expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final t in members)
            Padding(
              padding: EdgeInsets.only(left: widget.childIndent),
              child: widget.childTileBuilder(t),
            ),
      ],
    );
  }
}
