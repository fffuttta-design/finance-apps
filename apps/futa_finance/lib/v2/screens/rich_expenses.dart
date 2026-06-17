import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 新デザイン（リッチUI）の経費／支出タブ。
/// 月サマリー → カテゴリ内訳 → 明細リスト。既存 V2ExpensesScreen は温存。
class RichExpensesScreen extends StatefulWidget {
  final Color accent;
  const RichExpensesScreen({super.key, required this.accent});

  @override
  State<RichExpensesScreen> createState() => _RichExpensesScreenState();
}

class _RichExpensesScreenState extends State<RichExpensesScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  List<core.Subscription> _subs = [];
  bool _loading = true;

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

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
    final subs = await SubscriptionRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _subs = subs.subscriptions;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  int _subsOf(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    return _subs.fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
  }

  /// 指定月に計上される固定費（サブスク）の明細（名前・金額・アイコン）。金額降順。
  List<({String name, int amount, String? iconUrl})> _fixedLinesForMonth(
      DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final lines = <({String name, int amount, String? iconUrl})>[];
    for (final sub in _subs) {
      final amt = sub.plAmountForMonth(ym, curYm);
      if (amt > 0) {
        lines.add((
          name: sub.name.trim().isEmpty ? '固定費' : sub.name,
          amount: amt,
          iconUrl: sub.iconUrl,
        ));
      }
    }
    lines.sort((a, b) => b.amount.compareTo(a.amount));
    return lines;
  }

  List<core.Transaction> get _monthExpenses => _transactions
      .where((t) =>
          t.type == core.TransactionType.expense &&
          t.date.year == _month.year &&
          t.date.month == _month.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> _edit(core.Transaction t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: t)),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final isBusiness = AppModeManager.instance.current == AppMode.business;
    final accent = widget.accent;
    final rows = _monthExpenses;
    final txTotal = rows.fold<int>(0, (s, t) => s + t.amount);
    final subTotal = _subsOf(_month);
    final total = txTotal + subTotal;
    final fixedLines = _fixedLinesForMonth(_month);

    // カテゴリ内訳（大カテゴリ別・固定費込み）
    final byMajor = <String, int>{};
    for (final t in rows) {
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.amount;
    }
    if (subTotal > 0) {
      byMajor['固定費・サブスク'] = (byMajor['固定費・サブスク'] ?? 0) + subTotal;
    }
    final majorEntries = byMajor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.lg, horizontal: V2Spacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isBusiness ? '経費' : '支出',
                  style:
                      V2Typography.h1.copyWith(color: V2Colors.textPrimary)),
              const SizedBox(height: V2Spacing.md),
              // サマリー
              Container(
                padding: const EdgeInsets.all(V2Spacing.lg),
                decoration: BoxDecoration(
                  color: V2Colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: V2Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${_month.month}月の${isBusiness ? '経費' : '支出'}合計',
                            style: V2Typography.caption
                                .copyWith(color: V2Colors.textSecondary)),
                        const Spacer(),
                        _MiniStepper(
                          label: '${_month.year}年${_month.month}月',
                          onPrev: () => _shiftMonth(-1),
                          onNext: () => _shiftMonth(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(formatYen(total),
                        style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: V2Colors.textPrimary,
                            fontFeatures: V2Typography.tabularNums)),
                    const SizedBox(height: 6),
                    Text(
                        '明細 ${rows.length}件'
                        '${subTotal > 0 ? ' ＋ 固定費 ${formatYen(subTotal)}' : ''}',
                        style: V2Typography.micro
                            .copyWith(color: V2Colors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: V2Spacing.md),
              // カテゴリ内訳（一番上）
              if (majorEntries.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(V2Spacing.md),
                  decoration: BoxDecoration(
                    color: V2Colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('カテゴリ内訳',
                          style: V2Typography.h2
                              .copyWith(color: V2Colors.textPrimary)),
                      const SizedBox(height: V2Spacing.md),
                      for (final e in majorEntries.take(8))
                        _CatBar(
                          name: e.key,
                          value: e.value,
                          ratio: total == 0 ? 0 : e.value / total,
                          accent: accent,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
              ],
              // 毎月の固定費（引落予定）— カテゴリの下
              if (fixedLines.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(V2Spacing.md),
                  decoration: BoxDecoration(
                    color: V2Colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.repeat,
                              size: 17, color: V2Colors.textSecondary),
                          const SizedBox(width: 6),
                          Text('毎月の固定費（引落予定）',
                              style: V2Typography.h2
                                  .copyWith(color: V2Colors.textPrimary)),
                          const Spacer(),
                          Text(formatYen(subTotal),
                              style: V2Typography.bodyStrong.copyWith(
                                  color: V2Colors.textPrimary,
                                  fontFeatures: V2Typography.tabularNums)),
                        ],
                      ),
                      const SizedBox(height: V2Spacing.sm),
                      for (int i = 0; i < fixedLines.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: V2Colors.divider),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              BrandLogo(
                                iconUrl: fixedLines[i].iconUrl,
                                fallbackIcon: Icons.subscriptions_outlined,
                                size: 20,
                                borderRadius: 5,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(fixedLines[i].name,
                                    style: V2Typography.body,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Text(formatYen(fixedLines[i].amount),
                                  style: V2Typography.caption.copyWith(
                                      color: V2Colors.textSecondary,
                                      fontFeatures:
                                          V2Typography.tabularNums)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
              ],
              // 明細
              Container(
                padding: const EdgeInsets.all(V2Spacing.md),
                decoration: BoxDecoration(
                  color: V2Colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: V2Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(isBusiness ? '経費明細' : '支出明細',
                            style: V2Typography.h2
                                .copyWith(color: V2Colors.textPrimary)),
                        const Spacer(),
                        InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ExpenseListScreen(
                                  title: isBusiness ? '経費明細一覧' : '支出明細一覧',
                                  month: _month,
                                ),
                              ),
                            );
                            await _load();
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Text('一覧',
                                    style: V2Typography.caption
                                        .copyWith(color: accent)),
                                Icon(Icons.chevron_right,
                                    size: 16, color: accent),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.sm),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.inbox_outlined,
                                  size: 36, color: V2Colors.textMuted),
                              const SizedBox(height: 8),
                              Text('${_month.month}月の記録はまだありません',
                                  style: V2Typography.caption.copyWith(
                                      color: V2Colors.textSecondary)),
                            ],
                          ),
                        ),
                      )
                    else
                      for (int i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: V2Colors.divider),
                        _ExpenseRow(t: rows[i], onTap: () => _edit(rows[i])),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MiniStepper(
      {required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon: const Icon(Icons.chevron_left, color: V2Colors.textSecondary),
          onPressed: onPrev,
        ),
        Text(label,
            style:
                V2Typography.bodyStrong.copyWith(color: V2Colors.textPrimary)),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon:
              const Icon(Icons.chevron_right, color: V2Colors.textSecondary),
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _CatBar extends StatelessWidget {
  final String name;
  final int value;
  final double ratio;
  final Color accent;
  const _CatBar({
    required this.name,
    required this.value,
    required this.ratio,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: V2Typography.body,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('${(ratio * 100).round()}%',
                  style: V2Typography.micro
                      .copyWith(color: V2Colors.textMuted)),
              const SizedBox(width: 10),
              Text(formatYen(value),
                  style: V2Typography.caption.copyWith(
                      color: V2Colors.textSecondary,
                      fontFeatures: V2Typography.tabularNums)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: V2Colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  const _ExpenseRow({required this.t, required this.onTap});

  String _categoryLabel() {
    final major = t.category.major
        .replaceFirst(RegExp(r'^\s*\d+\.\s*'), '')
        .trim();
    final sub = t.category.sub.trim();
    if (sub.isNotEmpty) return sub;
    if (major.isNotEmpty) return major;
    return '未分類';
  }

  @override
  Widget build(BuildContext context) {
    final title =
        t.description.trim().isNotEmpty ? t.description.trim() : _categoryLabel();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: V2Colors.negative.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.receipt_long_outlined,
                  size: 16, color: V2Colors.negative),
            ),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: V2Typography.bodyStrong,
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                  const SizedBox(height: 2),
                  Text('${formatMonthDay(t.date)} · ${_categoryLabel()}・${t.paymentMethod}',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted),
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('-${formatYen(t.amount)}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: V2Colors.negative,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}
