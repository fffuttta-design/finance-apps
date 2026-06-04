import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import 'expense_input_screen.dart';

/// 並び替えモード。
enum _Sort { dateDesc, dateAsc, amountDesc, amountAsc, categoryAsc }

extension _SortX on _Sort {
  String get label {
    switch (this) {
      case _Sort.dateDesc:
        return '日付が新しい順';
      case _Sort.dateAsc:
        return '日付が古い順';
      case _Sort.amountDesc:
        return '金額の高い順';
      case _Sort.amountAsc:
        return '金額の安い順';
      case _Sort.categoryAsc:
        return 'カテゴリ順';
    }
  }
}

/// 経費明細（支出取引）の全件一覧画面。
/// - 並び替え（日付/金額/カテゴリ）
/// - 検索（内容・カテゴリ・支払方法・備考）
/// - 行タップで編集
class ExpenseListScreen extends StatefulWidget {
  /// 表示タイトル（事業=経費明細 / 個人=支出明細）。
  final String title;

  /// 指定すると、その月（年・月）の明細だけに絞り込む。
  /// null なら全期間（従来どおり）。画面内で前月/翌月に移動できる。
  final DateTime? month;
  const ExpenseListScreen({super.key, this.title = '経費明細一覧', this.month});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  bool _loading = true;

  _Sort _sort = _Sort.dateDesc;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// 月絞り込み（null=全期間）。前月/翌月ボタンで移動。
  late DateTime? _month =
      widget.month == null ? null : DateTime(widget.month!.year, widget.month!.month);

  void _shiftMonth(int delta) {
    final m = _month;
    if (m == null) return;
    setState(() => _month = DateTime(m.year, m.month + delta));
  }

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _loading = false;
    });
  }

  List<core.Transaction> get _filtered {
    final q = _query.trim().toLowerCase();
    final m = _month;
    var list = _transactions
        .where((t) => t.type == core.TransactionType.expense)
        .where((t) =>
            m == null || (t.date.year == m.year && t.date.month == m.month))
        .where((t) {
      if (q.isEmpty) return true;
      return t.description.toLowerCase().contains(q) ||
          t.category.major.toLowerCase().contains(q) ||
          t.category.sub.toLowerCase().contains(q) ||
          t.paymentMethod.toLowerCase().contains(q) ||
          (t.memo ?? '').toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.dateDesc:
        list.sort((a, b) => b.date.compareTo(a.date));
        break;
      case _Sort.dateAsc:
        list.sort((a, b) => a.date.compareTo(b.date));
        break;
      case _Sort.amountDesc:
        list.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case _Sort.amountAsc:
        list.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case _Sort.categoryAsc:
        list.sort((a, b) {
          final c = a.category.major.compareTo(b.category.major);
          if (c != 0) return c;
          final s = a.category.sub.compareTo(b.category.sub);
          if (s != 0) return s;
          return b.date.compareTo(a.date);
        });
        break;
    }
    return list;
  }

  Future<void> _editRow(core.Transaction t) async {
    final changed =
        await showInputSheet<bool>(context, ExpenseInputScreen(editing: t));
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final total = rows.fold<int>(0, (s, t) => s + t.amount);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: '並び替え',
            icon: const Icon(Icons.sort, color: Color(0xFF1A237E)),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => _Sort.values
                .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                .toList(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              // 広い画面でテーブルが横一杯に広がって見にくいので、中央 1 カラム
              // （最大幅 760）に制約する。
              child: Center(
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  // 月絞り込みバー（月指定で開いた場合のみ）。前月/翌月へ移動可。
                  if (_month != null)
                    Container(
                      color: const Color(0xFFF8FAFC),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 22,
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => _shiftMonth(-1),
                            tooltip: '前の月',
                          ),
                          Text('${_month!.year}年${_month!.month}月',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827))),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 22,
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => _shiftMonth(1),
                            tooltip: '次の月',
                          ),
                        ],
                      ),
                    ),
                  // 検索
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: '内容・カテゴリ・支払方法で検索',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  // 件数・合計・並び替えラベル
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Row(
                      children: [
                        Text('${rows.length}件',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                        const SizedBox(width: 10),
                        Text('· ${_sort.label}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF9CA3AF))),
                        const Spacer(),
                        Text('合計 -${formatYen(total)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('該当する支出がありません',
                                style: TextStyle(
                                    color: Color(0xFF9CA3AF), fontSize: 13)))
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final t = rows[i];
                              return _row(t);
                            },
                          ),
                  ),
                ],
              ),
              ),
              ),
            ),
    );
  }

  Widget _row(core.Transaction t) {
    final cat = t.category.sub.trim().isNotEmpty
        ? t.category.sub.trim()
        : (t.category.major.trim().isEmpty ? '未分類' : t.category.major.trim());
    return InkWell(
      onTap: () => _editRow(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text('${t.date.month}/${t.date.day}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF6B7280))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // カテゴリバッジ（大きめ）
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(cat,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4338CA))),
                  ),
                  const SizedBox(height: 4),
                  // タイトル（取引内容）を大きく
                  Text(
                    t.description.isEmpty ? '—' : t.description,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 店舗だけ控えめに（支払方法は詳細を開いた時に表示）
                  if (t.store != null && t.store!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined,
                            size: 11, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(t.store!.trim(),
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF)),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('-${formatYen(t.amount)}',
                style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626))),
          ],
        ),
      ),
    );
  }
}
