import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/emoji_palette.dart';
import '../utils/formatters.dart';
import '../widgets/calendar_view.dart';
import '../widgets/month_closing_view.dart';

/// 期間フィルタの選択肢。
enum _PeriodFilter {
  all,
  currentYear,
  last12Months,
  last6Months,
  last3Months,
  currentMonth,
}

extension _PeriodFilterX on _PeriodFilter {
  String get label {
    switch (this) {
      case _PeriodFilter.all:
        return '全期間';
      case _PeriodFilter.currentYear:
        return '今年';
      case _PeriodFilter.last12Months:
        return '直近12ヶ月';
      case _PeriodFilter.last6Months:
        return '直近6ヶ月';
      case _PeriodFilter.last3Months:
        return '直近3ヶ月';
      case _PeriodFilter.currentMonth:
        return '今月';
    }
  }

  /// 期間の開始日を返す。null は全期間。
  DateTime? startFrom(DateTime now) {
    switch (this) {
      case _PeriodFilter.all:
        return null;
      case _PeriodFilter.currentYear:
        return DateTime(now.year, 1, 1);
      case _PeriodFilter.last12Months:
        return DateTime(now.year, now.month - 11, 1);
      case _PeriodFilter.last6Months:
        return DateTime(now.year, now.month - 5, 1);
      case _PeriodFilter.last3Months:
        return DateTime(now.year, now.month - 2, 1);
      case _PeriodFilter.currentMonth:
        return DateTime(now.year, now.month, 1);
    }
  }
}

/// 種別フィルタ。
enum _TypeFilter { expense, income, both }

/// 集計タブ内のビューモード。
enum _AggregationViewMode { statistics, calendar, closing }

extension _TypeFilterX on _TypeFilter {
  String get label {
    switch (this) {
      case _TypeFilter.expense:
        return '支出';
      case _TypeFilter.income:
        return '収入';
      case _TypeFilter.both:
        return '両方';
    }
  }
}

