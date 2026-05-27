import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/income_source_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import 'income_input_screen.dart';

/// 収入タブの表示モード。
enum _IncomeViewMode { list, grouped }

/// リスト表示時の並び順。
enum _IncomeSortMode { dateDesc, amountDesc }

/// 収入タブ。月送り、月計サマリ、リスト/カテゴリ(=収入マスタ)表示切替。
class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _repo = TransactionRepository.instance;
  final _sourceRepo = IncomeSourceRepository.instance;
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.IncomeSourceConfig? _sources;
  DateTime _focused = DateTime(DateTime.now().year, DateTime.now().month);
  _IncomeViewMode _viewMode = _IncomeViewMode.list;
  _IncomeSortMode _sortMode = _IncomeSortMode.dateDesc;

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
    final srcs = await _sourceRepo.load();
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _sources = srcs;
    });
  }

  void _prevMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month - 1));
  }

  void _nextMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month + 1));
  }

  /// 表示中月の収入のみ。
  List<core.Transaction> get _monthIncomes => _transactions
      .where((t) =>
          t.type == core.TransactionType.income &&
          t.date.year == _focused.year &&
          t.date.month == _focused.month)
      .toList();

  /// ソート済みの月次収入。
  List<core.Transaction> get _sortedMonthIncomes {
    final list = [..._monthIncomes];
    if (_sortMode == _IncomeSortMode.dateDesc) {
      list.sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return b.amount.compareTo(a.amount);
      });
    } else {
      list.sort((a, b) {
        final amtCmp = b.amount.compareTo(a.amount);
        if (amtCmp != 0) return amtCmp;
        return b.date.compareTo(a.date);
      });
    }
    return list;
  }

  /// 収入マスタID別にグループ化（null は "未紐づけ"）。
  Map<String?, List<core.Transaction>> get _bySource {
    final map = <String?, List<core.Transaction>>{};
    for (final t in _monthIncomes) {
      map.putIfAbsent(t.incomeSourceId, () => []).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) => b.amount.compareTo(a.amount));
    }
    return map;
  }

  /// マスタ合計の降順。
  List<MapEntry<String?, int>> get _sourceTotalsSorted {
    final totals = <String?, int>{};
    for (final t in _monthIncomes) {
      totals[t.incomeSourceId] =
          (totals[t.incomeSourceId] ?? 0) + t.amount;
    }
    return totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// 収入マスタIDから名称を引く。null なら "未紐づけ"。
  String _sourceLabel(String? sourceId) {
    if (sourceId == null) return '未紐づけ';
    final srcs = _sources;
    if (srcs == null) return '不明';
    for (final s in srcs.sources) {
      if (s.id == sourceId) {
        return s.name +
            (s.clientName != null ? ' (${s.clientName})' : '');
      }
    }
    return '削除済マスタ';
  }

  @override
  Widget build(BuildContext context) {
    final monthIncomes = _monthIncomes;
    final totalAmount =
        monthIncomes.fold<int>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('収入',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          IconButton(
            tooltip: '収入を記録',
            icon: const Icon(Icons.add_circle,
                color: Color(0xFF16A34A), size: 28),
            onPressed: () async {
              final saved = await showIncomeInputModal(context);
              if (saved == true && mounted) _load();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _monthHeader(monthIncomes.length, totalAmount),
            _viewToggle(),
            Expanded(
              child: monthIncomes.isEmpty
                  ? _empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        if (_viewMode == _IncomeViewMode.list)
                          ..._sortedMonthIncomes.map(_txnCard)
                        else
                          ..._sourceTotalsSorted.map((e) =>
                              _sourceSection(e.key, e.value, _bySource[e.key]!)),
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
            icon: const Icon(Icons.chevron_left, color: Color(0xFF16A34A)),
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
                    Text('合計 ${formatYen(total, withSign: true)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF16A34A),
                            fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right, color: Color(0xFF16A34A)),
          ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                      child: _toggleSeg(
                          _IncomeViewMode.list, 'リスト', Icons.list)),
                  Expanded(
                      child: _toggleSeg(_IncomeViewMode.grouped, 'カテゴリ',
                          Icons.folder_outlined)),
                ],
              ),
            ),
          ),
          if (_viewMode == _IncomeViewMode.list) ...[
            const SizedBox(width: 8),
            _sortMenu(),
          ],
        ],
      ),
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<_IncomeSortMode>(
      tooltip: '並び順',
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 16, color: Color(0xFF6B7280)),
            const SizedBox(width: 4),
            Text(
              _sortMode == _IncomeSortMode.dateDesc ? '日付順' : '金額順',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
      onSelected: (m) => setState(() => _sortMode = m),
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: _IncomeSortMode.dateDesc, child: Text('日付の新しい順')),
        PopupMenuItem(
            value: _IncomeSortMode.amountDesc, child: Text('金額の大きい順')),
      ],
    );
  }

  Widget _toggleSeg(_IncomeViewMode mode, String label, IconData icon) {
    final selected = _viewMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 3,
                      offset: Offset(0, 1))
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.savings_outlined,
                size: 72, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('この月は収入記録なし',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            SizedBox(height: 4),
            Text('右下の「収入を記録」ボタンから記録できます',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
      );

  /// 1取引を1枚のカードとして表示（リスト表示）。
  Widget _txnCard(core.Transaction t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.attach_money,
                color: Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  '${formatMonthDay(t.date)}（${weekdayKanji(t.date)}） · ${_sourceLabel(t.incomeSourceId)} · ${t.paymentMethod}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Text(
            formatYen(t.amount, withSign: true),
            style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF16A34A),
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 収入マスタでグループ化した表示。
  Widget _sourceSection(
      String? sourceId, int total, List<core.Transaction> txns) {
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
          initiallyExpanded: true,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          leading: const Icon(Icons.attach_money,
              color: Color(0xFF16A34A), size: 20),
          title: Text(_sourceLabel(sourceId),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827))),
          subtitle: Text('${txns.length}件',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF9CA3AF))),
          trailing: Text(
            formatYen(total, withSign: true),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16A34A),
                fontFamily: 'monospace'),
          ),
          children: txns.map((t) => _txnRowInGroup(t)).toList(),
        ),
      ),
    );
  }

  /// グループ表示内の取引行。
  Widget _txnRowInGroup(core.Transaction t) {
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
                  t.paymentMethod,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Text(
            formatYen(t.amount, withSign: true),
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF16A34A),
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
