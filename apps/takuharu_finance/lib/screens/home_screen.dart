import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';
import 'settings_screen.dart';

/// ホーム：月次サマリー＋カテゴリ内訳＋取引一覧（可愛い系）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  bool _inMonth(core.Transaction t) =>
      t.date.year == _month.year && t.date.month == _month.month;

  Future<void> _openAdd([core.Transaction? editing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AddTransactionScreen(editing: editing)),
    );
    if (changed == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('たくはるファイナンス'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.favorite_rounded, color: AppColors.pink),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('きろく',
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
                final month = all.where(_inMonth).toList();
                return _body(month);
              },
            ),
    );
  }

  Widget _body(List<core.Transaction> month) {
    final income = month
        .where((t) => t.type == core.TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = month
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    // カテゴリ別（支出）集計。
    final byCat = <String, int>{};
    for (final t in month) {
      if (t.type != core.TransactionType.expense) continue;
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
    }
    final catEntries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _monthBar(),
        const SizedBox(height: 12),
        _summaryCard(income, expense),
        const SizedBox(height: 16),
        if (catEntries.isNotEmpty) ...[
          _sectionTitle('支出の内訳'),
          const SizedBox(height: 8),
          _categoryCard(catEntries, expense),
          const SizedBox(height: 16),
        ],
        _sectionTitle('記録'),
        const SizedBox(height: 8),
        if (month.isEmpty)
          _empty()
        else
          ...month.map(_txTile),
      ],
    );
  }

  Widget _monthBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _shift(-1),
        ),
        Text('${_month.year}年 ${_month.month}月',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => _shift(1),
        ),
      ],
    );
  }

  Widget _summaryCard(int income, int expense) {
    final balance = income - expense;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8FA8), Color(0xFFFF6B8A)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.pink.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('今月の収支',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            formatYen(balance),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStat('収入', income, Icons.south_west_rounded),
              ),
              Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.3)),
              Expanded(
                child: _miniStat('支出', expense, Icons.north_east_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        Text(formatYen(value),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _categoryCard(List<MapEntry<String, int>> entries, int total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final e in entries.take(6)) _catBar(e.key, e.value, total),
          ],
        ),
      ),
    );
  }

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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(c.icon, size: 17, color: c.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Text(formatYen(amount),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
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

  Widget _txTile(core.Transaction t) {
    final income = t.type == core.TransactionType.income;
    final c = categoryFor(t.category.major, income: income);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () => _openAdd(t),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: c.color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(c.icon, color: c.color),
        ),
        title: Text(
          t.description.isEmpty ? t.category.major : t.description,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('${t.date.month}/${t.date.day}　${t.category.major}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing: Text(
          '${income ? '+' : '-'}${formatYen(t.amount)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: income ? AppColors.income : AppColors.expense,
          ),
        ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.favorite_border_rounded,
                size: 48, color: Color(0xFFF3C6D2)),
            const SizedBox(height: 10),
            Text('${_month.month}月の記録はまだないよ',
                style: const TextStyle(
                    color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('右下の「きろく」から追加してね ♡',
                style: TextStyle(color: AppColors.textSub, fontSize: 11)),
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
