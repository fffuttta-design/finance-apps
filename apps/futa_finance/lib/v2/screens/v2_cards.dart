import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/transaction_repository.dart';
import '../../data/ui_preferences.dart';
import '../../screens/card_detail_screen.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 クレカタブ。
/// 上部: 当月利用合計 + カード数。
/// 中央: 各カードの行（ロゴ / 名前 / 引落日 / 当月利用 / chevron）
/// 行タップで v1 CardDetailScreen に遷移（明細 + 請求推移）。
class V2CardsScreen extends StatefulWidget {
  final Color accent;
  const V2CardsScreen({super.key, required this.accent});

  @override
  State<V2CardsScreen> createState() => _V2CardsScreenState();
}

class _V2CardsScreenState extends State<V2CardsScreen>
    with ModeAwareMixin {
  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig _payments =
      core.PaymentMethodsConfig.empty();
  bool _loading = true;

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
    PaymentsChangeNotifier.instance.addListener(_load);
    UiPreferences.instance.addListener(_onUiPrefs);
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    UiPreferences.instance.removeListener(_onUiPrefs);
    super.dispose();
  }

  void _onUiPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final payments = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _loading = false;
    });
  }

  /// 各カードの当月利用額
  int _currentMonthUsage(core.RegisteredCreditCard c) {
    final now = DateTime.now();
    return _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == c.name &&
            t.date.year == now.year &&
            t.date.month == now.month)
        .fold<int>(0, (s, t) => s + t.amount);
  }

  /// 指定年月の利用額（月別推移用）
  int _usageOfMonth(core.RegisteredCreditCard c, DateTime month) {
    return _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == c.name &&
            t.date.year == month.year &&
            t.date.month == month.month)
        .fold<int>(0, (s, t) => s + t.amount);
  }

  Future<void> _openDetail(core.RegisteredCreditCard c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CardDetailScreen(card: c)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final hideInactive = UiPreferences.instance.hideInactive;
    final allCards = _payments.creditCards;
    final cards = allCards
        .where((c) {
          if (!hideInactive) return true;
          final usage = _currentMonthUsage(c);
          final accum = usage + c.displayBalance;
          return !(c.inactive && accum <= 0);
        })
        .toList();
    final monthTotal = cards.fold<int>(
        0, (s, c) => s + _currentMonthUsage(c));
    final now = DateTime.now();

    // 過去 6 ヶ月の合算（推移）
    final last6 = List.generate(6, (i) {
      final m = DateTime(now.year, now.month - 5 + i);
      final total = cards.fold<int>(
          0, (s, c) => s + _usageOfMonth(c, m));
      return MapEntry(m, total);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 当月利用サマリー + 過去 6 ヶ月推移 ──
          V2Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: V2Colors.badgeRedSoft,
                        borderRadius:
                            BorderRadius.circular(V2Spacing.radiusSm),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.credit_card,
                          size: 18, color: V2Colors.negative),
                    ),
                    const SizedBox(width: V2Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('当月のクレカ利用',
                              style: V2Typography.caption.copyWith(
                                  color: V2Colors.textSecondary,
                                  fontWeight: FontWeight.w600)),
                          Text('-${formatYen(monthTotal)}',
                              style: V2Typography.kpiValue
                                  .copyWith(
                                      color: V2Colors.negative)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: V2Colors.surfaceMuted,
                        borderRadius:
                            BorderRadius.circular(V2Spacing.radiusSm),
                      ),
                      child: Text('${cards.length} 枚',
                          style: V2Typography.caption.copyWith(
                              color: V2Colors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: V2Spacing.md),
                const Divider(height: 1),
                const SizedBox(height: V2Spacing.md),
                Text('過去 6 ヶ月の請求合算',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: V2Spacing.sm),
                Row(
                  children: [
                    for (final e in last6) ...[
                      Expanded(
                          child: _MonthBar(
                              month: e.key,
                              value: e.value,
                              maxValue: last6.fold<int>(
                                  0,
                                  (m, x) =>
                                      x.value > m ? x.value : m),
                              accent: widget.accent)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
          // ── カード一覧 ──
          V2Card(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(V2Spacing.lg,
                      V2Spacing.md, V2Spacing.lg, V2Spacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.credit_card_outlined,
                          size: 18, color: widget.accent),
                      const SizedBox(width: V2Spacing.sm),
                      Text('クレジットカード',
                          style: V2Typography.h2),
                    ],
                  ),
                ),
                if (cards.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: V2Spacing.sm),
                        Text('クレジットカードが未登録です',
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.textSecondary)),
                        const SizedBox(height: V2Spacing.xs),
                        Text('設定 → ウォレット から追加できます',
                            style: V2Typography.micro.copyWith(
                                color: V2Colors.textMuted)),
                      ],
                    ),
                  )
                else
                  for (final c in cards)
                    _CardRow(
                      c: c,
                      usage: _currentMonthUsage(c),
                      onTap: () => _openDetail(c),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  final DateTime month;
  final int value;
  final int maxValue;
  final Color accent;
  const _MonthBar({
    required this.month,
    required this.value,
    required this.maxValue,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final ratio =
        maxValue == 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    final isCurrent = month.year == DateTime.now().year &&
        month.month == DateTime.now().month;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          // 棒
          SizedBox(
            height: 56,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: ratio == 0 ? 0.02 : ratio,
                child: Container(
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? accent
                        : accent.withValues(alpha: 0.35),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${month.month}月',
              style: V2Typography.micro.copyWith(
                  color: isCurrent
                      ? accent
                      : V2Colors.textMuted,
                  fontWeight: isCurrent
                      ? FontWeight.w800
                      : FontWeight.w500)),
          Text(
              value == 0
                  ? '0'
                  : '${(value / 1000).round()}k',
              style: V2Typography.micro.copyWith(
                  color: V2Colors.textMuted,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _CardRow extends StatefulWidget {
  final core.RegisteredCreditCard c;
  final int usage;
  final VoidCallback onTap;
  const _CardRow({
    required this.c,
    required this.usage,
    required this.onTap,
  });

  @override
  State<_CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<_CardRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accum = widget.usage + widget.c.displayBalance;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? V2Colors.hover : V2Colors.surface,
            border: const Border(
                top: BorderSide(
                    color: V2Colors.divider, width: 1)),
          ),
          child: Row(
            children: [
              BrandLogo(
                iconUrl: widget.c.iconUrl,
                fallbackIcon: Icons.credit_card,
                size: 32,
                borderRadius: 4,
              ),
              const SizedBox(width: V2Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(widget.c.name,
                            style: V2Typography.bodyStrong),
                        if (widget.c.last4 != null &&
                            widget.c.last4!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('•••• ${widget.c.last4}',
                              style: V2Typography.micro.copyWith(
                                  color: V2Colors.textMuted,
                                  fontFeatures:
                                      V2Typography.tabularNums)),
                        ],
                        if (widget.c.inactive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: V2Colors.surfaceMuted,
                              borderRadius:
                                  BorderRadius.circular(3),
                            ),
                            child: Text('未使用',
                                style: V2Typography.micro
                                    .copyWith(
                                        color:
                                            V2Colors.textMuted)),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (widget.c.paymentDay != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: V2Colors.surfaceMuted,
                              borderRadius:
                                  BorderRadius.circular(3),
                            ),
                            child: Text(
                                '引落 ${widget.c.paymentDay}日',
                                style: V2Typography.micro
                                    .copyWith(
                                        color: V2Colors
                                            .textSecondary,
                                        fontFeatures:
                                            V2Typography
                                                .tabularNums)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (widget.c.memo != null &&
                            widget.c.memo!.isNotEmpty)
                          Expanded(
                            child: Text(widget.c.memo!,
                                style: V2Typography.micro
                                    .copyWith(
                                        color:
                                            V2Colors.textMuted),
                                overflow:
                                    TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('当月利用',
                      style: V2Typography.micro.copyWith(
                          color: V2Colors.textSecondary)),
                  Text('-${formatYen(widget.usage)}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: V2Colors.negative,
                          fontFeatures:
                              V2Typography.tabularNums)),
                  if (accum != widget.usage)
                    Text('累積 -${formatYen(accum)}',
                        style: V2Typography.micro.copyWith(
                            color: V2Colors.textMuted,
                            fontFeatures:
                                V2Typography.tabularNums)),
                ],
              ),
              const SizedBox(width: V2Spacing.sm),
              const Icon(Icons.chevron_right,
                  size: 18, color: V2Colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
