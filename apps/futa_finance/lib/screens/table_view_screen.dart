import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// Web/Desktop 専用のテーブルビュー画面。
/// 全取引を1つのフラットなテーブルで表示し、列ソート＋テキストフィルタ＋
/// 期間/フロー絞り込みができる。Excel/スプシ風の体験を想定。
class TableViewScreen extends StatefulWidget {
  const TableViewScreen({super.key});

  @override
  State<TableViewScreen> createState() => _TableViewScreenState();
}

/// 並び替え対象の列。
enum _SortColumn { date, type, major, sub, payment, description, amount }

/// 並び替え方向。
enum _SortDir { asc, desc }

/// 期間フィルタ。
enum _Period { all, currentMonth, last3, last6, last12, currentYear }

extension _PeriodX on _Period {
  String get label {
    switch (this) {
      case _Period.all:
        return '全期間';
      case _Period.currentMonth:
        return '今月';
      case _Period.last3:
        return '直近3ヶ月';
      case _Period.last6:
        return '直近6ヶ月';
      case _Period.last12:
        return '直近12ヶ月';
      case _Period.currentYear:
        return '今年';
    }
  }

  DateTime? startFrom(DateTime now) {
    switch (this) {
      case _Period.all:
        return null;
      case _Period.currentMonth:
        return DateTime(now.year, now.month, 1);
      case _Period.last3:
        return DateTime(now.year, now.month - 2, 1);
      case _Period.last6:
        return DateTime(now.year, now.month - 5, 1);
      case _Period.last12:
        return DateTime(now.year, now.month - 11, 1);
      case _Period.currentYear:
        return DateTime(now.year, 1, 1);
    }
  }
}

/// フロー絞り込み。
enum _FlowFilter { all, expense, income, transfer }

extension _FlowFilterX on _FlowFilter {
  String get label {
    switch (this) {
      case _FlowFilter.all:
        return 'すべて';
      case _FlowFilter.expense:
        return '支出';
      case _FlowFilter.income:
        return '収入';
      case _FlowFilter.transfer:
        return '振替';
    }
  }
}