/// 集計タブ。フィルタ + 統計 + 月別推移 + 該当取引リスト。
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _repo = TransactionRepository.instance;
  final _settings = SettingsRepository();
  StreamSubscription<List<core.Transaction>>? _streamSub;
  List<core.Transaction> _transactions = [];
  core.CategoryConfig? _categories;

  // ビューモード
  _AggregationViewMode _viewMode = _AggregationViewMode.statistics;

  // フィルタ
  _PeriodFilter _period = _PeriodFilter.last6Months;
  _TypeFilter _type = _TypeFilter.expense;
  String? _major; // 大カテゴリ表示名（例: "0.固定費(定額)"）。null=全カテゴリ
  String? _sub; // 小カテゴリ名。null=全小カテゴリ

  @override
  void initState() {
    super.initState();
    _load();
    _streamSub = _repo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _repo.loadAll();
    final cfg = await _settings.loadCategories();
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _categories = cfg;
    });
  }

  /// 現在のフィルタに合致する取引一覧（日付降順）。
  List<core.Transaction> get _filtered {
    final now = DateTime.now();
    final cutoff = _period.startFrom(now);
    final result = _transactions.where((t) {
      // 期間
      if (cutoff != null && t.date.isBefore(cutoff)) return false;
      // 種別
      if (_type == _TypeFilter.expense &&
          t.type != core.TransactionType.expense) {
        return false;
      }
      if (_type == _TypeFilter.income &&
          t.type != core.TransactionType.income) {
        return false;
      }
      // 大カテゴリ
      if (_major != null && t.category.major != _major) return false;
      // 小カテゴリ
      if (_sub != null && t.category.sub != _sub) return false;
      return true;
    }).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// 大カテゴリ表示名リスト（フィルタ用）。
  List<String> get _allMajors {
    final cfg = _categories;
    if (cfg == null) return const [];
    return List.generate(
        cfg.majors.length, (i) => cfg.majors[i].displayName(i));
  }

  /// 選択中の大カテゴリの小カテゴリリスト。
  List<String> get _subsOfMajor {
    final cfg = _categories;
    if (cfg == null || _major == null) return const [];
    final idx = cfg.majors.indexWhere(
        (m) => m.displayName(cfg.majors.indexOf(m)) == _major);
    if (idx < 0) return const [];
    return cfg.majors[idx].subs;
  }

  /// 月別合計（フィルタ済データから）。
  Map<DateTime, int> get _monthlyTotals {
    final map = <DateTime, int>{};
    for (final t in _filtered) {
      final key = DateTime(t.date.year, t.date.month);
      map[key] = (map[key] ?? 0) + t.amount;
    }
    return map;
  }

  String _iconKeyFor(String majorDisplay) {
    final cfg = _categories;
    if (cfg == null) return '📦';
    for (int i = 0; i < cfg.majors.length; i++) {
      if (cfg.majors[i].displayName(i) == majorDisplay) {
        return cfg.majors[i].iconKey ?? '📦';
      }
    }
    return '📦';
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = filtered.fold<int>(0, (s, t) => s + t.amount);
    final count = filtered.length;
    final avg = count == 0 ? 0 : (total / count).round();
    final maxAmount = filtered.fold<int>(
        0, (m, t) => t.amount > m ? t.amount : m);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '集計',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _viewToggle(),
            Expanded(
              child: switch (_viewMode) {
                _AggregationViewMode.statistics => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _filterSection(),
                      const SizedBox(height: 12),
                      _statsCard(count, total, avg, maxAmount),
                      const SizedBox(height: 12),
                      _monthlyChartCard(),
                      const SizedBox(height: 12),
                      _transactionsCard(filtered),
                    ],
                  ),
                _AggregationViewMode.calendar => const CalendarView(),
                _AggregationViewMode.closing => const MonthClosingView(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(
                child: _toggleSeg(_AggregationViewMode.statistics, '統計',
                    Icons.analytics_outlined)),
            Expanded(
                child: _toggleSeg(_AggregationViewMode.calendar,
                    'カレンダー', Icons.calendar_month_outlined)),
            Expanded(
                child: _toggleSeg(_AggregationViewMode.closing,
                    '月末締め', Icons.lock_outline)),
          ],
        ),
      ),
    );
  }

  Widget _toggleSeg(_AggregationViewMode mode, String label, IconData icon) {
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

  // ===================== Sections =====================

  Widget _filterSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.filter_alt_outlined,
                  size: 16, color: Color(0xFF1A237E)),
              SizedBox(width: 6),
              Text('フィルタ',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _filterChip(
                _period.label,
                onTap: _pickPeriod,
                active: _period != _PeriodFilter.last6Months,
              ),
              _filterChip(
                _type.label,
                onTap: _pickType,
                active: _type != _TypeFilter.expense,
              ),
              _filterChip(
                _major ?? '全カテゴリ',
                onTap: _pickMajor,
                active: _major != null,
                onClear: _major != null
                    ? () => setState(() {
                          _major = null;
                          _sub = null;
                        })
                    : null,
              ),
              if (_major != null)
                _filterChip(
                  _sub ?? '全小カテゴリ',
                  onTap: _pickSub,
                  active: _sub != null,
                  onClear:
                      _sub != null ? () => setState(() => _sub = null) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label, {
    required VoidCallback onTap,
    bool active = false,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE0E7FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF1A237E)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF6B7280),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 14, color: Color(0xFF1A237E)),
              ),
            ] else ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: active
                      ? const Color(0xFF1A237E)
                      : const Color(0xFF9CA3AF)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statsCard(int count, int total, int avg, int maxAmount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate,
                  size: 16, color: Color(0xFF1A237E)),
              const SizedBox(width: 6),
              const Text('統計',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statBlock('件数', '$count件')),
              Expanded(
                child: _statBlock(
                  '合計',
                  formatYen(total),
                  color: _type == _TypeFilter.income
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  big: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _statBlock('平均', formatYen(avg))),
              Expanded(child: _statBlock('最大', formatYen(maxAmount))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBlock(String label, String value,
      {Color? color, bool big = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: big ? 18 : 14,
                fontWeight: FontWeight.w700,
                color: color ?? const Color(0xFF111827),
                fontFamily: 'monospace')),
      ],
    );
  }

  Widget _monthlyChartCard() {
    final totals = _monthlyTotals;
    if (totals.isEmpty) return const SizedBox.shrink();

    // 月のキーをソート
    final months = totals.keys.toList()..sort();
    final maxValue = totals.values.fold(0, (m, v) => v > m ? v : m);
    final barColor = _type == _TypeFilter.income
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.show_chart, size: 16, color: Color(0xFF1A237E)),
              SizedBox(width: 6),
              Text('月別推移',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: months.map((m) {
                final value = totals[m] ?? 0;
                final h = maxValue == 0 ? 0.0 : (value / maxValue) * 120;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (value > 0) ...[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _compactYen(value),
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF6B7280),
                                  fontFamily: 'monospace'),
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Container(
                          height: h.clamp(2, 120),
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${m.month}月',
                            style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF6B7280))),
                        if (m.month == 1 || months.indexOf(m) == 0)
                          Text('${m.year}',
                              style: const TextStyle(
                                  fontSize: 8,
                                  color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _compactYen(int amount) {
    if (amount.abs() < 10000) {
      return amount.toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
    }
    final man = amount.abs() / 10000;
    if (man == man.roundToDouble()) {
      return '${man.toInt()}万';
    }
    return '${man.toStringAsFixed(1)}万';
  }

  Widget _transactionsCard(List<core.Transaction> txns) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.list, size: 16, color: Color(0xFF1A237E)),
                const SizedBox(width: 6),
                const Text('該当取引',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const Spacer(),
                Text('${txns.length}件',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          if (txns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Center(
                child: Text('該当する取引なし',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ...txns.asMap().entries.map((e) => _txnRow(e.value, e.key == 0)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _txnRow(core.Transaction t, bool isFirst) {
    final isExpense = t.type == core.TransactionType.expense;
    final color = isExpense
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);
    final majorClean = t.category.major.contains('.')
        ? t.category.major.substring(t.category.major.indexOf('.') + 1)
        : t.category.major;
    final categoryText = t.category.sub.isNotEmpty
        ? '$majorClean・${t.category.sub}'
        : majorClean;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: isFirst ? Colors.transparent : const Color(0xFFF3F4F6)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '${t.date.year.toString().substring(2)}/${formatMonthDay(t.date)}',
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 4),
          categoryIconWidget(_iconKeyFor(t.category.major), size: 14),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                Text(categoryText,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF9CA3AF)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isExpense
                ? formatYen(-t.amount, withSign: true)
                : formatYen(t.amount, withSign: true),
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ===================== Pickers =====================

  void _pickPeriod() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _PeriodFilter.values
              .map((p) => ListTile(
                    title: Text(p.label),
                    trailing: p == _period
                        ? const Icon(Icons.check,
                            color: Color(0xFF1A237E))
                        : null,
                    onTap: () {
                      setState(() => _period = p);
                      Navigator.pop(sheet);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickType() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _TypeFilter.values
              .map((t) => ListTile(
                    title: Text(t.label),
                    trailing: t == _type
                        ? const Icon(Icons.check,
                            color: Color(0xFF1A237E))
                        : null,
                    onTap: () {
                      setState(() => _type = t);
                      Navigator.pop(sheet);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickMajor() {
    final majors = _allMajors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('全カテゴリ'),
              trailing: _major == null
                  ? const Icon(Icons.check, color: Color(0xFF1A237E))
                  : null,
              onTap: () {
                setState(() {
                  _major = null;
                  _sub = null;
                });
                Navigator.pop(sheet);
              },
            ),
            const Divider(height: 1),
            ...majors.map((m) => ListTile(
                  leading:
                      categoryIconWidget(_iconKeyFor(m), size: 18),
                  title: Text(m),
                  trailing: m == _major
                      ? const Icon(Icons.check, color: Color(0xFF1A237E))
                      : null,
                  onTap: () {
                    setState(() {
                      _major = m;
                      _sub = null;
                    });
                    Navigator.pop(sheet);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _pickSub() {
    final subs = _subsOfMajor;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('全小カテゴリ'),
              trailing: _sub == null
                  ? const Icon(Icons.check, color: Color(0xFF1A237E))
                  : null,
              onTap: () {
                setState(() => _sub = null);
                Navigator.pop(sheet);
              },
            ),
            const Divider(height: 1),
            ...subs.map((s) => ListTile(
                  title: Text(s),
                  trailing: s == _sub
                      ? const Icon(Icons.check, color: Color(0xFF1A237E))
                      : null,
                  onTap: () {
                    setState(() => _sub = s);
                    Navigator.pop(sheet);
                  },
                )),
          ],
        ),
      ),
    );
  }
}
