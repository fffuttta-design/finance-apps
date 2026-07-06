import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../utils/formatters.dart';
import '../widgets/centered_body.dart';
import 'transaction_detail_screen.dart';

/// カテゴリ（大 or 小）に紐づく明細の一覧。
/// カテゴリ編集画面の「明細◯件」をタップすると、この画面で中身を確認できる。
/// 各行タップで取引詳細（編集/削除）へ。変更があれば呼び元へ true を返して再読込させる。
class CategoryTxnsScreen extends StatefulWidget {
  final String title;
  final List<core.Transaction> transactions;
  const CategoryTxnsScreen({
    super.key,
    required this.title,
    required this.transactions,
  });

  @override
  State<CategoryTxnsScreen> createState() => _CategoryTxnsScreenState();
}

class _CategoryTxnsScreenState extends State<CategoryTxnsScreen> {
  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];

  Color _accent(core.Transaction t) {
    switch (t.type) {
      case core.TransactionType.income:
        return const Color(0xFF059669);
      case core.TransactionType.transfer:
        return const Color(0xFF6B7280);
      case core.TransactionType.expense:
        return const Color(0xFFDC2626);
    }
  }

  String _signed(core.Transaction t) {
    final y = formatYen(t.amount);
    switch (t.type) {
      case core.TransactionType.income:
        return '+$y';
      case core.TransactionType.transfer:
        return y;
      case core.TransactionType.expense:
        return '-$y';
    }
  }

  Future<void> _open(core.Transaction t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(transaction: t),
      ),
    );
    if (changed == true) {
      // 編集/削除された：呼び元（カテゴリ編集）で件数を取り直せるよう、
      // この画面を閉じて true を返す（一覧は元データのままなので閉じるのが安全）。
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txns = [...widget.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: Text(widget.title)),
      body: CenteredBody(
        maxWidth: 560,
        child: txns.isEmpty
              ? const Center(
                  child: Text('明細がありません',
                      style: TextStyle(color: Color(0xFF9CA3AF))))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: txns.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = txns[i];
                    final wd = _wd[(t.date.weekday - 1) % 7];
                    final hasReimbursed =
                        t.type == core.TransactionType.expense &&
                            (t.reimbursed ?? 0) > 0;
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _open(t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 62,
                                child: Text(
                                  '${t.date.month}/${t.date.day}（$wd）',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t.description.trim().isEmpty
                                          ? t.category.sub.isEmpty
                                              ? t.category.major
                                              : t.category.sub
                                          : t.description,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF111827)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (hasReimbursed) ...[
                                      const SizedBox(height: 3),
                                      Text('立替・実質 ${formatYen(t.effectiveAmount)}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF059669))),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _signed(t),
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _accent(t)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
  }
}
