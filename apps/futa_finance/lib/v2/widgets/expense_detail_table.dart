import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/category_colors.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 制作原価のチーム別に小カテゴリ文字色を返す（該当しなければ null）。
/// YouTube事業=赤 / LINE事業=緑。
Color? _teamColor(String sub) {
  final s = sub.trim();
  if (s == 'YouTube事業') return const Color(0xFFD32F2F); // 赤
  if (s == 'LINE事業') return const Color(0xFF2E7D32); // 緑
  return null;
}

/// 明細テーブルに「実際の取引」と混ぜて並べる固定費（サブスク）の1行。
///
/// 固定費は実取引（Transaction）ではなく毎月の引落予定だが、明細を1件ずつ
/// チェックするときに「固定費が計上されているか」を同時に確認できるよう、
/// 同じ表に淡色（区別色）で混ぜて表示するための行データ。
class FixedCostRow {
  /// 元のサブスク(Subscription)のID。タップ編集時に使う。
  final String id;

  /// サービス名（例「中部電力」）。明細の「内容」列に出す。
  final String name;

  /// その月の計上額（円）。
  final int amount;

  /// 並び替え（日付）用の日付。請求日があればその日、無ければ月初。
  final DateTime date;

  /// 支払方法（任意）。
  final String? paymentMethod;

  /// 「小カテゴリ」列に出す科目/グループ名（任意・空可）。
  final String categoryLabel;

  /// 同じ日付内の手動並び順（元サブスクの sortOrder）。null は未設定。
  final double? sortOrder;

  /// この月の確認済み（検収）状態。
  final bool reviewed;

  /// 変動費で今月の金額が未入力＝「入力待ち」。金額の代わりにバッジを出す。
  final bool pending;

  const FixedCostRow({
    required this.id,
    required this.name,
    required this.amount,
    required this.date,
    this.paymentMethod,
    this.categoryLabel = '',
    this.sortOrder,
    this.reviewed = false,
    this.pending = false,
  });
}

/// 手動並び替えの結果1件（取引 or 固定費）。呼び出し側で index を sortOrder に振る。
class ReorderedItem {
  /// 取引のとき非null。
  final core.Transaction? txn;

  /// 固定費のとき、その元サブスクのID。
  final String? subscriptionId;

  const ReorderedItem.txn(this.txn) : subscriptionId = null;
  const ReorderedItem.fixed(this.subscriptionId) : txn = null;

  bool get isFixed => subscriptionId != null;
}

/// 支出明細の共通テーブル（PC幅・表形式）。
///
/// 支出タブ（rich_expenses）とクレカ詳細（card_detail）で共用。
/// 日付/カテゴリ(色)/内容/支払方法/金額の表＋検索＋並び替えバッジ＋列幅ドラッグ。
class ExpenseDetailTable extends StatefulWidget {
  /// 表示対象の取引（呼び出し側で絞り込み済み）。
  final List<core.Transaction> rows;

  /// 取引に混ぜて表示する固定費（任意）。空なら従来どおり取引のみ。
  final List<FixedCostRow> fixedRows;

  /// 固定費行タップ時（サブスク編集を開く）。fixedRows を渡すなら指定する。
  final Future<void> Function(FixedCostRow f)? onEditFixed;

  /// 行タップ時（編集を開く等）。
  final Future<void> Function(core.Transaction t) onEditTxn;

  /// アクセント色（バッジ選択色）。
  final Color accent;

  /// 見出し（例「支出明細」「明細」）。
  final String title;

  /// 0件時の補助文（検索ヒット0件は別メッセージ）。
  final String emptyHint;

  /// 領収書/レシート保存済みチェック列を出すか（事業モード・税理士提出用）。
  final bool showReceiptCheck;

  /// 証憑列の呼び名（既定「領収書」。制作原価タブでは「請求書」を渡す）。
  final String receiptLabel;

  /// 既定の並びを「小カテゴリ昇順 → 場所降順」にする（制作原価タブ用）。
  /// ヘッダーをタップして手動ソートするまではこの複合順で表示する。
  final bool defaultTeamSort;

