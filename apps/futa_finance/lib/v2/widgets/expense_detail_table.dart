import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/category_colors.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 支出明細の共通テーブル（PC幅・表形式）。
///
/// 支出タブ（rich_expenses）とクレカ詳細（card_detail）で共用。
/// 日付/カテゴリ(色)/内容/支払方法/金額の表＋検索＋並び替えバッジ＋列幅ドラッグ。
class ExpenseDetailTable extends StatefulWidget {
  /// 表示対象の取引（呼び出し側で絞り込み済み）。
  final List<core.Transaction> rows;

  /// 行タップ時（編集を開く等）。
  final Future<void> Function(core.Transaction t) onEditTxn;

  /// アクセント色（バッジ選択色）。
  final Color accent;

  /// 見出し（例「支出明細」「明細」）。
  final String title;

  /// 0件時の補助文（検索ヒット0件は別メッセージ）。
  final String emptyHint;

  const ExpenseDetailTable({
    super.key,
    required this.rows,
    required this.onEditTxn,
    required this.accent,
    this.title = '明細',
    this.emptyHint = '記録はまだありません',
  });

  @override
  State<ExpenseDetailTable> createState() => _ExpenseDetailTableState();
}

class _ExpenseDetailTableState extends State<ExpenseDetailTable> {
  // 列幅（中央3列の配分・合計1.0）。端末に保存（全画面共通）。
  List<double> _colFrac = const [0.36, 0.37, 0.27];
  static const _kColFracKey = 'futa.exp_table_col_frac';

  _ExpSort _expSort = _ExpSort.dateDesc;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadColFrac();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadColFrac() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kColFracKey);
    if (raw == null || raw.length != 3) return;
    final f = raw.map((e) => double.tryParse(e) ?? 0).toList();
    final sum = f.fold<double>(0, (a, b) => a + b);
    if (sum <= 0 || f.any((e) => e <= 0)) return;
    if (!mounted) return;
    setState(() => _colFrac = f.map((e) => e / sum).toList());
  }

  Future<void> _saveColFrac() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _kColFracKey, _colFrac.map((e) => e.toStringAsFixed(4)).toList());
  }

  void _resizeCol(int handleIndex, double dx, double middleWidth) {
    const minW = 60.0;
    final widths = _colFrac.map((f) => f * middleWidth).toList();
    final i = handleIndex, j = handleIndex + 1;
    final wi = widths[i] + dx;
    final wj = widths[j] - dx;
    if (wi < minW || wj < minW) return;
    widths[i] = wi;
    widths[j] = wj;
    setState(() => _colFrac = widths.map((w) => w / middleWidth).toList());
  }

  List<core.Transaction> _sortFilter(List<core.Transaction> rows) {
    final q = _query.trim().toLowerCase();
    var list = q.isEmpty
        ? [...rows]
        : rows.where((t) {
            final hay = [
              t.description,
              t.category.major,
              t.category.sub,
              t.paymentMethod,
              t.memo ?? '',
              t.store ?? '',
            ].join(' ').toLowerCase();
            return hay.contains(q);
          }).toList();
    switch (_expSort) {
      case _ExpSort.dateDesc:
        list.sort((a, b) => b.date.compareTo(a.date));
        break;
      case _ExpSort.dateAsc:
        list.sort((a, b) => a.date.compareTo(b.date));
        break;
      case _ExpSort.amountDesc:
        list.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case _ExpSort.amountAsc:
        list.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case _ExpSort.category:
        list.sort((a, b) {
          final c = a.category.majorOrder.compareTo(b.category.majorOrder);
          if (c != 0) return c;
          final s = a.category.sub.compareTo(b.category.sub);
          if (s != 0) return s;
          return b.date.compareTo(a.date);
        });
        break;
    }
    return list;
  }

  Widget _sortBadge(_ExpSort s) {
    final sel = _expSort == s;
    return InkWell(
      onTap: () => setState(() => _expSort = s),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? widget.accent : V2Colors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? widget.accent : V2Colors.border),
        ),
        child: Text(s.badgeLabel,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : V2Colors.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailRows = _sortFilter(widget.rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(widget.title,
                style: V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
            const SizedBox(width: 8),
            Text('${detailRows.length}件',
                style: V2Typography.caption
                    .copyWith(color: V2Colors.textSecondary)),
            const Spacer(),
            const Icon(Icons.sort, size: 16, color: V2Colors.textSecondary),
            const SizedBox(width: 6),
            Wrap(
              spacing: 6,
              children: [for (final s in _ExpSort.values) _sortBadge(s)],
            ),
          ],
        ),
        const SizedBox(height: V2Spacing.sm),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: '内容・カテゴリ・支払方法で検索',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: V2Colors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: V2Colors.border)),
          ),
        ),
        const SizedBox(height: V2Spacing.sm),
        if (detailRows.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: V2Colors.border),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.inbox_outlined,
                      size: 36, color: V2Colors.textMuted),
                  const SizedBox(height: 8),
                  Text(
                      _query.isNotEmpty
                          ? '「$_query」に一致する明細はありません'
                          : widget.emptyHint,
                      style: V2Typography.caption
                          .copyWith(color: V2Colors.textSecondary)),
                ],
              ),
            ),
          )
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: V2Colors.border),
            ),
            child: LayoutBuilder(builder: (ctx, cons) {
              final innerW = cons.maxWidth - 24;
              final fixed =
                  _kDateW + _kAmountW + _kColGap * 2 + _kHandleW * 2;
              final mw = (innerW - fixed) < 120 ? 120.0 : innerW - fixed;
              final w = _ColW(
                date: _kDateW,
                cat: _colFrac[0] * mw,
                content: _colFrac[1] * mw,
                pay: _colFrac[2] * mw,
                amount: _kAmountW,
              );
              return Column(
                children: [
                  _ExpenseTableHeader(
                    w: w,
                    onResize: (i, dx) => _resizeCol(i, dx, mw),
                    onResizeEnd: _saveColFrac,
                  ),
                  for (final t in detailRows) ...[
                    const Divider(height: 1, color: V2Colors.divider),
                    _ExpenseRow(t: t, onTap: () => widget.onEditTxn(t), w: w),
                  ],
                ],
              );
            }),
          ),
      ],
    );
  }
}

