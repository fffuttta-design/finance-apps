import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../data/app_mode.dart';
import '../../data/monthly_snapshot_repository.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 新デザイン（リッチUI）のホーム画面。
///
/// 既存の [TransactionRepository] などからデータを取得して描画する独立画面。
/// 現行ホーム（V2HomeTopNavScreen）には一切手を入れず、トグルで切替える。
/// 主役カード＝「今月の収支」（総資産は資産タブへ）。旧ホームの主要な数字
/// （見込み収入・推定/実測残高・固定費）も引き継ぐ。
class RichHomeScreen extends StatefulWidget {
  /// アクセント色（事業=青 / 個人=オレンジ）
  final Color accent;
  const RichHomeScreen({super.key, required this.accent});

  @override
  State<RichHomeScreen> createState() => _RichHomeScreenState();
}

class _RichHomeScreenState extends State<RichHomeScreen> with ModeAwareMixin {
  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;
  final _snapshotRepo = MonthlySnapshotRepository.instance;

  StreamSubscription<List<Transaction>>? _sub;
  List<Transaction> _transactions = [];
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  MonthlySnapshotConfig _snapshots = MonthlySnapshotConfig.empty();
  List<Subscription> _subs = [];
  bool _loading = true;
  String? _error;

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
    PaymentsChangeNotifier.instance.addListener(_load);
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await (() async {
        final txns = await _txRepo.loadAll();
        final payments = await _settings.loadPayments();
        final snapshots = await _snapshotRepo.load();
        final subs = await SubscriptionRepository.instance.load();
        return (txns, payments, snapshots, subs);
      })()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _transactions = data.$1;
        _payments = data.$2;
        _snapshots = data.$3;
        _subs = data.$4.subscriptions;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  int _subsTotalForMonth(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    return _subs.fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
  }