  /// 領収書チェックの切替（保存はここで行う）。showReceiptCheck=true 時は必須。
  final Future<void> Function(core.Transaction t, bool value)? onToggleReceipt;

  /// 確認済み（検収済み）チェックの切替。指定すると金額の隣にチェック列が出る。
  /// チェックした行は薄くグレーアウトする（締め処理の確認用）。
  final Future<void> Function(core.Transaction t, bool value)? onToggleReviewed;

  /// 固定費行の確認済みチェックの切替（月別）。
  final Future<void> Function(FixedCostRow f, bool value)? onToggleReviewedFixed;

  /// 手動並び替えの保存。指定するとヘッダーに「手で並び替え」トグルが出る。
  /// 引数はその日の項目（取引・固定費）を新しい上→下の順に並べたリスト
  /// （呼び出し側で index を sortOrder として振って保存する）。
  final Future<void> Function(List<ReorderedItem> dayInNewOrder)?
      onReorderDay;

  const ExpenseDetailTable({
    super.key,
    required this.rows,
    required this.onEditTxn,
    required this.accent,
    this.fixedRows = const [],
    this.onEditFixed,
    this.title = '明細',
    this.emptyHint = '記録はまだありません',
    this.showReceiptCheck = false,
    this.receiptLabel = '領収書',
    this.defaultTeamSort = false,
    this.onToggleReceipt,
    this.onToggleReviewed,
    this.onToggleReviewedFixed,
    this.onReorderDay,
  });

  @override
  State<ExpenseDetailTable> createState() => _ExpenseDetailTableState();
}

class _ExpenseDetailTableState extends State<ExpenseDetailTable> {
  // 列幅（中央6列＝大カテゴリ/小カテゴリ/内容/場所/支払方法/金額 の配分・合計1.0）。
  // 各境界をドラッグで調整できる。端末保存。
  List<double> _colFrac = const [0.14, 0.15, 0.24, 0.16, 0.15, 0.16];
  static const _kColFracKey = 'futa.exp_table_col_frac_v4';
  static const _kColCount = 6;

  // 並び替えは表ヘッダーのクリックで列＋昇順/降順を切替。
  _SortCol _sortCol = _SortCol.date;
  bool _asc = false; // 日付は既定で降順（新しい順）。
  // ユーザーが一度でも並び替えを操作したか。既定（日付順）のうちは矢印を出さない。
  bool _sortTouched = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// 決済手段の絞り込み（null = すべて表示）。
  String? _payFilter;

