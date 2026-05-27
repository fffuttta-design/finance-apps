import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../widgets/brand_logo.dart';

/// クレジットカード詳細（利用明細）画面。
/// 銀行通帳の AccountDetailScreen に相当するクレカ版。
///
/// 機能:
/// - 月セレクター（取引のある月 + 当月）
/// - サマリー: 当月利用合計（大）/ 件数 / 引落予定日
/// - 利用履歴: その月のカード利用一覧（日付→明細→金額）
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.card});

  final core.RegisteredCreditCard card;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

const double _kContentMaxWidth = 1000;

class _CardDetailScreenState extends State<CardDetailScreen> {
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];
  DateTime? _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _all = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() => _all = list);
  }

  /// このカードに紐づく取引（paymentMethod が一致）。
  List<core.Transaction> _cardTransactions() {
    final name = widget.card.name;
    return _all.where((t) {
      return t.type == core.TransactionType.expense &&
          t.paymentMethod == name;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 月選択肢: 当月 + 取引月（降順）+ 全期間。
  List<DateTime?> _availableMonths() {
    final name = widget.card.name;
    final set = <DateTime>{};
    final now = DateTime.now();
    set.add(DateTime(now.year, now.month));
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.paymentMethod != name) continue;
      set.add(DateTime(t.date.year, t.date.month));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return [null, ...list];
  }

  @override
  Widget build(BuildContext context) {
    final allTxns = _cardTransactions();
    final monthTxns = _selectedMonth == null
        ? allTxns
        : allTxns
            .where((t) =>
                t.date.year == _selectedMonth!.year &&
                t.date.month == _selectedMonth!.month)
            .toList();
    final monthTotal =
        monthTxns.fold<int>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.card.iconUrl != null &&
                widget.card.iconUrl!.isNotEmpty)
              BrandLogo(
                  iconUrl: widget.card.iconUrl,
                  fallbackEmoji: '💳',
                  size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.card.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final content = Column(
            children: [
              _monthSelector(),
              _summaryCard(monthTotal, monthTxns.length),
              const Divider(height: 1),
              Expanded(child: _historyList(monthTxns)),
            ],
          );
          if (constraints.maxWidth >= 900) {
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _kContentMaxWidth,
                height: constraints.maxHeight,
                child: content,
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _monthSelector() {
    final months = _availableMonths();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Text('期間: ',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          DropdownButton<DateTime?>(
            value: _selectedMonth,
            underline: const SizedBox.shrink(),
            items: months.map((m) {
              final label = m == null ? '全期間' : '${m.year}年${m.month}月';
              return DropdownMenuItem<DateTime?>(
                  value: m, child: Text(label));
            }).toList(),
            onChanged: (v) => setState(() => _selectedMonth = v),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int monthTotal, int txnCount) {
    final paymentDay = widget.card.paymentDay;
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // 利用合計（主役）
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                    width: 1.5),
              ),
              child: Column(
                children: [
                  const Text('利用合計',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    formatYen(monthTotal),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 件数 + 引落予定日
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      const Text('件数',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 2),
                      Text('$txnCount 件',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      const Text('引落予定日',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 2),
                      Text(
                          paymentDay == null
                              ? '未設定'
                              : '毎月 $paymentDay 日',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: paymentDay == null
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF1A237E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyList(List<core.Transaction> txns) {
    if (txns.isEmpty) {
      return const Center(
        child: Text('この期間の利用はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    return ListView.separated(
      itemCount: txns.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final t = txns[i];
        return _historyRow(t);
      },
    );
  }

  Widget _historyRow(core.Transaction t) {
    final dateLabel =
        '${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}';
    final yearLabel = '${t.date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          // 日付
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        fontFamily: 'monospace')),
                Text(yearLabel,
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 明細（カテゴリ + 説明）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${t.category.major}${t.category.sub.isNotEmpty ? ' · ${t.category.sub}' : ''}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 金額
          Text(
            '-${formatYen(t.amount)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }
}
