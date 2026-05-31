import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/transaction_repository.dart';
import '../../data/ui_preferences.dart';
import '../../screens/account_detail_screen.dart';
import '../../screens/transfer_input_screen.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 ネイティブ資産タブ。
///
/// レイアウト:
/// - 上部: 総資産 + 内訳サマリー
/// - 中央: 種別別（銀行/現金/電子マネー）の口座カード
///   各口座は現在残高 + ロゴ + 行タップで通帳画面（v1 AccountDetailScreen）に遷移
class V2AssetScreen extends StatefulWidget {
  final Color accent;
  const V2AssetScreen({super.key, required this.accent});

  @override
  State<V2AssetScreen> createState() => _V2AssetScreenState();
}

class _V2AssetScreenState extends State<V2AssetScreen>
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

  /// 各口座の現在残高（startingBalance + 全期間の取引差分、振替対応）
  int _balanceOf(core.RegisteredBankAccount b) {
    int delta = 0;
    for (final t in _transactions) {
      if (t.type == core.TransactionType.transfer) {
        if (t.transferFromAccount == b.name) delta -= t.amount;
        if (t.transferToAccount == b.name) delta += t.amount;
        continue;
      }
      if (t.paymentMethod != b.name) continue;
      if (t.type == core.TransactionType.income) {
        delta += t.amount;
      } else {
        delta -= t.amount;
      }
    }
    return (b.startingBalance ?? 0) + delta;
  }

  Future<void> _openDetail(core.RegisteredBankAccount b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AccountDetailScreen(account: b)),
    );
    if (mounted) await _load();
  }

  Future<void> _openTransferInput() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransferInputScreen()),
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
    final all = _payments.bankAccounts;
    // hideInactive: 残高 0 でかつ inactive のみ隠す
    final banks = all
        .where((b) {
          if (!hideInactive) return true;
          final bal = _balanceOf(b);
          return !(b.inactive && bal <= 0);
        })
        .toList();
    final bankList = banks
        .where((b) => b.accountType == core.AccountType.bank)
        .toList();
    final cashList = banks
        .where((b) => b.accountType == core.AccountType.cash)
        .toList();
    final emoneyList = banks
        .where((b) => b.accountType == core.AccountType.emoney)
        .toList();
    final totalAsset =
        banks.fold<int>(0, (s, b) => s + _balanceOf(b));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 総資産サマリー ──────────────────
          V2Card(
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: V2Colors.accentSoft,
                    borderRadius:
                        BorderRadius.circular(V2Spacing.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                      color: widget.accent),
                ),
                const SizedBox(width: V2Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('総資産',
                          style: V2Typography.caption.copyWith(
                              color: V2Colors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text(formatYen(totalAsset),
                          style: V2Typography.kpiValue.copyWith(
                              color: V2Colors.textPrimary)),
                    ],
                  ),
                ),
                _SummaryChip(
                    label: '銀行',
                    count: bankList.length,
                    total: bankList.fold<int>(
                        0, (s, b) => s + _balanceOf(b))),
                const SizedBox(width: V2Spacing.sm),
                _SummaryChip(
                    label: '現金',
                    count: cashList.length,
                    total: cashList.fold<int>(
                        0, (s, b) => s + _balanceOf(b))),
                const SizedBox(width: V2Spacing.sm),
                _SummaryChip(
                    label: '電子',
                    count: emoneyList.length,
                    total: emoneyList.fold<int>(
                        0, (s, b) => s + _balanceOf(b))),
                const SizedBox(width: V2Spacing.md),
                OutlinedButton.icon(
                  onPressed: _openTransferInput,
                  icon: const Icon(Icons.swap_horiz, size: 14),
                  label: const Text('振替'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
          // ── 種別別セクション ──────────────────
          if (bankList.isNotEmpty)
            _TypeSection(
              title: '銀行口座',
              icon: Icons.account_balance,
              color: V2Colors.badgeBlue,
              bg: V2Colors.badgeBlueSoft,
              accounts: bankList,
              balanceOf: _balanceOf,
              onTap: _openDetail,
            ),
          if (bankList.isNotEmpty && cashList.isNotEmpty)
            const SizedBox(height: V2Spacing.lg),
          if (cashList.isNotEmpty)
            _TypeSection(
              title: '現金（財布）',
              icon: Icons.wallet,
              color: V2Colors.badgeAmber,
              bg: V2Colors.badgeAmberSoft,
              accounts: cashList,
              balanceOf: _balanceOf,
              onTap: _openDetail,
            ),
          if (cashList.isNotEmpty && emoneyList.isNotEmpty)
            const SizedBox(height: V2Spacing.lg),
          if (emoneyList.isNotEmpty)
            _TypeSection(
              title: '電子マネー',
              icon: Icons.qr_code_2,
              color: V2Colors.badgePurple,
              bg: V2Colors.badgePurpleSoft,
              accounts: emoneyList,
              balanceOf: _balanceOf,
              onTap: _openDetail,
            ),
          if (banks.isEmpty)
            V2Card(
              child: SizedBox(
                height: 140,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inbox_outlined,
                          size: 36, color: V2Colors.textMuted),
                      const SizedBox(height: V2Spacing.sm),
                      Text('ウォレットが未登録です',
                          style: V2Typography.caption.copyWith(
                              color: V2Colors.textSecondary)),
                      const SizedBox(height: V2Spacing.xs),
                      Text('設定 → ウォレット から追加できます',
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: V2Colors.surfaceMuted,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textSecondary)),
              const SizedBox(width: 3),
              Text('$count',
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textMuted,
                      fontFeatures: V2Typography.tabularNums)),
            ],
          ),
          Text(formatYen(total),
              style: V2Typography.caption.copyWith(
                  color: V2Colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Color bg;
  final List<core.RegisteredBankAccount> accounts;
  final int Function(core.RegisteredBankAccount) balanceOf;
  final void Function(core.RegisteredBankAccount) onTap;
  const _TypeSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.bg,
    required this.accounts,
    required this.balanceOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal =
        accounts.fold<int>(0, (s, b) => s + balanceOf(b));
    return V2Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.sm),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius:
                        BorderRadius.circular(V2Spacing.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: V2Spacing.sm),
                Text(title,
                    style: V2Typography.h2.copyWith(
                        color: V2Colors.textPrimary)),
                const SizedBox(width: V2Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('${accounts.length}',
                      style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Text(formatYen(subtotal),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: V2Colors.textPrimary,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
          ),
          for (final b in accounts)
            _AccountRow(
              b: b,
              balance: balanceOf(b),
              onTap: () => onTap(b),
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatefulWidget {
  final core.RegisteredBankAccount b;
  final int balance;
  final VoidCallback onTap;
  const _AccountRow({
    required this.b,
    required this.balance,
    required this.onTap,
  });

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? V2Colors.hover : V2Colors.surface,
            border: const Border(
                top: BorderSide(color: V2Colors.divider, width: 1)),
          ),
          child: Row(
            children: [
              BrandLogo(
                iconUrl: widget.b.iconUrl,
                fallbackIcon: Icons.account_balance,
                size: 28,
                borderRadius: 4,
              ),
              const SizedBox(width: V2Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(widget.b.name,
                            style: V2Typography.bodyStrong),
                        if (widget.b.last4 != null &&
                            widget.b.last4!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('•••• ${widget.b.last4}',
                              style: V2Typography.micro.copyWith(
                                  color: V2Colors.textMuted,
                                  fontFeatures:
                                      V2Typography.tabularNums)),
                        ],
                        if (widget.b.inactive) ...[
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
                                style: V2Typography.micro.copyWith(
                                    color: V2Colors.textMuted)),
                          ),
                        ],
                      ],
                    ),
                    if (widget.b.memo != null &&
                        widget.b.memo!.isNotEmpty)
                      Text(widget.b.memo!,
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Text(formatYen(widget.balance),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: widget.balance >= 0
                          ? V2Colors.textPrimary
                          : V2Colors.negative,
                      fontFeatures: V2Typography.tabularNums)),
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
