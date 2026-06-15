import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/receipt_group.dart';
import 'add_transaction_screen.dart';

/// 収支カレンダー：日ごとの支出/収入をカレンダー表示。日タップで明細。
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected;

  void _shift(int d) => setState(() {
        _month = DateTime(_month.year, _month.month + d);
        _selected = null;
      });

  Future<void> _edit(core.Transaction t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionScreen(editing: t)),
    );
    if (changed == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(title: const Text('カレンダー')),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<core.Transaction>>(
              stream: TxRepository.instance.watch(hid),
              builder: (context, snap) {
                final all = snap.data ?? const <core.Transaction>[];
                final month = all
                    .where((t) =>
                        t.date.year == _month.year &&
                        t.date.month == _month.month)
                    .toList();
                // 日 → 支出/収入
                final exp = <int, int>{};
                final inc = <int, int>{};
                for (final t in month) {
                  if (t.type == core.TransactionType.expense) {
                    exp[t.date.day] = (exp[t.date.day] ?? 0) + t.amount;
                  } else if (t.type == core.TransactionType.income) {
                    inc[t.date.day] = (inc[t.date.day] ?? 0) + t.amount;
                  }
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    _monthBar(),
                    const SizedBox(height: 8),
                    _grid(exp, inc),
                    const SizedBox(height: 16),
                    if (_selected != null) _dayDetail(month),
                  ],
                );
              },
            ),
    );
  }

  Widget _monthBar() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _shift(-1)),
          Text('${_month.year}年 ${_month.month}月',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _shift(1)),
        ],
      );

  Widget _grid(Map<int, int> exp, Map<int, int> inc) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7; // 日曜=0
    final cells = <Widget>[];
    const wd = ['日', '月', '火', '水', '木', '金', '土'];
    for (var i = 0; i < 7; i++) {
      cells.add(Center(
        child: Text(wd[i],
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: i == 0
                    ? AppColors.expense
                    : (i == 6 ? AppColors.income : AppColors.textSub))),
      ));
    }
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(_dayCell(d, exp[d], inc[d]));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.62,
      children: cells,
    );
  }

  Widget _dayCell(int day, int? exp, int? inc) {
    final isSel = _selected?.day == day;
    final isToday = DateTime.now().year == _month.year &&
        DateTime.now().month == _month.month &&
        DateTime.now().day == day;
    return GestureDetector(
      onTap: () => setState(
          () => _selected = DateTime(_month.year, _month.month, day)),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSel ? AppColors.pinkSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: AppColors.pink, width: 1.4)
              : null,
        ),
        child: Column(
          children: [
            const SizedBox(height: 4),
            Text('$day',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            if (exp != null)
              Text('-${_short(exp)}',
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.expense)),
            if (inc != null)
              Text('+${_short(inc)}',
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.income)),
          ],
        ),
      ),
    );
  }

  String _short(int v) {
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(v % 10000 == 0 ? 0 : 1)}万';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}千';
    return '$v';
  }

  Widget _dayDetail(List<core.Transaction> month) {
    final sel = _selected!;
    final items = month.where((t) => t.date.day == sel.day).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('${sel.month}月${sel.day}日の記録',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: Text('記録なし',
                    style:
                        TextStyle(color: AppColors.textSub, fontSize: 13))),
          )
        else
          // レシートの品目は1レシート＝親1行にまとめて表示（タップで品目展開）。
          ...groupByReceipt(items).map((g) => g.isGroup
              ? ReceiptGroupTile(members: g.members, childTileBuilder: _tile)
              : _tile(g.single!)),
      ],
    );
  }

  Widget _tile(core.Transaction t) {
    final income = t.type == core.TransactionType.income;
    final c = categoryFor(t.category.major, income: income);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _edit(t),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(c.icon, color: c.color, size: 20),
        ),
        title: Text(t.description.isEmpty ? t.category.major : t.description,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle:
            Text(t.category.major, style: const TextStyle(fontSize: 11)),
        trailing: Text('${income ? '+' : '-'}${formatYen(t.amount)}',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: income ? AppColors.income : AppColors.expense)),
      ),
    );
  }
}