class _TableViewScreenState extends State<TableViewScreen>
    with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];

  _SortColumn _sortBy = _SortColumn.date;
  _SortDir _sortDir = _SortDir.desc;
  _Period _period = _Period.currentMonth;
  _FlowFilter _flow = _FlowFilter.all;
  final _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    _queryCtrl.addListener(() {
      setState(() => _query = _queryCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() => _transactions = list);
  }

  // ── フィルタ + ソート ──
  List<core.Transaction> get _filtered {
    final now = DateTime.now();
    final start = _period.startFrom(now);
    final q = _query.toLowerCase();

    var list = _transactions.where((t) {
      // 期間
      if (start != null && t.date.isBefore(start)) return false;
      // フロー
      if (_flow == _FlowFilter.expense &&
          t.type != core.TransactionType.expense) {
        return false;
      }
      if (_flow == _FlowFilter.income &&
          t.type != core.TransactionType.income) {
        return false;
      }
      if (_flow == _FlowFilter.transfer &&
          t.type != core.TransactionType.transfer) {
        return false;
      }
      // テキスト
      if (q.isNotEmpty) {
        final hit = t.description.toLowerCase().contains(q) ||
            t.category.major.toLowerCase().contains(q) ||
            t.category.sub.toLowerCase().contains(q) ||
            t.paymentMethod.toLowerCase().contains(q) ||
            (t.memo ?? '').toLowerCase().contains(q);
        if (!hit) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case _SortColumn.date:
          cmp = a.date.compareTo(b.date);
          break;
        case _SortColumn.type:
          cmp = a.type.index.compareTo(b.type.index);
          break;
        case _SortColumn.major:
          cmp = a.category.major.compareTo(b.category.major);
          break;
        case _SortColumn.sub:
          cmp = a.category.sub.compareTo(b.category.sub);
          break;
        case _SortColumn.payment:
          cmp = a.paymentMethod.compareTo(b.paymentMethod);
          break;
        case _SortColumn.description:
          cmp = a.description.compareTo(b.description);
          break;
        case _SortColumn.amount:
          cmp = a.amount.compareTo(b.amount);
          break;
      }
      return _sortDir == _SortDir.asc ? cmp : -cmp;
    });

    return list;
  }

  /// 列ヘッダクリック: 同じ列なら方向反転、別の列なら降順から開始。
  void _toggleSort(_SortColumn col) {
    setState(() {
      if (_sortBy == col) {
        _sortDir = _sortDir == _SortDir.asc ? _SortDir.desc : _SortDir.asc;
      } else {
        _sortBy = col;
        _sortDir = _SortDir.desc;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final expenseSum = list
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    final incomeSum = list
        .where((t) => t.type == core.TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('テーブル',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _filterBar(),
          _summaryBar(list.length, expenseSum, incomeSum),
          const Divider(height: 1),
          Expanded(child: _buildTable(list)),
        ],
      ),
    );
  }

  // ── フィルタバー ──
  Widget _filterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 期間
          DropdownButton<_Period>(
            value: _period,
            underline: const SizedBox.shrink(),
            items: _Period.values
                .map((p) =>
                    DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _period = v);
            },
          ),
          // フロー
          SegmentedButton<_FlowFilter>(
            segments: _FlowFilter.values
                .map((f) => ButtonSegment(value: f, label: Text(f.label)))
                .toList(),
            selected: {_flow},
            onSelectionChanged: (s) {
              setState(() => _flow = s.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          // 検索
          SizedBox(
            width: 240,
            child: TextField(
              controller: _queryCtrl,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: '名前 / カテゴリ / 支払方法 / メモ',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _queryCtrl.clear();
                        },
                      ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── サマリーバー（件数・合計） ──
  Widget _summaryBar(int count, int expenseSum, int incomeSum) {
    final net = incomeSum - expenseSum;
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text('$count 件',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(width: 16),
          _summaryChip('支出', expenseSum, const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          _summaryChip('収入', incomeSum, const Color(0xFF16A34A)),
          const Spacer(),
          Text(
            '差引: ${formatYen(net, withSign: true)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color:
                  net >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label ${formatYen(amount)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── テーブル本体 ──
  Widget _buildTable(List<core.Transaction> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          '該当する取引がありません',
          style: TextStyle(color: Color(0xFF9CA3AF)),
        ),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: _SortColumn.values.indexOf(_sortBy),
            sortAscending: _sortDir == _SortDir.asc,
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF3F4F6)),
            headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151)),
            dataTextStyle: const TextStyle(
                fontSize: 12, color: Color(0xFF111827)),
            columnSpacing: 24,
            horizontalMargin: 16,
            columns: [
              DataColumn(
                label: const Text('日付'),
                onSort: (_, _) => _toggleSort(_SortColumn.date),
              ),
              DataColumn(
                label: const Text('種別'),
                onSort: (_, _) => _toggleSort(_SortColumn.type),
              ),
              DataColumn(
                label: const Text('大カテゴリ'),
                onSort: (_, _) => _toggleSort(_SortColumn.major),
              ),
              DataColumn(
                label: const Text('小カテゴリ'),
                onSort: (_, _) => _toggleSort(_SortColumn.sub),
              ),
              DataColumn(
                label: const Text('支払方法'),
                onSort: (_, _) => _toggleSort(_SortColumn.payment),
              ),
              DataColumn(
                label: const Text('内容'),
                onSort: (_, _) => _toggleSort(_SortColumn.description),
              ),
              DataColumn(
                label: const Text('金額'),
                numeric: true,
                onSort: (_, _) => _toggleSort(_SortColumn.amount),
              ),
              const DataColumn(label: Text('メモ')),
            ],
            rows: list.map((t) {
              final isIncome = t.type == core.TransactionType.income;
              final amountColor = isIncome
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626);
              return DataRow(
                cells: [
                  DataCell(Text(
                      '${t.date.year}/${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}')),
                  DataCell(_typeBadge(t.type)),
                  DataCell(Text(t.category.major)),
                  DataCell(Text(t.category.sub)),
                  DataCell(Text(t.paymentMethod)),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        t.description,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${isIncome ? '+' : '-'}${formatYen(t.amount)}',
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 160,
                      child: Text(
                        t.memo ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(core.TransactionType type) {
    final (color, label) = switch (type) {
      core.TransactionType.income => (const Color(0xFF16A34A), '収入'),
      core.TransactionType.expense => (const Color(0xFFDC2626), '支出'),
      core.TransactionType.transfer => (const Color(0xFFEA580C), '振替'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
