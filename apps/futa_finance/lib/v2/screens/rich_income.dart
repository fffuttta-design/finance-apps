import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/month_cursor.dart';
import '../../data/transaction_repository.dart';
import '../../screens/income_input_screen.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/month_closing_bar.dart';

/// 新デザイン（リッチUI）の売上／収入タブ。
/// サマリーカード（合計＋確定/見込み）＋明細リスト。既存 V2IncomeScreen は温存。
class RichIncomeScreen extends StatefulWidget {
  final Color accent;
  const RichIncomeScreen({super.key, required this.accent});

  @override
  State<RichIncomeScreen> createState() => _RichIncomeScreenState();
}

class _RichIncomeScreenState extends State<RichIncomeScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  bool _loading = true;

  // タブ横断で月を共有（切替で今月にリセットされないよう共有カーソルを初期値に）。
  late DateTime _month = MonthCursor.instance.month;

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
    MonthCursor.instance.addListener(_onMonthCursor);
  }

  /// 他タブで月が変わったら追従。
  void _onMonthCursor() {
    final m = MonthCursor.instance.month;
    if (!mounted) return;
    if (m.year != _month.year || m.month != _month.month) {
      setState(() => _month = DateTime(m.year, m.month));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    MonthCursor.instance.removeListener(_onMonthCursor);
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

  List<core.Transaction> get _monthIncome => _transactions
      .where((t) =>
          t.type == core.TransactionType.income &&
          t.date.year == _month.year &&
          t.date.month == _month.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> _editTxn(core.Transaction t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => IncomeInputScreen(editing: t)),
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
    final all = _monthIncome;
    final confirmed = all.where((t) => !t.isPending).toList();
    final pending = all.where((t) => t.isPending).toList();
    final confirmedTotal = confirmed.fold<int>(0, (s, t) => s + t.amount);
    final pendingTotal = pending.fold<int>(0, (s, t) => s + t.amount);
    final total = confirmedTotal + pendingTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.lg, horizontal: V2Spacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 月の切替はトップバーの共有月ナビに集約。ここは締めボタンだけ右に。
              Row(
                children: [
                  Text(isBusiness ? '売上' : '収入',
                      style: V2Typography.h1
                          .copyWith(color: V2Colors.textPrimary)),
                  const Spacer(),
                  MonthClosingBar(
                      month: _month, snapshotIncome: total, dense: true),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              // サマリーカード
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
                    Text('${_month.month}月の合計',
                        style: V2Typography.caption
                            .copyWith(color: V2Colors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(formatYen(total),
                        style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: V2Colors.positive,
                            fontFeatures: V2Typography.tabularNums)),
                    const SizedBox(height: V2Spacing.md),
                    Row(
                      children: [
                        _SplitChip(
                          label: '確定',
                          count: confirmed.length,
                          amount: confirmedTotal,
                          color: V2Colors.positive,
                          soft: V2Colors.positiveSoft,
                        ),
                        const SizedBox(width: V2Spacing.sm),
                        _SplitChip(
                          label: '見込み',
                          count: pending.length,
                          amount: pendingTotal,
                          color: V2Colors.warning,
                          soft: V2Colors.warningSoft,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: V2Spacing.md),
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
                    Text(isBusiness ? '売上明細' : '収入明細',
                        style: V2Typography.h2
                            .copyWith(color: V2Colors.textPrimary)),
                    const SizedBox(height: V2Spacing.sm),
                    if (all.isEmpty)
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
                      for (int i = 0; i < all.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: V2Colors.divider),
                        _IncomeRow(t: all[i], onTap: () => _editTxn(all[i])),
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

class _SplitChip extends StatelessWidget {
  final String label;
  final int count;
  final int amount;
  final Color color;
  final Color soft;
  const _SplitChip({
    required this.label,
    required this.count,
    required this.amount,
    required this.color,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: soft.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Text('$label $count件',
                style: V2Typography.micro
                    .copyWith(color: color, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(formatYen(amount),
                style: V2Typography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}

class _IncomeRow extends StatelessWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  const _IncomeRow({required this.t, required this.onTap});

  String _categoryLabel() {
    final major = t.category.major.trim();
    final sub = t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return '未分類';
    if (sub.isEmpty) return major;
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    final isPending = t.isPending;
    final color = isPending ? V2Colors.warning : V2Colors.positive;
    final soft = isPending ? V2Colors.warningSoft : V2Colors.positiveSoft;
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : _categoryLabel();
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
                color: soft.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.south_west, size: 16, color: color),
            ),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(isPending ? '見込み' : '確定',
                            style: TextStyle(
                                fontSize: 10,
                                color: color,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(title,
                            style: V2Typography.bodyStrong,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${formatMonthDay(t.date)} · ${_categoryLabel()}・${t.paymentMethod}',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('+${formatYen(t.amount)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}