/// 大カテゴリ名から安定した色を作る（ユーザー指定色を最優先）。
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

IconData _paymentIcon(String method) {
  final s = method.toLowerCase();
  if (method.contains('現金')) return Icons.payments_outlined;
  if (method.contains('カード') ||
      method.contains('クレカ') ||
      method.contains('オリコ') ||
      s.contains('card') ||
      s.contains('visa')) {
    return Icons.credit_card;
  }
  if (method.contains('銀行') ||
      method.contains('振込') ||
      method.contains('引落')) {
    return Icons.account_balance_outlined;
  }
  if (s.contains('suica') ||
      s.contains('paypay') ||
      method.contains('電子') ||
      method.contains('チャージ')) {
    return Icons.contactless_outlined;
  }
  return Icons.payment_outlined;
}

enum _ExpSort { dateDesc, dateAsc, amountDesc, amountAsc, category }

extension _ExpSortX on _ExpSort {
  String get badgeLabel {
    switch (this) {
      case _ExpSort.dateDesc:
        return '新しい順';
      case _ExpSort.dateAsc:
        return '古い順';
      case _ExpSort.amountDesc:
        return '高い順';
      case _ExpSort.amountAsc:
        return '安い順';
      case _ExpSort.category:
        return 'カテゴリ順';
    }
  }
}

const double _kDateW = 48;
const double _kAmountW = 92;
const double _kColGap = 8;
const double _kHandleW = 12;

class _ColW {
  final double date;
  final double cat;
  final double content;
  final double pay;
  final double amount;
  const _ColW({
    required this.date,
    required this.cat,
    required this.content,
    required this.pay,
    required this.amount,
  });
}

class _ExpenseTableHeader extends StatelessWidget {
  final _ColW w;
  final void Function(int handleIndex, double dx) onResize;
  final VoidCallback onResizeEnd;
  const _ExpenseTableHeader({
    required this.w,
    required this.onResize,
    required this.onResizeEnd,
  });

  static Widget _h(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      overflow: TextOverflow.ellipsis,
      style: V2Typography.micro
          .copyWith(color: V2Colors.textMuted, fontWeight: FontWeight.w700));

  Widget _handle(int i) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onResize(i, d.delta.dx),
          onHorizontalDragEnd: (_) => onResizeEnd(),
          child: SizedBox(
            width: _kHandleW,
            height: 20,
            child: Center(
              child: Container(width: 2, height: 12, color: V2Colors.border),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: w.date, child: _h('日付')),
          const SizedBox(width: _kColGap),
          SizedBox(width: w.cat, child: _h('カテゴリ')),
          _handle(0),
          SizedBox(width: w.content, child: _h('内容')),
          _handle(1),
          SizedBox(width: w.pay, child: _h('支払方法')),
          const SizedBox(width: _kColGap),
          SizedBox(width: w.amount, child: _h('金額', right: true)),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  final _ColW w;
  const _ExpenseRow({required this.t, required this.onTap, required this.w});

  @override
  Widget build(BuildContext context) {
    final accent = _catColor(t.category.major);
    final major = t.category.major.trim();
    final sub = t.category.sub.trim();
    final catLabel = (major.isEmpty && sub.isEmpty)
        ? '未分類'
        : (sub.isEmpty ? major : '$major › $sub');
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (sub.isNotEmpty ? sub : (major.isNotEmpty ? major : '未分類'));
    final pay = t.paymentMethod.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: w.date,
              child: Text(formatMonthDay(t.date),
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textSecondary,
                      fontFeatures: V2Typography.tabularNums)),
            ),
            const SizedBox(width: _kColGap),
            SizedBox(
              width: w.cat,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(catLabel,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: HSLColor.fromColor(accent)
                                    .withLightness(0.30)
                                    .toColor())),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: _kHandleW),
            SizedBox(
              width: w.content,
              child: Text(title,
                  style: V2Typography.body.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
            const SizedBox(width: _kHandleW),
            SizedBox(
              width: w.pay,
              child: Row(
                children: [
                  Icon(_paymentIcon(pay),
                      size: 13, color: const Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(pay,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B))),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _kColGap),
            SizedBox(
              width: w.amount,
              child: Text('-${formatYen(t.amount)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.negative,
                      fontFeatures: V2Typography.tabularNums)),
            ),
          ],
        ),
      ),
    );
  }
}
