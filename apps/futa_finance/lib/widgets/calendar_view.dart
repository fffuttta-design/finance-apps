import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// カレンダーグリッド + 月計サマリ。
/// 元々 CalendarScreen だった内容を Scaffold無しの再利用可能ウィジェット化したもの。
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _repo = TransactionRepository.instance;
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
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
    if (!mounted) return;
    setState(() => _transactions = list);
  }

  void _prevMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month - 1));
  }

  void _nextMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month + 1));
  }

  List<core.Transaction> get _currentMonthTxns => _transactions
      .where((t) =>
          t.date.year == _focused.year && t.date.month == _focused.month)
      .toList();

  Map<int, List<core.Transaction>> get _byDay {
    final map = <int, List<core.Transaction>>{};
    for (final t in _currentMonthTxns) {
      map.putIfAbsent(t.date.day, () => []).add(t);
    }
    return map;
  }

  int _dayIncome(int day) =>
      _byDay[day]
          ?.where((t) => t.type == core.TransactionType.income)
          .fold(0, (s, t) => s! + t.amount) ??
      0;

  int _dayExpense(int day) =>
      _byDay[day]
          ?.where((t) => t.type == core.TransactionType.expense)
          .fold(0, (s, t) => s! + t.amount) ??
      0;

  void _showDay(int day) {
    final txns = _byDay[day] ?? [];
    if (txns.isEmpty) return;
    final date = DateTime(_focused.year, _focused.month, day);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text(
              '${date.year}年${date.month}月${date.day}日（${weekdayKanji(date)}）',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: txns.length,
                itemBuilder: (_, i) => _txnRow(txns[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _weekdaysRow(),
        _grid(),
        _monthSummary(),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left, color: Color(0xFF1A237E)),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${_focused.year}年${_focused.month}月',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
              ),
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

  Widget _weekdaysRow() {
    const labels = ['日', '月', '火', '水', '木', '金', '土'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: List.generate(7, (i) {
          final color = i == 0
              ? const Color(0xFFDC2626)
              : i == 6
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF6B7280);
          return Expanded(
            child: Center(
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ),
          );
        }),
      ),
    );
  }

  Widget _grid() {
    final firstDay = DateTime(_focused.year, _focused.month, 1);
    final daysInMonth =
        DateTime(_focused.year, _focused.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday % 7;
    final totalCells = ((leadingBlanks + daysInMonth) / 7).ceil() * 7;
    final today = DateTime.now();
    final isCurrentMonth =
        today.year == _focused.year && today.month == _focused.month;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.75,
      ),
      itemCount: totalCells,
      itemBuilder: (context, i) {
        final day = i - leadingBlanks + 1;
        if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
        final txns = _byDay[day] ?? [];
        final isToday = isCurrentMonth && today.day == day;
        return _dayCell(day, txns, isToday);
      },
    );
  }

  Widget _dayCell(int day, List<core.Transaction> txns, bool isToday) {
    final expense = _dayExpense(day);
    final income = _dayIncome(day);
    final hasData = txns.isNotEmpty;
    final dayOfWeek =
        DateTime(_focused.year, _focused.month, day).weekday % 7;
    final dayColor = dayOfWeek == 0
        ? const Color(0xFFDC2626)
        : dayOfWeek == 6
            ? const Color(0xFF3B82F6)
            : const Color(0xFF111827);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: hasData ? () => _showDay(day) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isToday
                ? const Color(0xFF1A237E)
                : const Color(0xFFE5E7EB),
            width: isToday ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('$day',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isToday ? FontWeight.bold : FontWeight.w500,
                    color: dayColor)),
            if (hasData) ...[
              const SizedBox(height: 2),
              if (income > 0)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('+${_compactYen(income)}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                          fontFamily: 'monospace')),
                ),
              if (expense > 0)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('-${_compactYen(expense)}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                          fontFamily: 'monospace')),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthSummary() {
    final monthTxns = _currentMonthTxns;
    final income = monthTxns
        .where((t) => t.type == core.TransactionType.income)
        .fold(0, (s, t) => s + t.amount);
    final expense = monthTxns
        .where((t) => t.type == core.TransactionType.expense)
        .fold(0, (s, t) => s + t.amount);
    final net = income - expense;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child:
                _sumBlock('収入', formatYen(income), const Color(0xFF16A34A)),
          ),
          Expanded(
            child: _sumBlock(
                '支出', formatYen(-expense), const Color(0xFFDC2626)),
          ),
          Expanded(
            child: _sumBlock('差引', formatYen(net),
                net >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  Widget _sumBlock(String label, String value, Color color) => Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'monospace')),
        ],
      );

  Widget _txnRow(core.Transaction t) {
    final isIncome = t.type == core.TransactionType.income;
    final color = isIncome ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color:
                  isIncome ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                color: color,
                size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${t.category.major} · ${t.paymentMethod}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            isIncome
                ? formatYen(t.amount, withSign: true)
                : formatYen(-t.amount, withSign: true),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  String _compactYen(int amount) {
    if (amount.abs() < 10000) {
      return amount.abs().toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
    }
    final man = amount.abs() / 10000;
    if (man == man.roundToDouble()) {
      return '${man.toInt()}万';
    }
    return '${man.toStringAsFixed(1)}万';
  }
}