  /// ヘッダークリック：同じ列なら昇順/降順をトグル、別列なら列を切替（既定向き）。
  void _onSort(_SortCol col) {
    setState(() {
      _sortTouched = true;
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

  List<_Row> _sortFilter() {
    final rows = <_Row>[
      ...widget.rows.map(_Row.txn),
      ...widget.fixedRows.map(_Row.fixed),
    ];
    // 全角数字（１２３）でも金額検索できるよう半角化してから照合する。
    final q = _normalizeDigits(_query).trim().toLowerCase();
    var list =
        q.isEmpty ? rows : rows.where((r) => r.searchHay.contains(q)).toList();
    if (_payFilter != null) {
      list = list.where((r) => r.payKey == _payFilter).toList();
    }
    // 制作原価タブの既定：小カテゴリ（チーム）昇順 → 場所（工程）降順の複合順。
    // ヘッダーを一度でもタップしたら通常の単一列ソートへ切り替わる。
    if (widget.defaultTeamSort && !_sortTouched) {
      list.sort((a, b) {
        final c = a.subText.compareTo(b.subText); // 小カテゴリ昇順
        if (c != 0) return c;
        return b.placeText.compareTo(a.placeText); // 場所降順
      });
      return list;
    }
    int cmp;
    switch (_sortCol) {
      case _SortCol.date:
        // 手動並び順(sortOrder)を最優先＝月内で自由に並べた順を保持。
        // 未設定(null)の行は日付降順（新しい順）で、手動順の行より上に置く。
        list.sort((a, b) {
          final ao = a.manualOrder, bo = b.manualOrder;
          if (ao == null && bo == null) {
            final c = a.date.compareTo(b.date);
            return _asc ? c : -c; // 既定は降順（新しい順）
          }
          if (ao == null) return -1; // 未設定（新規）は上へ
          if (bo == null) return 1;
          return ao.compareTo(bo); // 手動順（上→下）
        });
        return list;
      case _SortCol.amount:
        list.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case _SortCol.major:
        list.sort((a, b) {
          cmp = a.majorOrder.compareTo(b.majorOrder);
          if (cmp != 0) return cmp;
          return a.subText.compareTo(b.subText);
        });
        break;
      case _SortCol.sub:
        list.sort((a, b) {
          cmp = a.subText.compareTo(b.subText);
          if (cmp != 0) return cmp;
          return a.majorOrder.compareTo(b.majorOrder);
        });
        break;
      case _SortCol.content:
        list.sort((a, b) => a.contentText.compareTo(b.contentText));
        break;
      case _SortCol.place:
        list.sort((a, b) => a.placeText.compareTo(b.placeText));
        break;
      case _SortCol.payment:
        list.sort((a, b) => a.paymentText.compareTo(b.paymentText));
        break;
    }
    if (!_asc) {
      list = list.reversed.toList();
    }
    return list;
  }

  /// 決済手段の選択肢（件数の多い順）。取引＋固定費の両方から集計。
  List<({String key, int count})> _payOptions() {
    final all = <_Row>[
      ...widget.rows.map(_Row.txn),
      ...widget.fixedRows.map(_Row.fixed),
    ];
    final counts = <String, int>{};
    for (final r in all) {
      counts[r.payKey] = (counts[r.payKey] ?? 0) + 1;
    }
    final list =
        counts.entries.map((e) => (key: e.key, count: e.value)).toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final detailRows = _sortFilter();
    final payOptions = _payOptions();
    // 絞り込み中の決済手段が選択肢から消えたら（データ変化など）解除する。
    if (_payFilter != null &&
        !payOptions.any((o) => o.key == _payFilter)) {
      _payFilter = null;
    }
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
            Text(
                widget.onReorderDay != null
                    ? '行の右端をドラッグで並び替え'
                    : 'ヘッダーをタップで並び替え',
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textMuted)),
          ],
        ),
        const SizedBox(height: V2Spacing.sm),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: '内容・カテゴリ・支払方法・金額で検索',
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
        // 決済手段でしぼり込み（2種類以上あるときだけ表示）。
        if (payOptions.length >= 2) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PayChip(
                  label: 'すべて',
                  icon: Icons.apps,
                  selected: _payFilter == null,
                  accent: widget.accent,
                  onTap: () => setState(() => _payFilter = null),
                ),
                for (final o in payOptions) ...[
                  const SizedBox(width: 6),
                  _PayChip(
                    label: '${o.key}（${o.count}）',
                    icon: _paymentIcon(o.key),
                    selected: _payFilter == o.key,
                    accent: widget.accent,
                    onTap: () => setState(() => _payFilter = o.key),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.sm),
        ],
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
                      touched: _sortTouched,
                    ),
                    _reorderableRows(
                      detailRows,
                      (r) => r.isFixed
                          ? _NarrowFixedRow(
                              f: r.fx!,
                              onTap: () => widget.onEditFixed?.call(r.fx!),
                              showReceipt: widget.showReceiptCheck,
                              showReview:
                                  widget.onToggleReviewedFixed != null,
                              onToggleReviewed: widget.onToggleReviewedFixed,
                            )
                          : _NarrowRow(
                              t: r.txn!,
                              onTap: () => widget.onEditTxn(r.txn!),
                              showReceipt: widget.showReceiptCheck,
                              onToggleReceipt: widget.onToggleReceipt,
                              showReview: widget.onToggleReviewed != null,
                              onToggleReviewed: widget.onToggleReviewed,
                            ),
                    ),
                  ],
                );
              }
              final innerW = cons.maxWidth - 24;
              final showReview = widget.onToggleReviewed != null ||
                  widget.onToggleReviewedFixed != null;
              final receiptExtra =
                  widget.showReceiptCheck ? (_kReceiptW + _kColGap) : 0.0;
              final reviewExtra =
                  showReview ? (_kReviewW + _kColGap) : 0.0;
              // 中央6列。固定は date ＋ date|major の隙間 ＋ ハンドル5本。
              final fixed = _kDateW +
                  _kColGap +
                  _kHandleW * 5 +
                  receiptExtra +
                  reviewExtra;
              final mw = (innerW - fixed) < 240 ? 240.0 : innerW - fixed;
              final w = _ColW(
                date: _kDateW,
                major: _colFrac[0] * mw,
                sub: _colFrac[1] * mw,
                content: _colFrac[2] * mw,
                place: _colFrac[3] * mw,
                pay: _colFrac[4] * mw,
                amount: _colFrac[5] * mw,
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
                    showReceipt: widget.showReceiptCheck,
                    showReview: showReview,
                    touched: _sortTouched,
                    receiptLabel: widget.receiptLabel,
                  ),
                  _reorderableRows(
                    detailRows,
                    (r) => r.isFixed
                        ? _FixedRow(
                            f: r.fx!,
                            onTap: () => widget.onEditFixed?.call(r.fx!),
                            w: w,
                            showReceipt: widget.showReceiptCheck,
                            showReview: showReview,
                            onToggleReviewed: widget.onToggleReviewedFixed,
                          )
                        : _ExpenseRow(
                            t: r.txn!,
                            onTap: () => widget.onEditTxn(r.txn!),
                            w: w,
                            showReceipt: widget.showReceiptCheck,
                            onToggleReceipt: widget.onToggleReceipt,
                            showReview: showReview,
                            onToggleReviewed: widget.onToggleReviewed,
                          ),
                  ),
                ],
              );
            }),
          ),
      ],
    );
  }

  /// 明細行リスト。並び替え可能なら ReorderableListView。ハンドルは出さず、
  /// **行を長押し（PCは押し続け）でドラッグ**して並び替える（タップは詳細を開く）。
  /// 列ソート中など不可のときは通常の縦積み。
  Widget _reorderableRows(List<_Row> rows, Widget Function(_Row r) build) {
    final canReorder =
        widget.onReorderDay != null && _sortCol == _SortCol.date;
    if (!canReorder) {
      return Column(
        children: [
          for (final r in rows) ...[
            const Divider(height: 1, color: V2Colors.divider),
            build(r),
          ],
        ],
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false, // 見えるハンドルは出さない
      itemCount: rows.length,
      onReorder: (oldIndex, newIndex) => _onReorder(oldIndex, newIndex, rows),
      itemBuilder: (ctx, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(rows[i].keyId),
        index: i,
        child: Column(
          children: [
            const Divider(height: 1, color: V2Colors.divider),
            build(rows[i]),
          ],
        ),
      ),
    );
  }

  /// ドラッグで並べ替えた結果を、月内の並び順(sortOrder)として保存する。
  void _onReorder(int oldIndex, int newIndex, List<_Row> rows) {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = [...rows];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    widget.onReorderDay?.call([
      for (final r in list)
        r.isFixed ? ReorderedItem.fixed(r.fx!.id) : ReorderedItem.txn(r.txn!),
    ]);
  }

}

