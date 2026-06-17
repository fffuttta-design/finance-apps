import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/transaction_repository.dart';
import '../../screens/income_input_screen.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

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
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  List<core.Transaction> get _monthIncome => _transactions
      .where((t) =>
          t.type == core.TransactionType.income &&
          t.date.year == _month.year &&
          t.date.month == _month.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> _openInput() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncomeInputScreen()),
    );
    if (mounted) await _load();
  }

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
          vertical: V2Spacing.xl, horizontal: V2Spacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(isBusiness ? '売上' : '収入',
                      style: V2Typography.h1
                          .copyWith(color: V2Colors.textPrimary)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _openInput,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(isBusiness ? '売上を追加' : '収入を追加'),
                    style: FilledButton.styleFrom(
                        backgroundColor: widget.accent),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.lg),
              // サマリーカード
              Container(
                padding: const EdgeInsets.all(V2Spacing.xl),
                decoration: BoxDecoration(
                  color: V2Colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: V2Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${_month.month}月の合計',
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
                            fontSize: 30,
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
              const SizedBox(height: V2Spacing.lg),
              // 明細
              Container(
                padding: const EdgeInsets.all(V2Spacing.lg),
                decoration: BoxDecoration(
                  color: V2Colors.surface,
                  borderRadius: BorderRadius.circular(16),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: soft.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.south_west, size: 18, color: color),
            ),
            const SizedBox(width: V2Spacing.md),
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
