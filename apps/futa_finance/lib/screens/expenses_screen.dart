import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../mock/mock_data.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';
import '../widgets/annual_contracts_card.dart';

/// 支出タブ。月送り、年間払い契約、カテゴリ別の支出一覧（折りたたみ式）。
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _repo = TransactionRepository.instance;
  final _settings = SettingsRepository();
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.CategoryConfig? _categoryConfig;
  DateTime _focused = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _repo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _repo.loadAll();
    final cfg = await _settings.loadCategories();
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _categoryConfig = cfg;
    });
  }

  /// 大カテゴリ表示名 → アイコン
  IconData _iconFor(String majorDisplayName) {
    final cfg = _categoryConfig;
    if (cfg == null) return Icons.folder_outlined;
    for (int i = 0; i < cfg.majors.length; i++) {
      if (cfg.majors[i].displayName(i) == majorDisplayName) {
        return iconForKey(cfg.majors[i].iconKey);
      }
    }
    return Icons.folder_outlined;
  }

  void _prevMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month - 1));
  }

  void _nextMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month + 1));
  }

  /// 表示中月の支出のみ。
  List<core.Transaction> get _monthExpenses => _transactions
      .where((t) =>
          t.type == core.TransactionType.expense &&
          t.date.year == _focused.year &&
          t.date.month == _focused.month)
      .toList();

  /// 大カテゴリ → その月の取引リスト（金額降順）。
  Map<String, List<core.Transaction>> get _byMajor {
    final map = <String, List<core.Transaction>>{};
    for (final t in _monthExpenses) {
      map.putIfAbsent(t.category.major, () => []).add(t);
    }
    // 各カテゴリ内を金額降順に
    for (final list in map.values) {
      list.sort((a, b) => b.amount.compareTo(a.amount));
    }
    return map;
  }

  /// カテゴリ別合計（降順ソート用）。
  List<MapEntry<String, int>> get _majorTotalsSorted {
    final totals = <String, int>{};
    for (final t in _monthExpenses) {
      totals[t.category.major] = (totals[t.category.major] ?? 0) + t.amount;
    }
    return totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  @override
  Widget build(BuildContext context) {
    final monthExpenses = _monthExpenses;
    final totalAmount =
        monthExpenses.fold<int>(0, (s, t) => s + t.amount);
    final byMajor = _byMajor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('支出',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _monthHeader(monthExpenses.length, totalAmount),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  // 年間払い契約（ホームから移管）
                  AnnualContractsCard(
                    contracts: MockData.annualContracts,
                    today: DateTime.now(),
                  ),
                  const SizedBox(height: 12),
                  if (monthExpenses.isEmpty)
                    _empty()
                  else
                    ..._majorTotalsSorted
                        .map((e) => _categorySection(e.key, e.value, byMajor[e.key]!)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthHeader(int count, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left, color: Color(0xFF1A237E)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_focused.year}年${_focused.month}月',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827)),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$count件',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                    const SizedBox(width: 12),
                    Text('合計 ${formatYen(-total, withSign: true)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDC2626),
                            fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right, color: Color(0xFF1A237E)),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inbox_outlined, size: 64, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('この月は支出記録なし',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ],
        ),
      );

  Widget _categorySection(
      String major, int total, List<core.Transaction> txns) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          leading: Icon(_iconFor(major),
              color: const Color(0xFF1A237E), size: 20),
          title: Text(major,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827))),
          subtitle: Text('${txns.length}件',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF9CA3AF))),
          trailing: Text(
            formatYen(total),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
                fontFamily: 'monospace'),
          ),
          children: txns
              .map((t) => _txnRow(t))
              .toList(),
        ),
      ),
    );
  }

  Widget _txnRow(core.Transaction t) {
    final hasUsd = t.originalCurrency == 'USD' && t.originalAmount != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 14, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              formatMonthDay(t.date),
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF111827)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  '${t.category.sub.isEmpty ? "未分類" : t.category.sub} · ${t.paymentMethod}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatYen(-t.amount, withSign: true),
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFDC2626),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600),
              ),
              if (hasUsd)
                Text(
                  '\$${t.originalAmount!.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'monospace'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
