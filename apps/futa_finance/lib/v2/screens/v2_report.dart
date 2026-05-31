import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/transaction_repository.dart';
import '../../screens/report_screen.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// 損益計算書（PL）の大カテゴリ分類。
enum _PLCategory {
  sales,
  cogs,
  sga,
  nonOpIncome,
  nonOpExpense,
  extraIncome,
  extraExpense,
  tax,
  other,
}

/// PL テーブルの行種別。
enum _RowKind {
  /// 通常データ行（売上高・売上原価など、大区分の合計）
  data,

  /// 内訳行（販管費の中の「役員報酬」など、インデント表示）
  detail,

  /// 小計行（粗利・営業利益など、黄色背景でハイライト）
  subtotal,

  /// 最終利益（当期純利益、強ハイライト）
  emphasize,
}

/// 販売管理費の標準的な勘定科目（順序固定）。
/// Transaction.category.major でこれに完全一致するものを各内訳として集計。
/// リストにない販管費カテゴリは「その他販管費」に集約する。
const List<String> _sgaItems = [
  '役員報酬',
  '給与',
  '雑給与',
  '賞与・退職金',
  '法定福利費',
  '福利厚生費',
  '広告宣伝費',
  '交際費',
  '会議費',
  '旅費交通費',
  '通信費',
  '消耗品費',
  '修繕費',
  '水道光熱費',
  '新聞図書費',
  '諸会費',
  '支払手数料',
  '賃借料',
  '保険料',
  '租税公課',
  '支払報酬',
  '減価償却費',
  '雑費',
];

/// 営業外収益の標準科目。
const List<String> _nonOpIncomeItems = [
  '受取利息',
  '受取配当金',
  '雑収入',
];

/// 営業外費用の標準科目。
const List<String> _nonOpExpenseItems = [
  '支払利息',
  '雑損失',
];

/// v2.1 集計タブ：会計風月次表（PL）。
class V2ReportScreen extends StatefulWidget {
  final Color accent;
  const V2ReportScreen({super.key, required this.accent});

  @override
  State<V2ReportScreen> createState() => _V2ReportScreenState();
}