  List<Transaction> _monthTxns(DateTime m) => _transactions
      .where((t) => t.date.year == m.year && t.date.month == m.month)
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: V2Colors.textMuted),
              const SizedBox(height: 12),
              Text('読み込みに失敗しました\n$_error',
                  textAlign: TextAlign.center, style: V2Typography.caption),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('再読み込み'),
              ),
            ],
          ),
        ),
      );
    }

    final isBusiness = AppModeManager.instance.current == AppMode.business;
    final accent = widget.accent;
    final monthTxns = _monthTxns(_month);

    // 収支（見込み込みの売上・経費）
    final incomeConfirmed = monthTxns
        .where((t) => t.type == TransactionType.income && !t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final incomePending = monthTxns
        .where((t) => t.type == TransactionType.income && t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final income = incomeConfirmed + incomePending;
    final txExpense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    final subTotal = _subsTotalForMonth(_month);
    final expense = txExpense + subTotal;
    final net = income - expense;

    // 推定残高 / 実測残高（旧ホームと同じ）
    final now = DateTime.now();
    final isCurrentMonth =
        _month.year == now.year && _month.month == now.month;
    final snap = _snapshots.forMonth(_month.year, _month.month);
    final initialBalance = snap?.initialBalance ?? 0;
    final projected = initialBalance + income - expense;
    final actual = isCurrentMonth
        ? _payments.bankAccounts
            .fold<int>(0, (s, b) => s + (b.displayBalance ?? 0))
        : projected;
    final diff = actual - projected;

    // カテゴリ内訳（大カテゴリ別・固定費込み）
    final byMajor = <String, int>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
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
    final byMajorTotal = byMajor.values.fold<int>(0, (s, v) => s + v);

    // 最近の取引（当月・日付降順・最大8件）
    final recent = [...monthTxns]..sort((a, b) => b.date.compareTo(a.date));
    final recentTop = recent.take(8).toList();

    final hero = _HeroCard(
      accent: accent,
      monthLabel: '${_month.year}年${_month.month}月',
      net: net,
      income: income,
      incomePending: incomePending,
      expense: expense,
      isBusiness: isBusiness,
      onPrev: () => _shiftMonth(-1),
      onNext: () => _shiftMonth(1),
    );

    final balanceCard = _BalanceCard(
      hasSnap: snap != null,
      isCurrentMonth: isCurrentMonth,
      projected: projected,
      actual: actual,
      diff: diff,
      fixedCost: subTotal,
    );

    final categoryCard = _CategoryCard(
      entries: majorEntries,
      total: byMajorTotal,
      accent: accent,
    );

    final recentCard = _RecentCard(
      isBusiness: isBusiness,
      month: _month,
      txns: recentTop,
      onTapTxn: (t) async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transaction: t)),
        );
        if (changed == true) await _load();
      },
      onSeeAll: () async {
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
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.xl, horizontal: V2Spacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: LayoutBuilder(builder: (ctx, c) {
            final wide = c.maxWidth >= 880;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                const SizedBox(height: V2Spacing.lg),
                balanceCard,
                const SizedBox(height: V2Spacing.lg),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: categoryCard),
                        const SizedBox(width: V2Spacing.lg),
                        Expanded(child: recentCard),
                      ],
                    ),
                  )
                else ...[
                  categoryCard,
                  const SizedBox(height: V2Spacing.lg),
                  recentCard,
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 今月の収支ヒーローカード（アクセント色の主役カード）
// ═════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final Color accent;
  final String monthLabel;
  final int net;
  final int income;
  final int incomePending;
  final int expense;
  final bool isBusiness;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _HeroCard({
    required this.accent,
    required this.monthLabel,
    required this.net,
    required this.income,
    required this.incomePending,
    required this.expense,
    required this.isBusiness,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    const onAccent = Colors.white;
    final onAccentSoft = Colors.white.withValues(alpha: 0.78);
    final tileBg = Colors.white.withValues(alpha: 0.13);
    final isBlack = net >= 0;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.xl),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('今月の収支',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onAccentSoft)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(isBlack ? '黒字' : '赤字',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: onAccent)),
              ),
              const Spacer(),
              _RoundIconButton(
                  icon: Icons.chevron_left, onTap: onPrev, color: onAccent),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(monthLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onAccentSoft)),
              ),
              _RoundIconButton(
                  icon: Icons.chevron_right, onTap: onNext, color: onAccent),
            ],
          ),
          const SizedBox(height: 4),
          Text(formatYen(net, withSign: true),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: onAccent,
                fontFeatures: V2Typography.tabularNums,
              )),
          if (incomePending > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.hourglass_top, size: 14, color: onAccentSoft),
                const SizedBox(width: 5),
                Text(
                    '${isBusiness ? '売上' : '収入'}のうち見込み ${formatYen(incomePending, withSign: true)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onAccentSoft,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
          ],
          const SizedBox(height: V2Spacing.lg),
          Row(
            children: [
              Expanded(
                child: _HeroSubTile(
                  bg: tileBg,
                  label: isBusiness ? '今月の売上' : '今月の収入',
                  value: formatYen(income),
                  onAccent: onAccent,
                  onAccentSoft: onAccentSoft,
                ),
              ),
              const SizedBox(width: V2Spacing.md),
              Expanded(
                child: _HeroSubTile(
                  bg: tileBg,
                  label: isBusiness ? '今月の経費' : '今月の支出',
                  value: formatYen(expense),
                  onAccent: onAccent,
                  onAccentSoft: onAccentSoft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSubTile extends StatelessWidget {
  final Color bg;
  final String label;
  final String value;
  final Color onAccent;
  final Color onAccentSoft;
  const _HeroSubTile({
    required this.bg,
    required this.label,
    required this.value,
    required this.onAccent,
    required this.onAccentSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: onAccentSoft)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: onAccent,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _RoundIconButton(
      {required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 残高カード（推定残高 / 実測残高 / 固定費）
// ═════════════════════════════════════════════════

class _BalanceCard extends StatelessWidget {
  final bool hasSnap;
  final bool isCurrentMonth;
  final int projected;
  final int actual;
  final int diff;
  final int fixedCost;
  const _BalanceCard({
    required this.hasSnap,
    required this.isCurrentMonth,
    required this.projected,
    required this.actual,
    required this.diff,
    required this.fixedCost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
      ),
      child: Row(
        children: [
          // 推定残高
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('推定残高',
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textSecondary)),
                const SizedBox(height: 4),
                if (hasSnap)
                  Text(formatYen(projected),
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: projected >= 0
                              ? V2Colors.positive
                              : V2Colors.negative,
                          fontFeatures: V2Typography.tabularNums))
                else
                  Text('月初残高 未記録',
                      style: V2Typography.caption
                          .copyWith(color: V2Colors.warning)),
                if (hasSnap && isCurrentMonth) ...[
                  const SizedBox(height: 3),
                  Text(
                      '実測 ${formatYen(actual)} / ${diff == 0 ? '一致 ✓' : '差 ${formatYen(diff, withSign: true)}'}',
                      style: V2Typography.micro.copyWith(
                          color: diff == 0
                              ? V2Colors.positive
                              : V2Colors.warning,
                          fontFeatures: V2Typography.tabularNums)),
                ] else if (!hasSnap) ...[
                  const SizedBox(height: 3),
                  Text('資産タブで記録できます',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                ],
              ],
            ),
          ),
          Container(width: 1, height: 38, color: V2Colors.divider),
          // 固定費
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: V2Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.repeat,
                          size: 15, color: V2Colors.textSecondary),
                      const SizedBox(width: 5),
                      Text('今月の固定費',
                          style: V2Typography.caption
                              .copyWith(color: V2Colors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(formatYen(fixedCost),
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: V2Colors.textPrimary,
                          fontFeatures: V2Typography.tabularNums)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// カテゴリ内訳カード（横スタックバー + 凡例）
// ═════════════════════════════════════════════════

const List<Color> _kCatPalette = [
  Color(0xFF378ADD),
  Color(0xFF1D9E75),
  Color(0xFFEF9F27),
  Color(0xFFD4537E),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
];
const Color _kCatOther = Color(0xFFB4B2A9);

class _CategoryCard extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  final Color accent;
  const _CategoryCard({
    required this.entries,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final top = entries.take(5).toList();
    final restTotal = entries.skip(5).fold<int>(0, (s, e) => s + e.value);
    final segments = <({String name, int value, Color color})>[
      for (int i = 0; i < top.length; i++)
        (name: top[i].key, value: top[i].value, color: _kCatPalette[i]),
      if (restTotal > 0) (name: 'その他', value: restTotal, color: _kCatOther),
    ];

    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('カテゴリ内訳',
              style: V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.lg),
          if (segments.isEmpty || total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('この月の支出はまだありません',
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  for (final s in segments)
                    Expanded(
                      flex: (s.value * 1000 ~/ total).clamp(1, 1000000),
                      child: Container(height: 10, color: s.color),
                    ),
                ],
              ),
            ),
            const SizedBox(height: V2Spacing.lg),
            for (final s in segments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s.name,
                          style: V2Typography.body,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(formatYen(s.value),
                        style: V2Typography.caption.copyWith(
                            color: V2Colors.textSecondary,
                            fontFeatures: V2Typography.tabularNums)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 最近の取引カード
// ═════════════════════════════════════════════════

class _RecentCard extends StatelessWidget {
  final bool isBusiness;
  final DateTime month;
  final List<Transaction> txns;
  final void Function(Transaction) onTapTxn;
  final VoidCallback onSeeAll;
  const _RecentCard({
    required this.isBusiness,
    required this.month,
    required this.txns,
    required this.onTapTxn,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${month.month}月の取引',
                  style:
                      V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
              const Spacer(),
              InkWell(
                onTap: onSeeAll,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Text('すべて見る',
                          style: V2Typography.caption
                              .copyWith(color: V2Colors.accent)),
                      const Icon(Icons.chevron_right,
                          size: 16, color: V2Colors.accent),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.sm),
          if (txns.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('取引記録はまだありません',
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
            )
          else
            for (int i = 0; i < txns.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: V2Colors.divider),
              _TxnRow(t: txns[i], onTap: () => onTapTxn(txns[i])),
            ],
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final Transaction t;
  final VoidCallback onTap;
  const _TxnRow({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final IconData icon;
    final Color tint;
    if (isIncome) {
      icon = Icons.south_west;
      tint = V2Colors.positive;
    } else if (isTransfer) {
      icon = Icons.swap_horiz;
      tint = V2Colors.textSecondary;
    } else {
      icon = Icons.receipt_long_outlined;
      tint = V2Colors.negative;
    }
    final sign = isTransfer ? '' : (isIncome ? '+' : '-');
    final cat = t.category.sub.trim().isNotEmpty
        ? t.category.sub.trim()
        : t.category.major.trim();
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (cat.isNotEmpty ? cat : t.paymentMethod);

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
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: V2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: V2Typography.bodyStrong,
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                  const SizedBox(height: 2),
                  Text(
                      '${formatMonthDay(t.date)} · ${cat.isEmpty ? t.paymentMethod : '$cat・${t.paymentMethod}'}',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('$sign${formatYen(t.amount)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isTransfer ? V2Colors.textBody : tint,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}