/// 全角数字（０-９）と全角カンマ／円記号を半角へ正規化する。
/// 検索で「１３０４」や「¥1,304」を「1304」と同じに扱えるようにするため。
String _normalizeDigits(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF10 && r <= 0xFF19) {
      buf.writeCharCode(r - 0xFF10 + 0x30); // 全角0-9 → 半角
    } else if (r == 0xFF0C) {
      buf.writeCharCode(0x2C); // 全角カンマ → 半角
    } else if (r == 0xFFE5) {
      buf.writeCharCode(0xA5); // 全角￥ → 半角¥
    } else {
      buf.writeCharCode(r);
    }
  }
  return buf.toString();
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
enum _SortCol { date, major, sub, content, place, payment, amount }

/// 取引行 or 固定費行を統一して扱う内部ラッパ（並び替え・検索を共通化）。
class _Row {
  final core.Transaction? txn;
  final FixedCostRow? fx;
  _Row.txn(this.txn) : fx = null;
  _Row.fixed(this.fx) : txn = null;

  bool get isFixed => fx != null;

  /// ReorderableListView 用の一意キー。
  String get keyId => txn != null ? 'tx_${txn!.id}' : 'fx_${fx!.id}';

  /// 手動並び順（生の sortOrder。未設定は null）。月内フリー並び替えに使う。
  double? get manualOrder => txn != null ? txn!.sortOrder : fx!.sortOrder;

