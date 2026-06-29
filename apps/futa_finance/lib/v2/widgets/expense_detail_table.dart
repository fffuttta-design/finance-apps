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
  // 列幅（中央4列＝大カテゴリ/小カテゴリ/内容/支払方法 の配分・合計1.0）。端末に保存。
  List<double> _colFrac = const [0.18, 0.20, 0.37, 0.25];
  static const _kColFracKey = 'futa.exp_table_col_frac_v2';
  static const _kColCount = 4;

  // 並び替えは表ヘッダーのクリックで列＋昇順/降順を切替。
  _SortCol _sortCol = _SortCol.date;
  bool _asc = false; // 日付は既定で降順（新しい順）。
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// ヘッダークリック：同じ列なら昇順/降順をトグル、別列なら列を切替（既定向き）。
  void _onSort(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _asc = !_asc;
      } else {
        _sortCol = col;
        // 日付・金額は降順、文字列系は昇順を既定に。
        _asc = !(col == _SortCol.date || col == _SortCol.amount);
      }
    });
  }

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
    if (raw == null || raw.length != _kColCount) return;
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
    int cmp;
    switch (_sortCol) {
      case _SortCol.date:
        list.sort((a, b) => a.date.compareTo(b.date));
        break;
      case _SortCol.amount:
        list.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case _SortCol.major:
        list.sort((a, b) {
          cmp = a.category.majorOrder.compareTo(b.category.majorOrder);
          if (cmp != 0) return cmp;
          return a.category.sub.compareTo(b.category.sub);
        });
        break;
      case _SortCol.sub:
        list.sort((a, b) {
          cmp = a.category.sub.compareTo(b.category.sub);
          if (cmp != 0) return cmp;
          return a.category.majorOrder.compareTo(b.category.majorOrder);
        });
        break;
      case _SortCol.content:
        list.sort((a, b) => a.description.compareTo(b.description));
        break;
      case _SortCol.payment:
        list.sort((a, b) => a.paymentMethod.compareTo(b.paymentMethod));
        break;
    }
    if (!_asc) {
      list = list.reversed.toList();
    }
    return list;
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
            Text('ヘッダーをタップで並び替え',
                style:
                    V2Typography.micro.copyWith(color: V2Colors.textMuted)),
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
              // 狭い幅（スマホ）は1行表だと潰れるので2行のスリム表示。
              final narrow = cons.maxWidth < 560;
              if (narrow) {
                return Column(
                  children: [
                    _NarrowSortBar(
                      sortCol: _sortCol,
                      asc: _asc,
                      onSort: _onSort,
                      accent: widget.accent,
                    ),
                    for (final t in detailRows) ...[
                      const Divider(height: 1, color: V2Colors.divider),
                      _NarrowRow(
                          t: t, onTap: () => widget.onEditTxn(t)),
                    ],
                  ],
                );
              }
              final innerW = cons.maxWidth - 24;
              final fixed =
                  _kDateW + _kAmountW + _kColGap * 2 + _kHandleW * 3;
              final mw = (innerW - fixed) < 160 ? 160.0 : innerW - fixed;
              final w = _ColW(
                date: _kDateW,
                major: _colFrac[0] * mw,
                sub: _colFrac[1] * mw,
                content: _colFrac[2] * mw,
                pay: _colFrac[3] * mw,
                amount: _kAmountW,
              );
              return Column(
                children: [
                  _ExpenseTableHeader(
                    w: w,
                    onResize: (i, dx) => _resizeCol(i, dx, mw),
                    onResizeEnd: _saveColFrac,
                    sortCol: _sortCol,
                    asc: _asc,
                    onSort: _onSort,
                    accent: widget.accent,
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
Color expenseCatColor(String major) {
  // 手動色 → 無ければ名前から推測した「それっぽい」既定色（食=オレンジ等）。
  return CategoryColors.effective(major);
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

/// 並び替えの対象列。
enum _SortCol { date, major, sub, content, payment, amount }

const double _kDateW = 64; // 「06/29(月)」が収まる幅。
const double _kAmountW = 92;
const double _kColGap = 8;
const double _kHandleW = 12;
const double _kRowH = 40; // データ行の固定高さ（縦罫線をこの高さで引く）。
const double _kHeadH = 34; // ヘッダー行の固定高さ。
const Color _kGridLine = Color(0xFFEDF0F3); // 薄い縦罫線（表のセル区切り）。

/// 指定高さの縦罫線（列の区切り）。[box] の中央に1px。
Widget _vGrid(double boxWidth, double height) => SizedBox(
      width: boxWidth,
      child: Center(
        child: Container(width: 1, height: height, color: _kGridLine),
      ),
    );

class _ColW {
  final double date;
  final double major;
  final double sub;
  final double content;
  final double pay;
  final double amount;
  const _ColW({
    required this.date,
    required this.major,
    required this.sub,
    required this.content,
    required this.pay,
    required this.amount,
  });
}

class _ExpenseTableHeader extends StatelessWidget {
  final _ColW w;
  final void Function(int handleIndex, double dx) onResize;
  final VoidCallback onResizeEnd;
  final _SortCol sortCol;
  final bool asc;
  final void Function(_SortCol col) onSort;
  final Color accent;
  const _ExpenseTableHeader({
    required this.w,
    required this.onResize,
    required this.onResizeEnd,
    required this.sortCol,
    required this.asc,
    required this.onSort,
    required this.accent,
  });

  /// 並び替え可能な見出しセル（タップで切替・現在列は矢印＋アクセント色）。
  Widget _h(String s, _SortCol col, {bool right = false}) {
    final active = sortCol == col;
    final color = active ? accent : V2Colors.textMuted;
    final children = <Widget>[
      Flexible(
        child: Text(s,
            textAlign: right ? TextAlign.right : TextAlign.left,
            overflow: TextOverflow.ellipsis,
            style: V2Typography.micro
                .copyWith(color: color, fontWeight: FontWeight.w700)),
      ),
      if (active) ...[
        const SizedBox(width: 2),
        Icon(asc ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12, color: accent),
      ],
    ];
    return InkWell(
      onTap: () => onSort(col),
      child: Row(
        mainAxisAlignment:
            right ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: children,
      ),
    );
  }

  // リサイズハンドル兼・縦罫線（ヘッダー高さいっぱいの1px線をドラッグ可能に）。
  Widget _handle(int i) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onResize(i, d.delta.dx),
          onHorizontalDragEnd: (_) => onResizeEnd(),
          child: SizedBox(
            width: _kHandleW,
            height: _kHeadH,
            child: Center(
              child: Container(width: 1, height: _kHeadH, color: _kGridLine),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kHeadH,
      color: V2Colors.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: w.date, child: _h('日付', _SortCol.date)),
          _vGrid(_kColGap, _kHeadH),
          SizedBox(width: w.major, child: _h('大カテゴリ', _SortCol.major)),
          _handle(0),
          SizedBox(width: w.sub, child: _h('小カテゴリ', _SortCol.sub)),
          _handle(1),
          SizedBox(width: w.content, child: _h('内容', _SortCol.content)),
          _handle(2),
          SizedBox(width: w.pay, child: _h('支払方法', _SortCol.payment)),
          _vGrid(_kColGap, _kHeadH),
          SizedBox(
              width: w.amount, child: _h('金額', _SortCol.amount, right: true)),
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
    final accent = expenseCatColor(t.category.major);
    final major = t.category.major.trim();
    final sub = t.category.sub.trim();
    // 大カテゴリは番号プレフィックス（"1."）を外して表示。
    final majorDisplay = major.isEmpty
        ? '未分類'
        : major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
    final subDisplay = sub.isEmpty ? '—' : sub;
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (sub.isNotEmpty ? sub : (major.isNotEmpty ? major : '未分類'));
    final pay = t.paymentMethod.trim();
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _kRowH,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: w.date,
              child: _DateWithWeekday(date: t.date),
            ),
            _vGrid(_kColGap, _kRowH),
            // 大カテゴリ（色付きバッジ・アイコン無し）。
            SizedBox(
              width: w.major,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(majorDisplay,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HSLColor.fromColor(accent)
                              .withLightness(0.30)
                              .toColor())),
                ),
              ),
            ),
            _vGrid(_kHandleW, _kRowH),
            // 小カテゴリ（プレーンテキスト）。
            SizedBox(
              width: w.sub,
              child: Text(subDisplay,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 12,
                      color: sub.isEmpty
                          ? V2Colors.textMuted
                          : V2Colors.textSecondary)),
            ),
            _vGrid(_kHandleW, _kRowH),
            SizedBox(
              width: w.content,
              child: Text(title,
                  style: V2Typography.body.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
            _vGrid(_kHandleW, _kRowH),
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
            _vGrid(_kColGap, _kRowH),
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
      ),
    );
  }
}

