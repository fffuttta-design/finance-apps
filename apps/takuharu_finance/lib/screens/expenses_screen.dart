import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';

/// 支出タブ：月切替＋支出合計＋カテゴリ内訳＋支出一覧（可愛い系）。
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  bool _inMonth(core.Transaction t) =>
      t.date.year == _month.year && t.date.month == _month.month;

  Future<void> _openAdd([core.Transaction? editing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          editing: editing,
          initialType: core.TransactionType.expense,
        ),
      ),
    );
    if (changed == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('支出'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.shopping_bag_rounded, color: AppColors.expense),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(),
        backgroundColor: AppColors.expense,
        icon: const Icon(Icons.add_rounded),
        label: const Text('支出をきろく',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<core.Transaction>>(
              stream: TxRepository.instance.watch(hid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? const <core.Transaction>[];
                final month = all
                    .where((t) => t.type == core.TransactionType.expense)
                    .where(_inMonth)
                    .toList()
                  ..sort((a, b) => b.date.compareTo(a.date));
                return _body(month);
              },
            ),
    );
  }

  Widget _body(List<core.Transaction> month) {
    final total = month.fold<int>(0, (s, t) => s + t.amount);
    final byCat = <String, int>{};
    for (final t in month) {
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
    }
    final cats = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _monthBar(),
        const SizedBox(height: 12),
        _totalCard(total, month.length),
        const SizedBox(height: 16),
        if (cats.isNotEmpty) ...[
          _sectionTitle('カテゴリ内訳'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [for (final e in cats) _catBar(e.key, e.value, total)],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _sectionTitle('支出の記録'),
        const SizedBox(height: 8),
        if (month.isEmpty) _empty() else ...month.map(_tile),
      ],
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

  Widget _totalCard(int total, int count) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF9AA2), Color(0xFFFF6B6B)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppColors.expense.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            const Text('今月の支出',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text('-${formatYen(total)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('$count件',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  Widget _catBar(String name, int amount, int total) {
    final c = categoryFor(name, income: false);
    final ratio = total == 0 ? 0.0 : amount / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(c.icon, size: 17, color: c.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Text(formatYen(amount),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppColors.pinkSoft,
              valueColor: AlwaysStoppedAnimation(c.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(core.Transaction t) {
    final c = categoryFor(t.category.major, income: false);
    final names = HouseholdService.instance.memberNames;
    final payerUid = t.paidBy ?? t.recordedBy;
    final payer = (names.length >= 2 && payerUid != null)
        ? names[payerUid]
        : null;
    final sub = '${t.date.month}/${t.date.day}　${t.category.major}'
        '${payer != null ? '　💳 $payer' : ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () => _openAdd(t),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(c.icon, color: c.color),
        ),
        title: Text(t.description.isEmpty ? t.category.major : t.description,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(sub,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing: Text('-${formatYen(t.amount)}',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.expense)),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.shopping_bag_outlined,
                size: 48, color: Color(0xFFF3C6D2)),
            const SizedBox(height: 10),
            Text('${_month.month}月の支出はまだないよ',
                style: const TextStyle(color: AppColors.textSub, fontSize: 13)),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      );
}
