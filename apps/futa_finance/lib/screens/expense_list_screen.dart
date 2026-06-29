import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import '../utils/category_colors.dart';
import '../utils/formatters.dart';
import '../widgets/date_weekday_text.dart';
import 'receipt_group_detail_screen.dart';
import 'transaction_detail_screen.dart';

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
        // 支出に加えて振替も一覧に載せる（振替と分かるよう行側で区別表示）。
        .where((t) =>
            t.type == core.TransactionType.expense ||
            t.type == core.TransactionType.transfer)
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

  /// 行タップ：まず詳細画面を表示（そこから編集/削除）。
  Future<void> _editRow(core.Transaction t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: t)),
    );
    if (changed == true && mounted) await _load();
  }

  /// まとめ（複数品目）行タップ：まとめ編集画面（内訳＋まとめ編集・削除）へ。
  Future<void> _showGroupDetail(List<core.Transaction> members) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => ReceiptGroupDetailScreen(members: members)),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    // 合計は支出のみ（振替はお金の移動なので足さない）。
    final total = rows
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
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
                            return ListView.builder(
                              padding: const EdgeInsets.only(top: 8),
                              itemCount: units.length,
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

  /// ミュートなグレーバッジ（まとめ件数などに使う）。
  Widget _badge(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
      );

  Widget _amountText(int amount) => Text('-${formatYen(amount)}',
      style: const TextStyle(
          fontSize: 15,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          color: Color(0xFFDC2626)));

  /// 振替バッジ（青系・スワップアイコン付き）。支出と区別する。
  Widget _transferBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 11, color: Color(0xFF0EA5E9)),
            SizedBox(width: 2),
            Text('振替',
                style: TextStyle(fontSize: 11, color: Color(0xFF0EA5E9))),
          ],
        ),
      );

  /// 振替金額（中立色・マイナスなし）。
  Widget _transferAmount(int amount) => Text(formatYen(amount),
      style: const TextStyle(
          fontSize: 15,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569)));

  /// 白カード（角丸・枠付き・左右余白）。左端にカテゴリ色のアクセントバーを付ける。
  Widget _card(
      {required Widget child, VoidCallback? onTap, Color? accent}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accent ?? const Color(0xFFE5E7EB)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 大カテゴリ名から安定した色を作る（バッジ・アクセントの色付けに使う）。
  Color _catColor(String major) {
    final manual = CategoryColors.resolve(major);
    if (manual != null) return manual;
    final m = major.trim();
    if (m.isEmpty) return const Color(0xFF9CA3AF);
    var h = 0;
    for (final c in m.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.45).toColor();
  }

  /// カテゴリバッジ：「大カテゴリ › 小カテゴリ」を色付きで表示。
  Widget _catBadge(core.Category c, Color color) {
    final major = c.major.trim();
    final sub = c.sub.trim();
    final label = (major.isEmpty && sub.isEmpty)
        ? '未分類'
        : (sub.isEmpty ? major : '$major › $sub');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HSLColor.fromColor(color)
                  .withLightness(0.32)
                  .toColor())),
    );
  }

  /// 支払方法に合うアイコンを推定する。
  IconData _paymentIcon(String method) {
    final s = method.toLowerCase();
    if (method.contains('現金')) return Icons.payments_outlined;
    if (method.contains('カード') ||
        method.contains('クレカ') ||
        method.contains('オリコ') ||
        s.contains('card') ||
        s.contains('visa') ||
        s.contains('orico')) {
      return Icons.credit_card;
    }
    if (method.contains('銀行') ||
        method.contains('振込') ||
        method.contains('引落') ||
        s.contains('bank')) {
      return Icons.account_balance_outlined;
    }
    if (s.contains('suica') ||
        s.contains('paypay') ||
        s.contains('quicpay') ||
        s.contains('id') ||
        method.contains('電子') ||
        method.contains('チャージ')) {
      return Icons.contactless_outlined;
    }
    return Icons.payment_outlined;
  }

  /// 支払方法チップ（アイコン＋名称）。空なら何も出さない。
  Widget _paymentChip(String method) {
    final m = method.trim();
    if (m.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_paymentIcon(m), size: 12, color: const Color(0xFF64748B)),
          const SizedBox(width: 3),
          Text(m,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B))),
        ],
      ),
    );
  }

  /// 日付（曜日付き）。行の左側に縦並びで表示。
  Widget _dateCol(DateTime d) => SizedBox(
        width: 52,
        child: dateWeekdayText(d,
            baseStyle: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFF6B7280))),
      );

  /// 単品行（1取引）。白カード：日付｜内容＋（カテゴリ/支払方法）｜金額。
  Widget _singleRow(core.Transaction t) {
    final isTransfer = t.type == core.TransactionType.transfer;
    final accent =
        isTransfer ? const Color(0xFF0EA5E9) : _catColor(t.category.major);
    // 振替は「振替元 → 振替先」を支払方法の代わりに表示する。
    final payLabel = isTransfer
        ? [t.transferFromAccount, t.transferToAccount]
            .where((s) => (s ?? '').trim().isNotEmpty)
            .join(' → ')
        : t.paymentMethod;
    return _card(
      onTap: () => _editRow(t),
      accent: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _dateCol(t.date),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.description.isEmpty ? '—' : t.description,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    isTransfer
                        ? _transferBadge()
                        : _catBadge(t.category, accent),
                    _paymentChip(payLabel),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          isTransfer ? _transferAmount(t.amount) : _amountText(t.amount),
        ],
      ),
    );
  }

  /// レシートまとめの親行（白カード）。タップでまとめ編集画面（内訳＋編集・削除）へ。
  Widget _groupRow(_Unit u) {
    final m = u.members!;
    final first = m.first;
    final store = m
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final title = store.isNotEmpty ? store : 'まとめ記録';
    final accent = _catColor(first.category.major);
    return _card(
      onTap: () => _showGroupDetail(m),
      accent: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _dateCol(first.date),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _badge('🧾 ${m.length}件まとめ'),
                    _catBadge(first.category, accent),
                    _paymentChip(first.paymentMethod),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _amountText(u.total),
        ],
      ),
    );
  }

}