/// 日付＋曜日（土=青 / 日=赤）。
class _DateWithWeekday extends StatelessWidget {
  final DateTime date;
  const _DateWithWeekday({required this.date});

  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final w = date.weekday; // 1=月 .. 7=日
    final label = _wd[w - 1];
    final wColor = w == 6
        ? const Color(0xFF2563EB) // 土＝青
        : w == 7
            ? const Color(0xFFDC2626) // 日＝赤
            : V2Colors.textMuted;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: formatMonthDay(date),
            style: V2Typography.micro.copyWith(
                color: V2Colors.textSecondary,
                fontFeatures: V2Typography.tabularNums)),
        TextSpan(
            text: '($label)',
            style: V2Typography.micro
                .copyWith(color: wColor, fontWeight: FontWeight.w700)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }
}

/// 狭い幅用の並び替えバー（列ラベルをタップで切替・現在列は矢印＋アクセント色）。
class _NarrowSortBar extends StatelessWidget {
  final _SortCol sortCol;
  final bool asc;
  final void Function(_SortCol col) onSort;
  final Color accent;
  const _NarrowSortBar({
    required this.sortCol,
    required this.asc,
    required this.onSort,
    required this.accent,
  });

  static const _labels = {
    _SortCol.date: '日付',
    _SortCol.major: '大カテゴリ',
    _SortCol.sub: '小カテゴリ',
    _SortCol.content: '内容',
    _SortCol.payment: '支払方法',
    _SortCol.amount: '金額',
  };

  Widget _chip(_SortCol c) {
    final active = sortCol == c;
    return InkWell(
      onTap: () => onSort(c),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_labels[c]!,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? accent : V2Colors.textMuted)),
            if (active)
              Icon(asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: accent),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (final c in _SortCol.values) _chip(c)]),
      ),
    );
  }
}

/// 狭い幅用の2行スリム行。
/// 1行目：日付(曜日)＋内容＋金額／2行目：カテゴリ＋支払方法。
class _NarrowRow extends StatelessWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  const _NarrowRow({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = expenseCatColor(t.category.major);
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1行目：日付 + 内容 + 金額
            Row(
              children: [
                _DateWithWeekday(date: t.date),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.body
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text('-${formatYen(t.amount)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: V2Colors.negative,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
            const SizedBox(height: 5),
            // 2行目：カテゴリ + 支払方法
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                const SizedBox(width: 10),
                Flexible(
                  child: Row(
                    children: [
                      Icon(_paymentIcon(pay),
                          size: 12, color: const Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(pay,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF64748B))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
