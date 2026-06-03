import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../widgets/brand_logo.dart';
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
  const ExpenseListScreen({super.key, this.title = '経費明細一覧'});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  final _txRepo = TransactionRepository.instance;
  final _settings = SettingsRepository();

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig _payments = core.PaymentMethodsConfig.empty();
  bool _loading = true;

  _Sort _sort = _Sort.dateDesc;
  final _searchCtrl = TextEditingController();
  String _query = '';

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
    final payments = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _loading = false;
    });
  }

  String? _iconUrlFor(String name) {
    for (final b in _payments.bankAccounts) {
      if (b.name == name) return b.iconUrl;
    }
    for (final c in _payments.creditCards) {
      if (c.name == name) return c.iconUrl;
    }
    return null;
  }

  List<core.Transaction> get _filtered {
    final q = _query.trim().toLowerCase();
    var list = _transactions
        .where((t) => t.type == core.TransactionType.expense)
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
              child: Column(
                children: [
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(cat,
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF374151))),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t.description.isEmpty ? '—' : t.description,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      BrandLogo(
                        iconUrl: _iconUrlFor(t.paymentMethod),
                        fallbackIcon: Icons.account_balance,
                        size: 13,
                        borderRadius: 3,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(t.paymentMethod,
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF9CA3AF)),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('-${formatYen(t.amount)}',
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626))),
          ],
        ),
      ),
    );
  }
}