class _V2ReportScreenState extends State<V2ReportScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  bool _loading = true;

  final int _fyStartMonth = 6;
  late int _fyYear = _calcFyYear();

  int _calcFyYear() {
    final now = DateTime.now();
    return now.month >= _fyStartMonth ? now.year : now.year - 1;
  }

  @override
  void onModeChanged() => _load();

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

  /// 大カテゴリ分類。
  /// 法人税等の判定は major の完全一致のみ（租税公課は販管費）。
  _PLCategory _classify(core.Transaction t) {
    final major = t.category.major.trim();
    if (t.type == core.TransactionType.income) {
      if (major.contains('特別')) return _PLCategory.extraIncome;
      if (_nonOpIncomeItems.contains(major) ||
          major.contains('営業外')) {
        return _PLCategory.nonOpIncome;
      }
      return _PLCategory.sales;
    }
    if (t.type == core.TransactionType.expense) {
      // 法人税等は完全一致のみ（"租税公課" は販管費に残す）
      if (major == '法人税等' ||
          major == '法人税' ||
          major == '住民税' ||
          major == '事業税' ||
          major == '所得税') {
        return _PLCategory.tax;
      }
      if (major.contains('特別')) return _PLCategory.extraExpense;
      if (_nonOpExpenseItems.contains(major) ||
          major.contains('営業外')) {
        return _PLCategory.nonOpExpense;
      }
      if (major.contains('原価') || major.contains('仕入')) {
        return _PLCategory.cogs;
      }
      return _PLCategory.sga;
    }
    return _PLCategory.other;
  }

  /// 事業年度の各月（12 件）
  List<DateTime> get _fyMonths => List.generate(12, (i) {
        final m = _fyStartMonth + i;
        final y = _fyYear + (m > 12 ? 1 : 0);
        final mm = m > 12 ? m - 12 : m;
        return DateTime(y, mm);
      });

  /// 指定大カテゴリの月次集計
  List<int> _monthlyForCategory(_PLCategory c) {
    final months = _fyMonths;
    final result = List<int>.filled(12, 0);
    for (final t in _transactions) {
      if (_classify(t) != c) continue;
      final idx = months.indexWhere(
          (m) => m.year == t.date.year && m.month == t.date.month);
      if (idx < 0) continue;
      result[idx] += t.amount;
    }
    return result;
  }

  /// 指定大カテゴリ × 指定 major の月次集計
  List<int> _monthlyForItem(_PLCategory c, String major) {
    final months = _fyMonths;
    final result = List<int>.filled(12, 0);
    for (final t in _transactions) {
      if (_classify(t) != c) continue;
      if (t.category.major.trim() != major) continue;
      final idx = months.indexWhere(
          (m) => m.year == t.date.year && m.month == t.date.month);
      if (idx < 0) continue;
      result[idx] += t.amount;
    }
    return result;
  }

  /// 指定大カテゴリの「リストに無い」内訳の major リスト（出現順）
  List<String> _unlistedMajors(
      _PLCategory c, List<String> knownItems) {
    final seen = <String>{};
    final list = <String>[];
    for (final t in _transactions) {
      if (_classify(t) != c) continue;
      final major = t.category.major.trim();
      if (major.isEmpty) continue;
      if (knownItems.contains(major)) continue;
      if (seen.add(major)) list.add(major);
    }
    return list;
  }

  void _shiftYear(int delta) {
    setState(() => _fyYear += delta);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final months = _fyMonths;
    final rows = _buildRows();
    final fyEndYear = _fyYear + 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V2Card(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.table_chart_outlined,
                          size: 18, color: widget.accent),
                      const SizedBox(width: V2Spacing.sm),
                      Text('会計風 月次表（PL）',
                          style: V2Typography.h2),
                      const SizedBox(width: V2Spacing.sm),
                      Text('← 横スクロール →',
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.textMuted)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        onPressed: () => _shiftYear(-1),
                      ),
                      Text(
                        '$_fyYear 年度（$_fyStartMonth月〜$fyEndYear年5月）',
                        style: V2Typography.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: V2Colors.textPrimary),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        onPressed: () => _shiftYear(1),
                      ),
                    ],
                  ),
                ),
                _PLTable(months: months, rows: rows),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
          V2Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PL カテゴリ判定',
                    style: V2Typography.bodyStrong.copyWith(
                        color: V2Colors.textPrimary)),
                const SizedBox(height: V2Spacing.sm),
                Text(
                  '・通常 income → 売上高\n'
                  '・「原価」「仕入」を含む expense → 売上原価\n'
                  '・「営業外」or 受取利息/受取配当金/雑収入 → 営業外収益\n'
                  '・「営業外」or 支払利息/雑損失 → 営業外費用\n'
                  '・「特別」を含む → 特別利益 / 損失\n'
                  '・法人税 / 住民税 / 事業税 / 所得税（完全一致） → 法人税等\n'
                  '・上記以外の expense → 販売管理費（内訳は標準勘定科目で表示）',
                  style: V2Typography.caption,
                ),
                const SizedBox(height: V2Spacing.md),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ReportScreen()),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text(
                      'v1 集計画面（カテゴリ別/月末締め）を開く'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// PL テーブルの行リストを構築
  List<_PLRow> _buildRows() {
    final salesMonthly = _monthlyForCategory(_PLCategory.sales);
    final cogsMonthly = _monthlyForCategory(_PLCategory.cogs);
    final sgaMonthly = _monthlyForCategory(_PLCategory.sga);
    final nonOpIncomeMonthly =
        _monthlyForCategory(_PLCategory.nonOpIncome);
    final nonOpExpenseMonthly =
        _monthlyForCategory(_PLCategory.nonOpExpense);
    final extraIncomeMonthly =
        _monthlyForCategory(_PLCategory.extraIncome);
    final extraExpenseMonthly =
        _monthlyForCategory(_PLCategory.extraExpense);
    final taxMonthly = _monthlyForCategory(_PLCategory.tax);

    final gross = _diff(salesMonthly, cogsMonthly);
    final oper = _diff(gross, sgaMonthly);
    final ord = _addSub(oper, nonOpIncomeMonthly, nonOpExpenseMonthly);
    final preTax =
        _addSub(ord, extraIncomeMonthly, extraExpenseMonthly);
    final net = _diff(preTax, taxMonthly);

    final unlistedSga = _unlistedMajors(_PLCategory.sga, _sgaItems);
    final unlistedNonOpIn =
        _unlistedMajors(_PLCategory.nonOpIncome, _nonOpIncomeItems);
    final unlistedNonOpEx =
        _unlistedMajors(_PLCategory.nonOpExpense, _nonOpExpenseItems);

    final rows = <_PLRow>[];

    // ── 売上 ──
    rows.add(_PLRow(
        label: '売上高', monthly: salesMonthly, kind: _RowKind.data));
    rows.add(_PLRow(
        label: '売上原価', monthly: cogsMonthly, kind: _RowKind.data));
    rows.add(_PLRow(
        label: '売上総利益', monthly: gross, kind: _RowKind.subtotal));

    // ── 販管費（内訳付き） ──
    for (final item in _sgaItems) {
      rows.add(_PLRow(
        label: item,
        monthly: _monthlyForItem(_PLCategory.sga, item),
        kind: _RowKind.detail,
      ));
    }
    for (final item in unlistedSga) {
      rows.add(_PLRow(
        label: '$item（その他）',
        monthly: _monthlyForItem(_PLCategory.sga, item),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '販管費 合計', monthly: sgaMonthly, kind: _RowKind.data));
    rows.add(_PLRow(
        label: '営業利益', monthly: oper, kind: _RowKind.subtotal));

    // ── 営業外収益 ──
    for (final item in _nonOpIncomeItems) {
      rows.add(_PLRow(
        label: item,
        monthly: _monthlyForItem(_PLCategory.nonOpIncome, item),
        kind: _RowKind.detail,
      ));
    }
    for (final item in unlistedNonOpIn) {
      rows.add(_PLRow(
        label: '$item（その他）',
        monthly: _monthlyForItem(_PLCategory.nonOpIncome, item),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '営業外収益 合計',
        monthly: nonOpIncomeMonthly,
        kind: _RowKind.data));

    // ── 営業外費用 ──
    for (final item in _nonOpExpenseItems) {
      rows.add(_PLRow(
        label: item,
        monthly: _monthlyForItem(_PLCategory.nonOpExpense, item),
        kind: _RowKind.detail,
      ));
    }
    for (final item in unlistedNonOpEx) {
      rows.add(_PLRow(
        label: '$item（その他）',
        monthly: _monthlyForItem(_PLCategory.nonOpExpense, item),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '営業外費用 合計',
        monthly: nonOpExpenseMonthly,
        kind: _RowKind.data));

    rows.add(_PLRow(
        label: '経常利益', monthly: ord, kind: _RowKind.subtotal));

    // ── 特別利益 / 損失 ──
    rows.add(_PLRow(
        label: '特別利益',
        monthly: extraIncomeMonthly,
        kind: _RowKind.data));
    rows.add(_PLRow(
        label: '特別損失',
        monthly: extraExpenseMonthly,
        kind: _RowKind.data));

    rows.add(_PLRow(
        label: '税引前当期純利益',
        monthly: preTax,
        kind: _RowKind.subtotal));

    // ── 法人税等 ──
    rows.add(_PLRow(
        label: '法人税等', monthly: taxMonthly, kind: _RowKind.data));

    rows.add(_PLRow(
        label: '当期純利益', monthly: net, kind: _RowKind.emphasize));

    return rows;
  }

  /// 配列同士の差分（同じ index 同士）
  List<int> _diff(List<int> a, List<int> b) =>
      List.generate(12, (i) => a[i] - b[i]);

  /// a + b - c
  List<int> _addSub(List<int> a, List<int> b, List<int> c) =>
      List.generate(12, (i) => a[i] + b[i] - c[i]);
}

class _PLRow {
  final String label;
  final List<int> monthly;
  final _RowKind kind;
  const _PLRow({
    required this.label,
    required this.monthly,
    required this.kind,
  });

  int get total => monthly.fold<int>(0, (s, v) => s + v);
}

// ═════════════════════════════════════════════════
// テーブル本体（横スクロール）
// ═════════════════════════════════════════════════

class _PLTable extends StatelessWidget {
  final List<DateTime> months;
  final List<_PLRow> rows;
  const _PLTable({required this.months, required this.rows});

  static const labelColWidth = 160.0;
  static const monthColWidth = 90.0;
  static const totalColWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: V2Colors.border, width: 1)),
        ),
        child: Column(
          children: [
            _HeaderRow(months: months),
            for (final r in rows) _BodyRow(row: r),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<DateTime> months;
  const _HeaderRow({required this.months});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surfaceMuted,
      child: Row(
        children: [
          SizedBox(
            width: _PLTable.labelColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 8),
              child:
                  Text('項目', style: V2Typography.tableHeader),
            ),
          ),
          for (final m in months)
            SizedBox(
              width: _PLTable.monthColWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.sm, vertical: 8),
                child: Text(
                  '${m.month}月',
                  style: V2Typography.tableHeader,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          SizedBox(
            width: _PLTable.totalColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.sm, vertical: 8),
              child: Text(
                '年度累計',
                style: V2Typography.tableHeader.copyWith(
                    color: V2Colors.textPrimary,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  final _PLRow row;
  const _BodyRow({required this.row});

  Color _colorFor(int v) {
    if (v == 0) return V2Colors.textMuted;
    return v > 0 ? V2Colors.positive : V2Colors.negative;
  }

  @override
  Widget build(BuildContext context) {
    final isSubtotal = row.kind == _RowKind.subtotal;
    final isEmphasize = row.kind == _RowKind.emphasize;
    final isDetail = row.kind == _RowKind.detail;
    final highlightBg = isSubtotal
        ? const Color(0xFFFFFBEB)
        : (isEmphasize ? const Color(0xFFFEF9C3) : null);

    final labelStyle = isDetail
        ? V2Typography.caption.copyWith(
            color: V2Colors.textSecondary)
        : (isSubtotal || isEmphasize)
            ? V2Typography.bodyStrong.copyWith(
                color: V2Colors.textPrimary,
                fontWeight: isEmphasize
                    ? FontWeight.w800
                    : FontWeight.w700)
            : V2Typography.body;

    Color valueColor(int v) {
      if (isDetail) {
        return v == 0
            ? V2Colors.textMuted
            : V2Colors.textSecondary;
      }
      if (isSubtotal || isEmphasize) return _colorFor(v);
      return v == 0 ? V2Colors.textMuted : V2Colors.textPrimary;
    }

    final cellPadding = isDetail
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 8);

    return Container(
      decoration: BoxDecoration(
        color: highlightBg,
        border: Border(
            top: BorderSide(
                color: isSubtotal || isEmphasize
                    ? V2Colors.border
                    : V2Colors.divider,
                width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _PLTable.labelColWidth,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  isDetail ? 28 : 12,
                  cellPadding.vertical / 2,
                  12,
                  cellPadding.vertical / 2),
              child: Text(row.label, style: labelStyle),
            ),
          ),
          for (final v in row.monthly)
            SizedBox(
              width: _PLTable.monthColWidth,
              child: Padding(
                padding: cellPadding,
                child: Text(
                  v == 0 ? '0' : formatYen(v),
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                      color: valueColor(v),
                      fontSize: isDetail ? 11 : 13,
                      fontWeight: (isSubtotal || isEmphasize)
                          ? FontWeight.w700
                          : (isDetail
                              ? FontWeight.w500
                              : FontWeight.w600)),
                ),
              ),
            ),
          SizedBox(
            width: _PLTable.totalColWidth,
            child: Padding(
              padding: cellPadding,
              child: Text(
                row.total == 0 ? '0' : formatYen(row.total),
                textAlign: TextAlign.right,
                style: V2Typography.numericCell.copyWith(
                    color: valueColor(row.total),
                    fontSize: isEmphasize
                        ? 14
                        : (isDetail ? 11 : 13),
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
