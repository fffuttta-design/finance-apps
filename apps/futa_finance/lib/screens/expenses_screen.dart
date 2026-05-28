import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/emoji_palette.dart';
import '../utils/formatters.dart';
import 'expense_input_screen.dart';

/// 支出タブ。月送り、年間払い契約、カテゴリ別の支出一覧（折りたたみ式）。
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

/// 支出タブの表示モード。
/// 表示モード。並びは UI の並びと合わせて 行→リスト→カテゴリ→グラフ。
/// 行をデフォルトに（最も情報密度が高く、日々の確認はこのモードが中心）。
enum _ExpensesViewMode { row, list, grouped, chart }

/// リスト表示時の並び順。
enum _ExpensesSortMode { dateDesc, amountDesc }

class _ExpensesScreenState extends State<ExpensesScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _repo = TransactionRepository.instance;
  final _settings = SettingsRepository();
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.CategoryConfig? _categoryConfig;
  DateTime _focused = DateTime(DateTime.now().year, DateTime.now().month);
  _ExpensesViewMode _viewMode = _ExpensesViewMode.row;
  _ExpensesSortMode _sortMode = _ExpensesSortMode.dateDesc;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _repo.stream.listen((list) {
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
    final list = await _repo.loadAll();
    final cfg = await _settings.loadCategories();
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _categoryConfig = cfg;
    });
  }

  /// 大カテゴリ表示名 → アイコンキー（絵文字 or Material アイコン名）
  String? _iconKeyFor(String majorDisplayName) {
    final cfg = _categoryConfig;
    if (cfg == null) return null;
    for (int i = 0; i < cfg.majors.length; i++) {
      if (cfg.majors[i].displayName(i) == majorDisplayName) {
        return cfg.majors[i].iconKey;
      }
    }
    return null;
  }

  void _prevMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month - 1));
  }

  void _nextMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month + 1));
  }

  /// 表示中月の支出のみ。
  List<core.Transaction> get _monthExpenses => _transactions
      .where((t) =>
          t.type == core.TransactionType.expense &&
          t.date.year == _focused.year &&
          t.date.month == _focused.month)
      .toList();

  /// 表示用にソートした当月支出。並び順は _sortMode による。
  List<core.Transaction> get _sortedMonthExpenses {
    final list = [..._monthExpenses];
    if (_sortMode == _ExpensesSortMode.dateDesc) {
      list.sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return b.amount.compareTo(a.amount); // 同日なら金額降順
      });
    } else {
      // 金額降順、同額なら日付降順
      list.sort((a, b) {
        final amtCmp = b.amount.compareTo(a.amount);
        if (amtCmp != 0) return amtCmp;
        return b.date.compareTo(a.date);
      });
    }
    return list;
  }

  /// 大カテゴリ → その月の取引リスト（_sortMode に従う）。
  Map<String, List<core.Transaction>> get _byMajor {
    final map = <String, List<core.Transaction>>{};
    for (final t in _monthExpenses) {
      map.putIfAbsent(t.category.major, () => []).add(t);
    }
    for (final list in map.values) {
      if (_sortMode == _ExpensesSortMode.dateDesc) {
        list.sort((a, b) {
          final dateCmp = b.date.compareTo(a.date);
          if (dateCmp != 0) return dateCmp;
          return b.amount.compareTo(a.amount);
        });
      } else {
        list.sort((a, b) {
          final amtCmp = b.amount.compareTo(a.amount);
          if (amtCmp != 0) return amtCmp;
          return b.date.compareTo(a.date);
        });
      }
    }
    return map;
  }

  /// カテゴリ別合計（降順）。
  List<MapEntry<String, int>> get _majorTotalsSorted {
    final totals = <String, int>{};
    for (final t in _monthExpenses) {
      totals[t.category.major] = (totals[t.category.major] ?? 0) + t.amount;
    }
    return totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  @override
  Widget build(BuildContext context) {
    final monthExpenses = _monthExpenses;
    final totalAmount =
        monthExpenses.fold<int>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('支出',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          IconButton(
            tooltip: '支出を記録',
            icon: const Icon(Icons.add_circle,
                color: Color(0xFFDC2626), size: 28),
            onPressed: () async {
              final saved = await showExpenseInputModal(context);
              if (saved == true && mounted) _load();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _monthHeader(monthExpenses.length, totalAmount),
            _viewToggle(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (monthExpenses.isEmpty)
                    _empty()
                  else if (_viewMode == _ExpensesViewMode.list)
                    ..._sortedMonthExpenses.map(_txnCard)
                  else if (_viewMode == _ExpensesViewMode.row)
                    _rowTable(_sortedMonthExpenses)
                  else if (_viewMode == _ExpensesViewMode.chart)
                    _chartView(_majorTotalsSorted, totalAmount)
                  else
                    ..._majorTotalsSorted.map((e) =>
                        _categorySection(e.key, e.value, _byMajor[e.key]!)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthHeader(int count, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left, color: Color(0xFF1A237E)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_focused.year}年${_focused.month}月',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827)),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$count件',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                    const SizedBox(width: 12),
                    Text('合計 ${formatYen(-total, withSign: true)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDC2626),
                            fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right, color: Color(0xFF1A237E)),
          ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                      child: _toggleSeg(_ExpensesViewMode.row, '行',
                          Icons.table_rows_outlined)),
                  Expanded(
                      child: _toggleSeg(
                          _ExpensesViewMode.list, 'リスト', Icons.list)),
                  Expanded(
                      child: _toggleSeg(_ExpensesViewMode.grouped, 'カテゴリ',
                          Icons.folder_outlined)),
                  Expanded(
                      child: _toggleSeg(_ExpensesViewMode.chart, 'グラフ',
                          Icons.pie_chart_outline)),
                ],
              ),
            ),
          ),
          if (_viewMode != _ExpensesViewMode.chart) ...[
            const SizedBox(width: 8),
            _sortMenu(),
          ],
        ],
      ),
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<_ExpensesSortMode>(
      tooltip: '並び順',
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 16, color: Color(0xFF6B7280)),
            const SizedBox(width: 4),
            Text(
              _sortMode == _ExpensesSortMode.dateDesc ? '日付順' : '金額順',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
      onSelected: (m) => setState(() => _sortMode = m),
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: _ExpensesSortMode.dateDesc,
            child: Text('日付の新しい順')),
        PopupMenuItem(
            value: _ExpensesSortMode.amountDesc,
            child: Text('金額の大きい順')),
      ],
    );
  }

  Widget _toggleSeg(_ExpensesViewMode mode, String label, IconData icon) {
    final selected = _viewMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 3,
                      offset: Offset(0, 1))
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 大カテゴリでグループ化した表示（ExpansionTile）。
  Widget _categorySection(
      String major, int total, List<core.Transaction> txns) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          leading: categoryIconWidget(_iconKeyFor(major),
              color: const Color(0xFF1A237E), size: 20),
          title: Text(major,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827))),
          subtitle: Text('${txns.length}件',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF9CA3AF))),
          trailing: Text(
            formatYen(total),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
                fontFamily: 'monospace'),
          ),
          children: txns.map((t) => _txnRowInGroup(t)).toList(),
        ),
      ),
    );
  }

  /// グループ表示内の取引行（カード化せず、罫線区切りでコンパクト表示）。
  Widget _txnRowInGroup(core.Transaction t) {
    final hasUsd = t.originalCurrency == 'USD' && t.originalAmount != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 14, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              formatMonthDay(t.date),
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF111827)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  '${t.category.sub.isEmpty ? "未分類" : t.category.sub} · ${t.paymentMethod}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatYen(-t.amount, withSign: true),
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFDC2626),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600),
              ),
              if (hasUsd)
                Text(
                  '\$${t.originalAmount!.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'monospace'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// パイチャート用のカラーパレット（カテゴリ数に応じて巡回）。
  static const List<Color> _chartColors = [
    Color(0xFF1A237E), // ネイビー
    Color(0xFFDC2626), // 赤
    Color(0xFF16A34A), // 緑
    Color(0xFFEA580C), // オレンジ
    Color(0xFF7C3AED), // 紫
    Color(0xFF0891B2), // シアン
    Color(0xFFCA8A04), // ゴールド
    Color(0xFFDB2777), // ピンク
    Color(0xFF65A30D), // ライム
    Color(0xFF475569), // スレート
  ];

  /// グラフビュー: 円グラフ + 凡例（カテゴリ別の割合）。
  Widget _chartView(List<MapEntry<String, int>> totals, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // 円グラフ本体（中央に合計表示）
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(240, 240),
                  painter: _DonutChartPainter(
                    values: totals.map((e) => e.value.toDouble()).toList(),
                    colors: List.generate(
                        totals.length,
                        (i) =>
                            _chartColors[i % _chartColors.length]),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('合計',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 2),
                    Text(
                      formatYen(total),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 2),
                    Text('${totals.length}カテゴリ',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 凡例
          ...totals.asMap().entries.map((e) {
            final color = _chartColors[e.key % _chartColors.length];
            final ratio = total == 0 ? 0.0 : e.value.value / total;
            return _legendRow(
                e.value.key, e.value.value, ratio, color);
          }),
        ],
      ),
    );
  }

  Widget _legendRow(String major, int amount, double ratio, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 色チップ
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // アイコン
          categoryIconWidget(_iconKeyFor(major), size: 16),
          const SizedBox(width: 6),
          // 名前
          Expanded(
            child: Text(
              major.contains('.')
                  ? major.substring(major.indexOf('.') + 1)
                  : major,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF111827)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 金額
          Text(
            formatYen(amount),
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF111827),
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          // %
          SizedBox(
            width: 44,
            child: Text(
              '${(ratio * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inbox_outlined, size: 64, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('この月は支出記録なし',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ],
        ),
      );


  /// 行表示テーブル（ヘッダー + 罫線 + 等幅カラム）。
  Widget _rowTable(List<core.Transaction> txns) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          _rowHeader(),
          ...txns.asMap().entries.map((e) => _row(e.value)),
        ],
      ),
    );
  }

  /// テーブルのカラム幅定義（flex比率）。
  /// この同じ比率を _rowHeader と _row で使うことでカラムが揃う。
  /// 支払方法はデフォルト非表示（行タップで詳細シートに表示）。
  static const _colFlexDate = 3; // 日付 (例: 12/25)
  static const _colFlexDesc = 9; // 支出名
  static const _colFlexCategory = 6; // カテゴリ
  static const _colFlexAmount = 5; // 金額

  Widget _rowHeader() {
    const headerStyle = TextStyle(
      fontSize: 9,
      color: Color(0xFF9CA3AF),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(10)),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      // 列順: 日付 → カテゴリ → 支出名 → 金額
      child: const Row(
        children: [
          Expanded(
            flex: _colFlexDate,
            child: Text('日付', style: headerStyle),
          ),
          SizedBox(width: 3),
          Expanded(
            flex: _colFlexCategory,
            child: Text('カテゴリ', style: headerStyle),
          ),
          SizedBox(width: 3),
          Expanded(
            flex: _colFlexDesc,
            child: Text('支出名', style: headerStyle),
          ),
          SizedBox(width: 3),
          Expanded(
            flex: _colFlexAmount,
            child: Text('金額',
                style: headerStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  /// 1取引=1行（ヘッダーと同じカラム幅で揃う）。
  Widget _row(core.Transaction t) {
    return InkWell(
      onTap: () => _showRowDetail(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6)),
          ),
        ),
        child: Row(
          children: [
            // 日付
            Expanded(
              flex: _colFlexDate,
              child: Text(
                formatMonthDay(t.date),
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 3),
            // カテゴリ(大/小)
            Expanded(
              flex: _colFlexCategory,
              child: Text(
                _categoryLabel(t),
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF6B7280)),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 3),
            // 支出名
            Expanded(
              flex: _colFlexDesc,
              child: Text(
                t.description,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 3),
            // 金額
            Expanded(
              flex: _colFlexAmount,
              child: Text(
                formatYen(-t.amount, withSign: true),
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFDC2626),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(core.Transaction t) {
    // "0.固定費(定額)" → "固定費(定額)"
    final major = t.category.major.contains('.')
        ? t.category.major.substring(t.category.major.indexOf('.') + 1)
        : t.category.major;
    if (t.category.sub.isNotEmpty) {
      return '$major・${t.category.sub}';
    }
    return major;
  }

  /// 行をタップしたときの詳細ボトムシート。
  void _showRowDetail(core.Transaction t) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  categoryIconWidget(_iconKeyFor(t.category.major),
                      color: const Color(0xFF1A237E), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.description,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow(
                  '日付',
                  '${t.date.year}年${t.date.month}月${t.date.day}日（${weekdayKanji(t.date)}）'),
              _detailRow('カテゴリ', _categoryLabel(t)),
              _detailRow('支払方法', t.paymentMethod),
              _detailRow(
                  '金額', formatYen(-t.amount, withSign: true),
                  valueColor: const Color(0xFFDC2626),
                  valueBold: true),
              if (t.originalCurrency == 'USD' && t.originalAmount != null)
                _detailRow('原通貨',
                    'USD \$${t.originalAmount!.toStringAsFixed(2)}'),
              if (t.memo != null && t.memo!.isNotEmpty)
                _detailRow('備考', t.memo!),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {Color? valueColor, bool valueBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
                  color: valueColor ?? const Color(0xFF111827)),
            ),
          ),
        ],
      ),
    );
  }

  /// 1取引を1枚のカードとして表示。
  Widget _txnCard(core.Transaction t) {
    final hasUsd = t.originalCurrency == 'USD' && t.originalAmount != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          // カテゴリアイコン
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: categoryIconWidget(_iconKeyFor(t.category.major),
                color: const Color(0xFF1A237E), size: 20),
          ),
          const SizedBox(width: 10),
          // 中央: 取引内容 + メタ情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  '${formatMonthDay(t.date)}（${weekdayKanji(t.date)}） · ${t.category.major.contains('.') ? t.category.major.substring(t.category.major.indexOf('.') + 1) : t.category.major}'
                  '${t.category.sub.isNotEmpty ? " / ${t.category.sub}" : ""}'
                  ' · ${t.paymentMethod}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          // 右: 金額（+ USD併記）
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatYen(-t.amount, withSign: true),
                style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFDC2626),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold),
              ),
              if (hasUsd)
                Text(
                  '\$${t.originalAmount!.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'monospace'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ドーナツ型の円グラフを描画する CustomPainter。
/// [values] の合計を 360° に正規化し、各セグメントを [colors] で塗り分ける。
class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.values, required this.colors})
      : assert(values.length == colors.length);

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;
    final strokeWidth = outerRadius * 0.32; // ドーナツの太さ
    final ringRadius = outerRadius - strokeWidth / 2;

    double startAngle = -math.pi / 2; // 12時位置から開始
    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        startAngle,
        sweep - 0.005, // セグメント間の隙間
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
