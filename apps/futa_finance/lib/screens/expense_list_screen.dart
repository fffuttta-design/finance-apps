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

/// 一覧の表示単位。単品（single）か、同じレシートのまとめ（group）。
class _Unit {
  final core.Transaction? single;
  final String? receiptId;
  final List<core.Transaction>? members;
  const _Unit.single(this.single)
      : receiptId = null,
        members = null;
  const _Unit.group(this.receiptId, this.members) : single = null;
  bool get isGroup => members != null;
  int get total => single != null
      ? single!.amount
      : members!.fold<int>(0, (s, t) => s + t.amount);
}

/// カテゴリ名から安定した色を作る（同じカテゴリは常に同じ色）。
Color _catColor(String name) {
  if (name.trim().isEmpty) return const Color(0xFF9CA3AF);
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.52, 0.50).toColor();
}

/// バッジ文字色（同じ色相で暗め）。
Color _catTextColor(String name) {
  if (name.trim().isEmpty) return const Color(0xFF6B7280);
  return HSLColor.fromColor(_catColor(name)).withLightness(0.34).toColor();
}

/// 経費明細（支出取引）の全件一覧画面。
/// - 並び替え（日付/金額/カテゴリ）
/// - 検索（内容・カテゴリ・支払方法・備考）
/// - 同じレシートの複数品目は親1行にまとめ、タップで内訳を展開
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

  /// 展開中のレシート（receiptId）。タップで内訳を開閉。
  final Set<String> _expanded = {};

  /// 絞り込み済みの取引を、レシート単位でまとめた表示単位に変換する。
  /// 同じ receiptId が 2 件以上 → まとめ（group）、それ以外 → 単品（single）。
  /// 並び順は _filtered の順（＝親はその最初の品目の位置）を保つ。
  List<_Unit> get _units {
    final rows = _filtered;
    final counts = <String, int>{};
    for (final t in rows) {
      final rid = t.receiptId;
      if (rid != null && rid.isNotEmpty) {
        counts[rid] = (counts[rid] ?? 0) + 1;
      }
    }
    final units = <_Unit>[];
    final seen = <String>{};
    for (final t in rows) {
      final rid = t.receiptId;
      if (rid != null && rid.isNotEmpty && (counts[rid] ?? 0) >= 2) {
        if (seen.add(rid)) {
          units.add(_Unit.group(
              rid, rows.where((x) => x.receiptId == rid).toList()));
        }
      } else {
        units.add(_Unit.single(t));
      }
    }
    return units;
  }

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
                        : Builder(builder: (_) {
                            final units = _units;
                            return ListView.separated(
                              itemCount: units.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final u = units[i];
                                return u.isGroup
                                    ? _groupRow(u)
                                    : _singleRow(u.single!);
                              },
                            );
                          }),
                  ),
                ],
              ),
              ),
              ),
            ),
    );
  }

  /// カテゴリバッジ（大カテゴリ ＞ 小カテゴリ・カテゴリ色付き）。
  Widget _catBadge(core.Category category) {
    final major = category.major.trim();
    final sub = category.sub.trim();
    final label = major.isEmpty
        ? (sub.isEmpty ? '未分類' : sub)
        : (sub.isEmpty ? major : '$major ＞ $sub');
    final key = major.isEmpty ? sub : major;
    final color = _catColor(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _catTextColor(key))),
    );
  }

  Widget _storeLine(String? store) {
    if (store == null || store.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined,
              size: 11, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(store.trim(),
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _amountText(int amount) => Text('-${formatYen(amount)}',
      style: const TextStyle(
          fontSize: 16,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          color: Color(0xFFDC2626)));

  /// 単品行（1取引）。
  Widget _singleRow(core.Transaction t) {
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
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _catBadge(t.category)),
                  const SizedBox(height: 4),
                  Text(
                    t.description.isEmpty ? '—' : t.description,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  _storeLine(t.store),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _amountText(t.amount),
          ],
        ),
      ),
    );
  }

  /// レシートまとめの親行（タップで内訳を開閉）＋ 展開時は内訳の子行。
  Widget _groupRow(_Unit u) {
    final m = u.members!;
    final rid = u.receiptId!;
    final expanded = _expanded.contains(rid);
    final first = m.first;
    final store = m
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final title = store.isNotEmpty ? store : 'まとめ記録';
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            if (expanded) {
              _expanded.remove(rid);
            } else {
              _expanded.add(rid);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text('${first.date.month}/${first.date.day}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Color(0xFF6B7280))),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.receipt_long_rounded,
                    size: 20, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('🧾 ${m.length}件まとめ',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4338CA))),
                      ),
                      const SizedBox(height: 4),
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _amountText(u.total),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF)),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final t in m) _childRow(t),
      ],
    );
  }

  /// レシート内訳の子行（インデント表示・タップで編集）。
  Widget _childRow(core.Transaction t) {
    return InkWell(
      onTap: () => _editRow(t),
      child: Container(
        color: const Color(0xFFFAFAFC),
        padding: const EdgeInsets.fromLTRB(46, 7, 14, 7),
        child: Row(
          children: [
            const Icon(Icons.subdirectory_arrow_right_rounded,
                size: 15, color: Color(0xFFC7CCD6)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _catBadge(t.category)),
                  const SizedBox(height: 3),
                  Text(
                    t.description.isEmpty ? '—' : t.description,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('-${formatYen(t.amount)}',
                style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626))),
          ],
        ),
      ),
    );
  }
}
