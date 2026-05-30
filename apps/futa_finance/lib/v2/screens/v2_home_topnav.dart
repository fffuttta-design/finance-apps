import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../data/app_mode.dart';
import '../../data/monthly_snapshot_repository.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/expense_input_screen.dart';
import '../../screens/income_input_screen.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// マネフォ ME 風のホーム画面（v2.1）。
/// 3 カラム構成、v1 の Repository から実データを取得して表示。
/// - 左: 総資産 + 口座/カード残高一覧
/// - 中央: カンタン入力（v1 入力モーダル呼出） + 最新入出金 + 月の収支
/// - 右: 今月の予算（v1 未実装、placeholder）+ お知らせ
class V2HomeTopNavScreen extends StatefulWidget {
  /// アクセント色（事業=青 / 個人=オレンジ）
  final Color accent;

  const V2HomeTopNavScreen({super.key, required this.accent});

  @override
  State<V2HomeTopNavScreen> createState() => _V2HomeTopNavScreenState();
}

class _V2HomeTopNavScreenState extends State<V2HomeTopNavScreen>
    with ModeAwareMixin {
  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;
  final _snapshotRepo = MonthlySnapshotRepository.instance;

  StreamSubscription<List<Transaction>>? _sub;
  List<Transaction> _transactions = [];
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  MonthlySnapshotConfig _snapshots = MonthlySnapshotConfig.empty();
  bool _loading = true;

  /// 表示月（既定は今月、月切替で前後）
  late DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

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

  /// 月切替（外側 widget から呼べる公開メソッド）
  void shiftMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final payments = await _settings.loadPayments();
    final snapshots = await _snapshotRepo.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _snapshots = snapshots;
      _loading = false;
    });
  }

  // ── 計算ヘルパー ──────────────────────────

  /// 各銀行口座の「現在残高」（startingBalance + 全期間の取引差分、振替対応）。
  int _bankBalanceOf(RegisteredBankAccount b) {
    int delta = 0;
    for (final t in _transactions) {
      if (t.type == TransactionType.transfer) {
        if (t.transferFromAccount == b.name) delta -= t.amount;
        if (t.transferToAccount == b.name) delta += t.amount;
        continue;
      }
      if (t.paymentMethod != b.name) continue;
      if (t.type == TransactionType.income) {
        delta += t.amount;
      } else {
        delta -= t.amount;
      }
    }
    return (b.startingBalance ?? 0) + delta;
  }

  /// クレカ別の当月利用額。
  Map<String, int> _cardUsageOfMonth(DateTime month) {
    final names = _payments.creditCards.map((c) => c.name).toSet();
    final out = <String, int>{};
    for (final t in _transactions) {
      if (t.date.year != month.year || t.date.month != month.month) continue;
      if (t.type != TransactionType.expense) continue;
      if (!names.contains(t.paymentMethod)) continue;
      out[t.paymentMethod] = (out[t.paymentMethod] ?? 0) + t.amount;
    }
    return out;
  }

  List<Transaction> _monthTxns(DateTime month) => _transactions
      .where((t) => t.date.year == month.year && t.date.month == month.month)
      .toList();

  // ── 入力モーダル呼び出し（v1 機能の再利用） ──

  void _openExpenseInput() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseInputScreen()),
    );
  }

  void _openIncomeInput() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncomeInputScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 1000;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 240, child: _LeftAssetSummary(state: this)),
            const SizedBox(width: V2Spacing.lg),
            Expanded(child: _CenterColumn(state: this)),
            const SizedBox(width: V2Spacing.lg),
            SizedBox(width: 240, child: _RightSidebar(state: this)),
          ],
        );
      }
      return Column(
        children: [
          _LeftAssetSummary(state: this),
          const SizedBox(height: V2Spacing.lg),
          _CenterColumn(state: this),
          const SizedBox(height: V2Spacing.lg),
          _RightSidebar(state: this),
        ],
      );
    });
  }
}

// ═════════════════════════════════════════════════
// 左カラム: 総資産 + 口座/カード一覧
// ═════════════════════════════════════════════════