  DateTime get date => txn?.date ?? fx!.date;
  int get amount => txn?.amount ?? fx!.amount;

  /// 同じ日付内の並び順キー。手動並び替え(sortOrder)を最優先。
  /// 未設定は、固定費は先頭側（-∞）／取引は末尾側（+∞）に寄せる。
  double get orderKey {
    if (isFixed) return fx!.sortOrder ?? double.negativeInfinity;
    return txn!.sortOrder ?? double.infinity;
  }

  /// 大カテゴリ並び順。固定費は末尾側に寄せる（取引の後）。
  int get majorOrder => txn?.category.majorOrder ?? (1 << 20);

  String get subText => txn != null ? txn!.category.sub : fx!.categoryLabel;

  String get contentText => txn != null
      ? (txn!.description.trim().isNotEmpty
          ? txn!.description.trim()
          : txn!.category.sub)
      : fx!.name;

  String get paymentText =>
      (txn?.paymentMethod ?? fx!.paymentMethod ?? '').trim();

  /// 「場所」列の文字。固定費は場所なし。
  String get placeText => txn != null ? (txn!.store ?? '').trim() : '';

  /// 決済手段フィルタ用のキー（空は「未設定」）。
  String get payKey => paymentText.isEmpty ? '未設定' : paymentText;

  String get searchHay => (txn != null
          ? [
              txn!.description,
              txn!.category.major,
              txn!.category.sub,
              txn!.paymentMethod,
              txn!.memo ?? '',
              txn!.store ?? '',
              // 金額でも検索可（カンマ無し「420」も ¥付き「¥4,200」も両対応）。
              amount.toString(),
              formatYen(amount),
            ]
          : [
              fx!.name,
              fx!.categoryLabel,
              fx!.paymentMethod ?? '',
              '固定費',
              amount.toString(),
              formatYen(amount),
            ])
      .join(' ')
      .toLowerCase();
}

/// 固定費行の見た目（取引と区別するための淡いアンバー系）。
const Color _kFixedBg = Color(0xFFFFF8EC); // 行の淡い背景
const Color _kFixedBadgeBg = Color(0xFFFBE3BE); // 「固定費」バッジ背景
const Color _kFixedAccent = Color(0xFFB45309); // 「固定費」バッジ文字・金額

