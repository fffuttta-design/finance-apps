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

/// 損益計算書（PL）の項目分類。
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

/// v2.1 集計タブ：会計風月次表（PL）。
///
/// 横軸: 事業年度の各月（6月始まり既定）＋ 年度累計
/// 縦軸: 売上 / 原価 / 粗利 / 販管費 / 営業利益 / 営業外収益 / 営業外費用 /
///       経常利益 / 特別利益 / 特別損失 / 税引前利益 / 法人税等 / 当期純利益
///
/// データは Transaction から自動集計。Category.major のキーワードで分類する：
/// - "原価" / "仕入"   → 売上原価
/// - "営業外"          → 営業外収益 or 費用
/// - "特別"            → 特別利益 or 損失
/// - "法人税" / "租税" / "税金" → 法人税等
/// - それ以外の expense → 販管費
/// - 通常 income       → 売上高
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

  /// 事業年度開始月（既定: 6 月）
  final int _fyStartMonth = 6;

  /// 表示する事業年度（その年度の開始年）
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

  // ── PL カテゴリ分類 ──
  _PLCategory _classify(core.Transaction t) {
    final major = t.category.major;
    if (t.type == core.TransactionType.income) {
      if (major.contains('特別')) return _PLCategory.extraIncome;
      if (major.contains('営業外')) return _PLCategory.nonOpIncome;
      return _PLCategory.sales;
    }
    if (t.type == core.TransactionType.expense) {
      if (major.contains('法人税') ||
          major.contains('租税') ||
          major.contains('税金') ||
          major.contains('住民税') ||
          major.contains('事業税') ||
          major.contains('所得税')) {
        return _PLCategory.tax;
      }
      if (major.contains('特別')) return _PLCategory.extraExpense;
      if (major.contains('営業外')) return _PLCategory.nonOpExpense;
      if (major.contains('原価') || major.contains('仕入')) {
        return _PLCategory.cogs;
      }
      return _PLCategory.sga;
    }
    return _PLCategory.other;
  }

  /// 事業年度の各月 (12 件、開始月から順)
  List<DateTime> get _fyMonths => List.generate(12, (i) {
        final m = _fyStartMonth + i;
        final y = _fyYear + (m > 12 ? 1 : 0);
        final mm = m > 12 ? m - 12 : m;
        return DateTime(y, mm);
      });

  /// カテゴリ別の月次集計 [Category → List<int> (12 ヶ月)]
  Map<_PLCategory, List<int>> _aggregate() {
    final months = _fyMonths;
    final result = {
      for (final c in _PLCategory.values) c: List<int>.filled(12, 0),
    };
    for (final t in _transactions) {
      final idx = months.indexWhere(
          (m) => m.year == t.date.year && m.month == t.date.month);
      if (idx < 0) continue;
      final c = _classify(t);
      result[c]![idx] += t.amount;
    }
    return result;
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
    final agg = _aggregate();
    final fyEndYear = _fyYear + 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 月次表 PL ────────────────────────
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
                      // 年度切替
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
                _PLTable(
                  months: _fyMonths,
                  monthly: agg,
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
          // ── 注記 + v1 集計画面リンク ──
          V2Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PL カテゴリ判定',
                    style: V2Typography.bodyStrong.copyWith(
                        color: V2Colors.textPrimary)),
                const SizedBox(height: V2Spacing.sm),
                Text(
                  'Transaction のカテゴリ名（大カテゴリ）で自動分類します。\n'
                  '・「原価」「仕入」を含む → 売上原価\n'
                  '・「営業外」を含む → 営業外収益 / 費用\n'
                  '・「特別」を含む → 特別利益 / 損失\n'
                  '・「法人税」「租税」「税金」「住民税」「事業税」「所得税」を含む → 法人税等\n'
                  '・上記以外の収入 → 売上高\n'
                  '・上記以外の支出 → 販売管理費',
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
}

// ═════════════════════════════════════════════════
// PL テーブル本体
// ═════════════════════════════════════════════════

class _PLTable extends StatelessWidget {
  final List<DateTime> months;
  final Map<_PLCategory, List<int>> monthly;
  const _PLTable({required this.months, required this.monthly});

  // 各カテゴリの累計
  int _total(_PLCategory c) =>
      monthly[c]!.fold<int>(0, (s, v) => s + v);

  // 計算行：粗利、営業利益、経常利益、税引前、当期純利益
  List<int> _grossMonthly() => List.generate(12, (i) =>
      monthly[_PLCategory.sales]![i] - monthly[_PLCategory.cogs]![i]);

  List<int> _operMonthly() {
    final gross = _grossMonthly();
    return List.generate(
        12, (i) => gross[i] - monthly[_PLCategory.sga]![i]);
  }

  List<int> _ordMonthly() {
    final oper = _operMonthly();
    return List.generate(
        12,
        (i) =>
            oper[i] +
            monthly[_PLCategory.nonOpIncome]![i] -
            monthly[_PLCategory.nonOpExpense]![i]);
  }

  List<int> _preTaxMonthly() {
    final ord = _ordMonthly();
    return List.generate(
        12,
        (i) =>
            ord[i] +
            monthly[_PLCategory.extraIncome]![i] -
            monthly[_PLCategory.extraExpense]![i]);
  }

  List<int> _netMonthly() {
    final preTax = _preTaxMonthly();
    return List.generate(
        12, (i) => preTax[i] - monthly[_PLCategory.tax]![i]);
  }

  int _sumOf(List<int> arr) => arr.fold<int>(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    final gross = _grossMonthly();
    final oper = _operMonthly();
    final ord = _ordMonthly();
    final preTax = _preTaxMonthly();
    final net = _netMonthly();

    const labelColWidth = 130.0;
    const monthColWidth = 90.0;
    const totalColWidth = 110.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: V2Colors.border, width: 1)),
        ),
        child: Column(
          children: [
            // ヘッダー
            _HeaderRow(
              months: months,
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            // データ
            _DataRow(
              label: '売上高',
              monthly: monthly[_PLCategory.sales]!,
              total: _total(_PLCategory.sales),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '売上原価',
              monthly: monthly[_PLCategory.cogs]!,
              total: _total(_PLCategory.cogs),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _SubtotalRow(
              label: '売上総利益',
              monthly: gross,
              total: _sumOf(gross),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '販売管理費',
              monthly: monthly[_PLCategory.sga]!,
              total: _total(_PLCategory.sga),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _SubtotalRow(
              label: '営業利益',
              monthly: oper,
              total: _sumOf(oper),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '営業外収益',
              monthly: monthly[_PLCategory.nonOpIncome]!,
              total: _total(_PLCategory.nonOpIncome),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '営業外費用',
              monthly: monthly[_PLCategory.nonOpExpense]!,
              total: _total(_PLCategory.nonOpExpense),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _SubtotalRow(
              label: '経常利益',
              monthly: ord,
              total: _sumOf(ord),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '特別利益',
              monthly: monthly[_PLCategory.extraIncome]!,
              total: _total(_PLCategory.extraIncome),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '特別損失',
              monthly: monthly[_PLCategory.extraExpense]!,
              total: _total(_PLCategory.extraExpense),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _SubtotalRow(
              label: '税引前当期純利益',
              monthly: preTax,
              total: _sumOf(preTax),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _DataRow(
              label: '法人税等',
              monthly: monthly[_PLCategory.tax]!,
              total: _total(_PLCategory.tax),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
            ),
            _SubtotalRow(
              label: '当期純利益',
              monthly: net,
              total: _sumOf(net),
              labelWidth: labelColWidth,
              monthWidth: monthColWidth,
              totalWidth: totalColWidth,
              emphasize: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<DateTime> months;
  final double labelWidth;
  final double monthWidth;
  final double totalWidth;
  const _HeaderRow({
    required this.months,
    required this.labelWidth,
    required this.monthWidth,
    required this.totalWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surfaceMuted,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 8),
              child: Text('項目',
                  style: V2Typography.tableHeader),
            ),
          ),
          for (final m in months)
            SizedBox(
              width: monthWidth,
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
            width: totalWidth,
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

class _DataRow extends StatelessWidget {
  final String label;
  final List<int> monthly;
  final int total;
  final double labelWidth;
  final double monthWidth;
  final double totalWidth;
  const _DataRow({
    required this.label,
    required this.monthly,
    required this.total,
    required this.labelWidth,
    required this.monthWidth,
    required this.totalWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
            top: BorderSide(color: V2Colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 8),
              child: Text(label, style: V2Typography.body),
            ),
          ),
          for (final v in monthly)
            SizedBox(
              width: monthWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.sm, vertical: 8),
                child: Text(
                  v == 0 ? '0' : formatYen(v),
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                      color: v == 0
                          ? V2Colors.textMuted
                          : V2Colors.textBody),
                ),
              ),
            ),
          SizedBox(
            width: totalWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.sm, vertical: 8),
              child: Text(
                total == 0 ? '0' : formatYen(total),
                textAlign: TextAlign.right,
                style: V2Typography.numericCell.copyWith(
                    color: total == 0
                        ? V2Colors.textMuted
                        : V2Colors.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtotalRow extends StatelessWidget {
  final String label;
  final List<int> monthly;
  final int total;
  final double labelWidth;
  final double monthWidth;
  final double totalWidth;
  final bool emphasize;
  const _SubtotalRow({
    required this.label,
    required this.monthly,
    required this.total,
    required this.labelWidth,
    required this.monthWidth,
    required this.totalWidth,
    this.emphasize = false,
  });

  Color _colorFor(int v) {
    if (v == 0) return V2Colors.textMuted;
    return v > 0 ? V2Colors.positive : V2Colors.negative;
  }

  @override
  Widget build(BuildContext context) {
    // ハイライト行（黄色背景）
    final bg =
        emphasize ? const Color(0xFFFEF9C3) : const Color(0xFFFFFBEB);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
            top: BorderSide(color: V2Colors.border, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 9),
              child: Text(label,
                  style: V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary,
                      fontWeight: emphasize
                          ? FontWeight.w800
                          : FontWeight.w700)),
            ),
          ),
          for (final v in monthly)
            SizedBox(
              width: monthWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.sm, vertical: 9),
                child: Text(
                  v == 0 ? '0' : formatYen(v),
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                      color: _colorFor(v),
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          SizedBox(
            width: totalWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.sm, vertical: 9),
              child: Text(
                total == 0 ? '0' : formatYen(total),
                textAlign: TextAlign.right,
                style: V2Typography.numericCell.copyWith(
                    color: _colorFor(total),
                    fontSize: emphasize ? 14 : 13,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