class _LeftAssetSummary extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _LeftAssetSummary({required this.state});

  @override
  Widget build(BuildContext context) {
    // 総資産 = 全銀行口座の現在残高合計
    final totalAsset = state._payments.bankAccounts
        .fold<int>(0, (s, b) => s + state._bankBalanceOf(b));

    // 前月末時点との差分（前月末日 23:59 を cutoff）
    final today = DateTime.now();
    final prevEnd = DateTime(today.year, today.month, 1)
        .subtract(const Duration(seconds: 1));
    final prevAsset = _assetAt(prevEnd);
    final delta = totalAsset - prevAsset;

    // クレカ当月利用
    final cardUsage = state._cardUsageOfMonth(state._selectedMonth);

    return V2Card(
      padding: const EdgeInsets.all(V2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('総資産',
              style: V2Typography.bodyStrong.copyWith(
                  color: V2Colors.textPrimary, fontSize: 13)),
          const SizedBox(height: V2Spacing.md),
          Text(formatYen(totalAsset),
              style: V2Typography.kpiValue
                  .copyWith(color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.sm),
          Row(
            children: [
              Icon(
                  delta >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 14,
                  color: delta >= 0
                      ? V2Colors.positive
                      : V2Colors.negative),
              const SizedBox(width: 4),
              Text(formatYen(delta, withSign: true),
                  style: V2Typography.caption.copyWith(
                      color: delta >= 0
                          ? V2Colors.positive
                          : V2Colors.negative,
                      fontWeight: FontWeight.w700,
                      fontFeatures: V2Typography.tabularNums)),
              const SizedBox(width: V2Spacing.xs),
              Text('前月末比',
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textSecondary)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: V2Spacing.md),
            child: Divider(height: 1),
          ),
          // 銀行口座リスト
          for (final b in state._payments.bankAccounts)
            _AssetTile(
              icon: b.iconUrl,
              label: b.name,
              value: formatYen(state._bankBalanceOf(b)),
              valueColor: V2Colors.textPrimary,
            ),
          // クレカ当月利用（マイナス表示）
          for (final c in state._payments.creditCards)
            if ((cardUsage[c.name] ?? 0) > 0)
              _AssetTile(
                icon: c.iconUrl,
                label: c.name,
                value: '-${formatYen(cardUsage[c.name] ?? 0)}',
                valueColor: V2Colors.negative,
              ),
          if (state._payments.bankAccounts.isEmpty &&
              state._payments.creditCards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '口座が未登録です。設定 → ウォレット から追加してください。',
                style: V2Typography.micro.copyWith(
                    color: V2Colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// 指定時刻時点の総資産。
  int _assetAt(DateTime cutoff) {
    final banks = state._payments.bankAccounts;
    int total = 0;
    for (final b in banks) {
      int delta = 0;
      for (final t in state._transactions) {
        if (t.date.isAfter(cutoff)) continue;
        if (t.type == TransactionType.transfer) {
          if (t.transferFromAccount == b.name) delta -= t.amount;
          if (t.transferToAccount == b.name) delta += t.amount;
          continue;
        }
        if (t.paymentMethod != b.name) continue;
        if (t.type == TransactionType.income) {
          delta += t.amount;
        } else {
          delta -= t.amount;
        }
      }
      total += (b.startingBalance ?? 0) + delta;
    }
    return total;
  }
}

class _AssetTile extends StatelessWidget {
  final String? icon;
  final String label;
  final String value;
  final Color valueColor;
  const _AssetTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          BrandLogo(
            iconUrl: icon,
            fallbackIcon: Icons.account_balance,
            size: 16,
            borderRadius: 4,
          ),
          const SizedBox(width: V2Spacing.sm),
          Expanded(
            child: Text(label,
                style: V2Typography.caption,
                overflow: TextOverflow.ellipsis),
          ),
          Text(value,
              style: V2Typography.caption.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 中央カラム: カンタン入力 + 最新の入出金 + 月の収支
// ═════════════════════════════════════════════════

class _CenterColumn extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _CenterColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final monthTxns = state._monthTxns(state._selectedMonth);
    final incomeConfirmed = monthTxns
        .where((t) => t.type == TransactionType.income && !t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final incomePending = monthTxns
        .where((t) => t.type == TransactionType.income && t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final income = incomeConfirmed + incomePending;
    final expense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    final net = income - expense;
    final isBlack = net >= 0;

    // 最新の入出金: 日付降順で最新 5 件
    final recent = [...state._transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final recentTop = recent.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── カンタン入力 ──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 18, color: state.widget.accent),
                  const SizedBox(width: V2Spacing.sm),
                  Text('カンタン入力',
                      style: V2Typography.h2
                          .copyWith(color: V2Colors.textPrimary)),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              Wrap(
                spacing: V2Spacing.sm,
                runSpacing: V2Spacing.sm,
                children: [
                  _QuickInputButton(
                    label: isBusiness ? '経費を記録' : '支出を記録',
                    icon: Icons.remove_circle_outline,
                    fg: V2Colors.negative,
                    bg: V2Colors.negativeSoft,
                    onTap: state._openExpenseInput,
                  ),
                  _QuickInputButton(
                    label: isBusiness ? '売上を記録' : '収入を記録',
                    icon: Icons.add_circle_outline,
                    fg: V2Colors.positive,
                    bg: V2Colors.positiveSoft,
                    onTap: state._openIncomeInput,
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.sm),
              Text(
                isBusiness
                    ? '銀行/カードの支払いや、入金を記録します'
                    : '日々の支出や収入を記録します',
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        // ── 最新の入出金 ──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('最新の入出金',
                      style: V2Typography.h2
                          .copyWith(color: V2Colors.textPrimary)),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              if (recentTop.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('取引記録はまだありません',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary)),
                )
              else
                for (final t in recentTop) _TransactionRow(t: t),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        // ── 月の収支 ──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left, size: 18),
                    onPressed: () => state.shiftMonth(-1),
                  ),
                  Text('${state._selectedMonth.month}月の収支',
                      style: V2Typography.h2
                          .copyWith(color: V2Colors.textPrimary)),
                  const SizedBox(width: V2Spacing.sm),
                  Text(
                    '(${state._selectedMonth.year}年)',
                    style: V2Typography.caption,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    onPressed: () => state.shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.sm),
              _SummaryRow(
                  label: isBusiness ? '当月売上' : '当月収入',
                  value: formatYen(income, withSign: true),
                  color: V2Colors.positive),
              if (incomePending > 0)
                Padding(
                  padding: const EdgeInsets.only(left: V2Spacing.lg),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top,
                          size: 12, color: V2Colors.warning),
                      const SizedBox(width: 4),
                      Text('うち見込み',
                          style: V2Typography.micro
                              .copyWith(color: V2Colors.warning)),
                      const Spacer(),
                      Text(formatYen(incomePending, withSign: true),
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.warning,
                              fontWeight: FontWeight.w700,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
              const Divider(height: 1),
              _SummaryRow(
                  label: isBusiness ? '当月経費' : '当月支出',
                  value: formatYen(-expense, withSign: true),
                  color: V2Colors.negative),
              const Divider(height: 1),
              _SummaryRow(
                  label: '当月収支',
                  value: formatYen(net, withSign: true),
                  color: isBlack ? V2Colors.positive : V2Colors.negative,
                  emphasize: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickInputButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;
  const _QuickInputButton({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.md, vertical: V2Spacing.sm),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            border: Border.all(color: fg.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: V2Spacing.sm),
              Text(label,
                  style: V2Typography.body.copyWith(
                      color: fg, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Transaction t;
  const _TransactionRow({required this.t});

  String _typeLabel() {
    switch (t.type) {
      case TransactionType.income:
        return '収入';
      case TransactionType.expense:
        return '支出';
      case TransactionType.transfer:
        return '振替';
    }
  }

  String _categoryLabel() {
    final major = t.category.major.trim();
    final sub = t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return _typeLabel();
    if (sub.isEmpty) return major;
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final color = isTransfer
        ? V2Colors.textBody
        : (isIncome ? V2Colors.positive : V2Colors.negative);
    final sign = isTransfer ? '' : (isIncome ? '+' : '-');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: V2Colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text('${t.date.month}/${t.date.day}',
                  style: V2Typography.caption.copyWith(
                      fontFeatures: V2Typography.tabularNums))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
            ),
            child: Text(
              _categoryLabel(),
              style: V2Typography.micro,
            ),
          ),
          const SizedBox(width: V2Spacing.md),
          Expanded(
            child: Text(
              t.description.isEmpty ? t.paymentMethod : t.description,
              style: V2Typography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$sign${formatYen(t.amount)}',
              style: V2Typography.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool emphasize;
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(label,
              style: emphasize
                  ? V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 14)
                  : V2Typography.body),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontSize: emphasize ? 20 : 16,
                fontWeight:
                    emphasize ? FontWeight.w800 : FontWeight.w700,
                color: color,
                fontFeatures: V2Typography.tabularNums,
              )),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 右カラム: 月初残高 + お知らせ
// ═════════════════════════════════════════════════

class _RightSidebar extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _RightSidebar({required this.state});

  @override
  Widget build(BuildContext context) {
    final snap = state._snapshots
        .forMonth(state._selectedMonth.year, state._selectedMonth.month);
    return Column(
      children: [
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${state._selectedMonth.month}月の月初残高',
                  style: V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 13)),
              const SizedBox(height: V2Spacing.sm),
              if (snap != null)
                Text(formatYen(snap.initialBalance),
                    style: V2Typography.h1.copyWith(
                        color: V2Colors.textPrimary,
                        fontFeatures: V2Typography.tabularNums))
              else
                Text('未記録',
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.warning)),
              const SizedBox(height: V2Spacing.xs),
              Text(
                snap != null
                    ? 'スナップショット記録済'
                    : '集計 → 月初残高を記録するから設定できます',
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('お知らせ',
                  style: V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 13)),
              const SizedBox(height: V2Spacing.sm),
              Text(
                  'v2.1 ホームに実データを反映中。\n'
                  '他タブも順次 v2.1 ネイティブに移植予定。',
                  style: V2Typography.caption),
            ],
          ),
        ),
      ],
    );
  }
}