const double _kDateW = 64; // 「06/29(月)」が収まる幅。
const double _kColGap = 8;
const double _kHandleW = 12;
const double _kReceiptW = 56; // 領収書チェック列の幅（事業モード）。
const double _kReviewW = 44; // 確認済みチェック列の幅。
const Color _kReviewedBg = Color(0xFFF3F4F6); // 確認済み行のグレー背景。
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
  final double place;
  final double pay;
  final double amount;
  const _ColW({
    required this.date,
    required this.major,
    required this.sub,
    required this.content,
    required this.place,
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
  final bool showReceipt;
  final bool showReview;
  final bool touched;
  final String receiptLabel;
  const _ExpenseTableHeader({
    required this.w,
    required this.onResize,
    required this.onResizeEnd,
    required this.sortCol,
    required this.asc,
    required this.onSort,
    required this.accent,
    this.showReceipt = false,
    this.showReview = false,
    this.touched = false,
    this.receiptLabel = '領収書',
  });

  /// 並び替え可能な見出しセル（タップで切替）。既定（未操作）のうちは矢印も
  /// アクセント色も出さず、ヘッダーをタップしてから現在列を強調する。
  Widget _h(String s, _SortCol col, {bool right = false}) {
    final active = sortCol == col && touched;
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
      // ヘッダーはアクセント色の淡いトーンで色付け（表らしく見やすく）。
      color: Color.alphaBlend(accent.withValues(alpha: 0.12), Colors.white),
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
          SizedBox(width: w.place, child: _h('場所', _SortCol.place)),
          _handle(3),
          SizedBox(width: w.pay, child: _h('支払方法', _SortCol.payment)),
          _handle(4),
          SizedBox(
              width: w.amount, child: _h('金額', _SortCol.amount, right: true)),
          // 事業モードは「領収書 → 確認」の順で並べる。
          if (showReceipt) ...[
            _vGrid(_kColGap, _kHeadH),
            SizedBox(
              width: _kReceiptW,
              child: Text(receiptLabel,
                  textAlign: TextAlign.center,
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textMuted,
                      fontWeight: FontWeight.w700)),
            ),
          ],
          if (showReview) ...[
            _vGrid(_kColGap, _kHeadH),
            SizedBox(
              width: _kReviewW,
              child: Text('確認',
                  textAlign: TextAlign.center,
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textMuted,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  final _ColW w;
  final bool showReceipt;
  final Future<void> Function(core.Transaction t, bool value)? onToggleReceipt;
  final bool showReview;
  final Future<void> Function(core.Transaction t, bool value)? onToggleReviewed;
  const _ExpenseRow({
    required this.t,
    required this.onTap,
    required this.w,
    this.showReceipt = false,
    this.onToggleReceipt,
    this.showReview = false,
    this.onToggleReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final reviewed = t.reviewed;
    // 固定費は従来どおりオレンジ系で色分け＋淡い背景（実取引化しても見た目を保つ）。
    final isFixedCat = t.category.major.contains('固定費');
    final accent =
        isFixedCat ? _kFixedAccent : expenseCatColor(t.category.major);
    final major = t.category.major.trim();
    final sub = t.category.sub.trim();
    // 大カテゴリは番号プレフィックス（"1."）を外して表示。
    final majorDisplay = major.isEmpty
        ? '未分類'
        : major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
    final subDisplay = sub.isEmpty ? '—' : sub;
    // 制作原価のチーム別に色分け（YouTube事業=赤 / LINE事業=緑）。
    final subColor = _teamColor(sub) ??
        (sub.isEmpty ? V2Colors.textMuted : V2Colors.textSecondary);
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (sub.isNotEmpty ? sub : (major.isNotEmpty ? major : '未分類'));
    final pay = t.paymentMethod.trim();
    return InkWell(
      onTap: onTap,
      child: Container(
        height: _kRowH,
        // 確認済み=グレー背景 / 固定費=淡いオレンジ背景（それ以外は無し）。
        color: reviewed
            ? _kReviewedBg
            : (isFixedCat ? _kFixedBg : null),
        child: Opacity(
        opacity: reviewed ? 0.5 : 1,
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
                      fontWeight: _teamColor(sub) != null
                          ? FontWeight.w700
                          : FontWeight.normal,
                      color: subColor)),
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
            // 場所（店舗）。
            SizedBox(
              width: w.place,
              child: Text(
                  (t.store ?? '').trim().isEmpty ? '—' : t.store!.trim(),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 12,
                      color: (t.store ?? '').trim().isEmpty
                          ? V2Colors.textMuted
                          : V2Colors.textSecondary)),
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
            _vGrid(_kHandleW, _kRowH),
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
            if (showReceipt) ...[
              _vGrid(_kColGap, _kRowH),
              SizedBox(
                width: _kReceiptW,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: t.receiptSaved,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF16A34A),
                      onChanged: onToggleReceipt == null
                          ? null
                          : (v) => onToggleReceipt!(t, v ?? false),
                    ),
                  ),
                ),
              ),
            ],
            if (showReview) ...[
              _vGrid(_kColGap, _kRowH),
              SizedBox(
                width: _kReviewW,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: reviewed,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF6B7280),
                      onChanged: onToggleReviewed == null
                          ? null
                          : (v) => onToggleReviewed!(t, v ?? false),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
        ),
      ),
    );
  }
}

/// 固定費の1行（PC幅）。取引行と同じ列割りだが、淡いアンバー背景＋
/// 先頭に「固定費」バッジを付けて、ひと目で区別できるようにする。
class _FixedRow extends StatelessWidget {
  final FixedCostRow f;
  final VoidCallback onTap;
  final _ColW w;
  final bool showReceipt;
  final bool showReview;
  final Future<void> Function(FixedCostRow f, bool value)? onToggleReviewed;
  const _FixedRow({
    required this.f,
    required this.onTap,
    required this.w,
    this.showReceipt = false,
    this.showReview = false,
    this.onToggleReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final cat = f.categoryLabel.trim();
    final reviewed = f.reviewed;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: _kRowH,
        // 確認済みはグレー背景（固定費のアンバーより優先）。
        color: reviewed ? _kReviewedBg : _kFixedBg,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Opacity(
        opacity: reviewed ? 0.5 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: w.date, child: _DateWithWeekday(date: f.date)),
            _vGrid(_kColGap, _kRowH),
            // 大カテゴリ列：常に「固定費」バッジ（区別色）。
            SizedBox(
              width: w.major,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kFixedBadgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_repeat, size: 12, color: _kFixedAccent),
                      SizedBox(width: 4),
                      Text('固定費',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _kFixedAccent)),
                    ],
                  ),
                ),
              ),
            ),
            _vGrid(_kHandleW, _kRowH),
            // 小カテゴリ列：科目/グループ（あれば）。
            SizedBox(
              width: w.sub,
              child: Text(cat.isEmpty ? '—' : cat,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 12,
                      color: cat.isEmpty
                          ? V2Colors.textMuted
                          : V2Colors.textSecondary)),
            ),
            _vGrid(_kHandleW, _kRowH),
            SizedBox(
              width: w.content,
              child: Text(f.name,
                  style: V2Typography.body.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
            _vGrid(_kHandleW, _kRowH),
            // 場所（固定費は無し）。
            SizedBox(
              width: w.place,
              child: const Text('—',
                  style: TextStyle(fontSize: 12, color: V2Colors.textMuted)),
            ),
            _vGrid(_kHandleW, _kRowH),
            SizedBox(
              width: w.pay,
              child: Row(
                children: [
                  Icon(_paymentIcon(f.paymentMethod ?? ''),
                      size: 13, color: const Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        (f.paymentMethod ?? '').trim().isEmpty
                            ? '—'
                            : f.paymentMethod!.trim(),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B))),
                  ),
                ],
              ),
            ),
            _vGrid(_kHandleW, _kRowH),
            SizedBox(
              width: w.amount,
              child: f.pending
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('入力待ち',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB45309))),
                      ),
                    )
                  : Text('-${formatYen(f.amount)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kFixedAccent,
                          fontFeatures: V2Typography.tabularNums)),
            ),
            if (showReceipt) ...[
              _vGrid(_kColGap, _kRowH),
              // 固定費に領収書チェックは無い（予定なので「—」）。
              const SizedBox(
                width: _kReceiptW,
                child: Center(
                  child: Text('—',
                      style: TextStyle(
                          fontSize: 13, color: V2Colors.textMuted)),
                ),
              ),
            ],
            if (showReview) ...[
              _vGrid(_kColGap, _kRowH),
              SizedBox(
                width: _kReviewW,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: reviewed,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF6B7280),
                      onChanged: onToggleReviewed == null
                          ? null
                          : (v) => onToggleReviewed!(f, v ?? false),
                    ),
                  ),
                ),
              ),
            ],
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
  final bool touched;
  const _NarrowSortBar({
    required this.sortCol,
    required this.asc,
    required this.onSort,
    required this.accent,
    this.touched = false,
  });

  static const _labels = {
    _SortCol.date: '日付',
    _SortCol.major: '大カテゴリ',
    _SortCol.sub: '小カテゴリ',
    _SortCol.content: '内容',
    _SortCol.place: '場所',
    _SortCol.payment: '支払方法',
    _SortCol.amount: '金額',
  };

  Widget _chip(_SortCol c) {
    final active = sortCol == c && touched;
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
  final bool showReceipt;
  final Future<void> Function(core.Transaction t, bool value)? onToggleReceipt;
  final bool showReview;
  final Future<void> Function(core.Transaction t, bool value)? onToggleReviewed;
  const _NarrowRow({
    required this.t,
    required this.onTap,
    this.showReceipt = false,
    this.onToggleReceipt,
    this.showReview = false,
    this.onToggleReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final reviewed = t.reviewed;
    // 固定費は従来どおりオレンジ系で色分け＋淡い背景（実取引化しても見た目を保つ）。
    final isFixedCat = t.category.major.contains('固定費');
    final accent =
        isFixedCat ? _kFixedAccent : expenseCatColor(t.category.major);
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
      child: Container(
        color: reviewed
            ? _kReviewedBg
            : (isFixedCat ? _kFixedBg : null),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Opacity(
        opacity: reviewed ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1行目：日付 + 内容 + 金額（＋確認チェック）
            Row(
              children: [
                if (showReview) ...[
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: reviewed,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF6B7280),
                      onChanged: onToggleReviewed == null
                          ? null
                          : (v) => onToggleReviewed!(t, v ?? false),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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
                if (showReceipt) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: t.receiptSaved,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF16A34A),
                      onChanged: onToggleReceipt == null
                          ? null
                          : (v) => onToggleReceipt!(t, v ?? false),
                    ),
                  ),
                ],
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
                if ((t.store ?? '').trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(t.store!.trim(),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF64748B))),
                        ),
                      ],
                    ),
                  ),
                ],
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
      ),
    );
  }
}

/// 狭い幅用の固定費2行スリム行（淡いアンバー背景＋「固定費」バッジ）。
class _NarrowFixedRow extends StatelessWidget {
  final FixedCostRow f;
  final VoidCallback onTap;
  final bool showReceipt;
  final bool showReview;
  final Future<void> Function(FixedCostRow f, bool value)? onToggleReviewed;
  const _NarrowFixedRow({
    required this.f,
    required this.onTap,
    this.showReceipt = false,
    this.showReview = false,
    this.onToggleReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final cat = f.categoryLabel.trim();
    final pay = (f.paymentMethod ?? '').trim();
    final reviewed = f.reviewed;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: reviewed ? _kReviewedBg : _kFixedBg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Opacity(
        opacity: reviewed ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1行目：（確認）日付 + 内容 + 金額
            Row(
              children: [
                if (showReview) ...[
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: reviewed,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF6B7280),
                      onChanged: onToggleReviewed == null
                          ? null
                          : (v) => onToggleReviewed!(f, v ?? false),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                _DateWithWeekday(date: f.date),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.body
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                if (f.pending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('入力待ち',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309))),
                  )
                else
                  Text('-${formatYen(f.amount)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kFixedAccent,
                          fontFeatures: V2Typography.tabularNums)),
              ],
            ),
            const SizedBox(height: 5),
            // 2行目：固定費バッジ + 科目 + 支払方法
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kFixedBadgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_repeat, size: 12, color: _kFixedAccent),
                      SizedBox(width: 4),
                      Text('固定費',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _kFixedAccent)),
                    ],
                  ),
                ),
                if (cat.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(cat,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 12, color: V2Colors.textSecondary)),
                  ),
                ],
                if (pay.isNotEmpty) ...[
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
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// 決済手段の絞り込みチップ（横スクロール）。選択中はアクセント色。
class _PayChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _PayChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? Color.alphaBlend(accent.withValues(alpha: 0.16), Colors.white)
        : V2Colors.surface;
    final fg = selected ? accent : V2Colors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? accent : V2Colors.border,
              width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}
