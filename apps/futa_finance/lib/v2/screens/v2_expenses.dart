import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/account_detail_screen.dart';
import '../../screens/card_detail_screen.dart';
import '../../screens/expense_input_screen.dart';
import '../../utils/formatters.dart';
import '../../utils/thousands_separator_input_formatter.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/subscription_edit_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 ネイティブ支出タブ（マネフォクラウド寄りのテーブル中心）。
///
/// レイアウト:
/// - 上部: 月切替バー + 統計（件数 / 合計）
/// - 中央上: 毎月引落予定（固定費 / 変動費）
/// - 中央下: 取引一覧テーブル（日付 / カテゴリ / 内容 / 支払方法 / 金額）
///
/// 機能は v1 と完全同等を目指すが、初版はテーブル表示 + 引落予定のみ。
/// 検索/フィルタ/カテゴリ別集計/グラフは順次追加予定。
class V2ExpensesScreen extends StatefulWidget {
  final Color accent;
  const V2ExpensesScreen({super.key, required this.accent});

  @override
  State<V2ExpensesScreen> createState() => _V2ExpensesScreenState();
}

class _V2ExpensesScreenState extends State<V2ExpensesScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;
  final _settings = SettingsRepository();
  final _subscriptionRepo = SubscriptionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig _payments =
      core.PaymentMethodsConfig.empty();
  core.SubscriptionConfig _subscriptions =
      core.SubscriptionConfig.empty();
  bool _loading = true;

  /// 表示月
  late DateTime _focused =
      DateTime(DateTime.now().year, DateTime.now().month);

  /// 表示中の月キー "YYYY-MM"（変動費の実額参照用）。
  String get _ymKey =>
      '${_focused.year}-${_focused.month.toString().padLeft(2, '0')}';

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
    final payments = await _settings.loadPayments();
    final subs = await _subscriptionRepo.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _subscriptions = subs;
      _loading = false;
    });
  }

  List<core.Transaction> get _monthExpenses {
    return _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.date.year == _focused.year &&
            t.date.month == _focused.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 当月の毎月引落予定（subscription の monthly）
  List<core.Subscription> get _monthlyCharges {
    final list = _subscriptions.subscriptions
        .where(
            (s) => s.cycle == core.SubscriptionCycle.monthly)
        .toList();
    list.sort((a, b) {
      final ad = a.billingDay ?? 32;
      final bd = b.billingDay ?? 32;
      return ad.compareTo(bd);
    });
    return list;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month + delta);
    });
  }

  Future<void> _openInput() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseInputScreen()),
    );
    if (mounted) await _load();
  }

  /// 既存取引の編集は当面サポートなし（v1 で行うか、Phase 9 で対応）
  /// 行タップ時はサマリーをスナックバーで表示するに留める
  void _showTxnSummary(core.Transaction t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${t.date.month}/${t.date.day} ${t.description.isEmpty ? t.paymentMethod : t.description} -${formatYen(t.amount)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 引落予定の項目タップ → その場で編集シート（設定カード）を直接開く。
  /// 設定画面に遷移せず、保存したら即リストへ反映する。
  Future<void> _openSubscriptionEdit(String id) async {
    final idx =
        _subscriptions.subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final paymentMethods = <String>[
      ..._payments.bankAccounts.map((b) => b.name),
      ..._payments.creditCards.map((c) => c.name),
    ];
    final categories = _subscriptions.categoriesInOrder
        .where((c) => c != core.SubscriptionConfig.uncategorizedKey)
        .toList();
    final edited = await showSubscriptionEditSheet(
      context,
      initial: _subscriptions.subscriptions[idx],
      paymentMethods: paymentMethods,
      categories: categories,
    );
    if (edited == null) return;
    final newList = [..._subscriptions.subscriptions];
    newList[idx] = edited;
    await _subscriptionRepo
        .save(_subscriptions.copyWith(subscriptions: newList));
    if (mounted) await _load();
  }

  /// ウォレット一覧シート（銀行/現金/電子マネー/クレカ）。
  /// 各ウォレットの「当月の収支（フロー・振替込み）」を表示し、タップで詳細へ。
  Future<void> _openWalletList() async {
    final banks = _payments.bankAccounts;
    final cards = _payments.creditCards;
    if (banks.isEmpty && cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ウォレットが未登録です（設定 → ウォレット）')),
      );
      return;
    }
    bool inMonth(core.Transaction t) =>
        t.date.year == _focused.year && t.date.month == _focused.month;
    // 銀行/現金/電子マネーの当月フロー（収入+ / 支出- / 振替±）
    int bankFlow(String name) {
      int net = 0;
      for (final t in _transactions) {
        if (!inMonth(t)) continue;
        if (t.type == core.TransactionType.transfer) {
          if (t.transferFromAccount == name) net -= t.amount;
          if (t.transferToAccount == name) net += t.amount;
          continue;
        }
        if (t.paymentMethod != name) continue;
        if (t.type == core.TransactionType.income) {
          net += t.amount;
        } else {
          net -= t.amount;
        }
      }
      return net;
    }

    int cardUsage(String name) {
      int sum = 0;
      for (final t in _transactions) {
        if (!inMonth(t)) continue;
        if (t.type != core.TransactionType.expense) continue;
        if (t.paymentMethod == name) sum += t.amount;
      }
      return sum;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 18, color: Color(0xFF1A237E)),
                  const SizedBox(width: 8),
                  const Text('ウォレット',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_focused.month}月の収支',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in banks)
                    _walletTile(
                      iconUrl: b.iconUrl,
                      name: b.name,
                      sub: b.accountType.shortLabel,
                      flow: bankFlow(b.name),
                      onTap: () {
                        Navigator.pop(sheet);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AccountDetailScreen(account: b)),
                        ).then((_) {
                          if (mounted) _load();
                        });
                      },
                    ),
                  for (final c in cards)
                    _walletTile(
                      iconUrl: c.iconUrl,
                      name: c.name,
                      sub: 'クレカ',
                      flow: -cardUsage(c.name),
                      fallbackIcon: Icons.credit_card,
                      onTap: () {
                        Navigator.pop(sheet);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CardDetailScreen(card: c)),
                        ).then((_) {
                          if (mounted) _load();
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _walletTile({
    String? iconUrl,
    required String name,
    required String sub,
    required int flow,
    IconData fallbackIcon = Icons.account_balance,
    required VoidCallback onTap,
  }) {
    final color = flow > 0
        ? V2Colors.positive
        : (flow < 0 ? V2Colors.negative : V2Colors.textMuted);
    return ListTile(
      leading: BrandLogo(
          iconUrl: iconUrl,
          fallbackIcon: fallbackIcon,
          size: 28,
          borderRadius: 4),
      title: Text(name),
      subtitle: Text(sub,
          style: V2Typography.micro.copyWith(color: V2Colors.textMuted)),
      trailing: Text(formatYen(flow, withSign: true),
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: V2Typography.tabularNums)),
      onTap: onTap,
    );
  }

  /// 変動費の「その月の実額」をその場で入力（未入力は0／月ごと独立）。
  Future<void> _inputVariableActual(core.Subscription s) async {
    final ym = _ymKey;
    final current = s.monthlyActuals[ym] ?? 0;
    final ctrl = TextEditingController(
        text: current > 0 ? formatAmount(current) : '');
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${_focused.month}月の「${s.name}」'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            ThousandsSeparatorInputFormatter(),
          ],
          decoration: InputDecoration(
            labelText: '実額（円）',
            hintText: s.amount > 0 ? '目安 ${formatYen(s.amount)}' : null,
            prefixText: '¥ ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, -1),
              child: const Text('クリア')),
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, parseAmount(ctrl.text) ?? 0),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return; // キャンセル
    final idx = _subscriptions.subscriptions.indexWhere((x) => x.id == s.id);
    if (idx < 0) return;
    final m = Map<String, int>.from(s.monthlyActuals);
    if (result <= 0) {
      m.remove(ym);
    } else {
      m[ym] = result;
    }
    final list = [..._subscriptions.subscriptions];
    list[idx] = s.copyWith(monthlyActuals: m);
    await _subscriptionRepo
        .save(_subscriptions.copyWith(subscriptions: list));
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
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final expenses = _monthExpenses;
    final total = expenses.fold<int>(0, (s, t) => s + t.amount);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 月切替バー + 集計サマリー ─────────────────
          V2Card(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.lg, vertical: V2Spacing.md),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  '${_focused.year}年${_focused.month}月',
                  style: V2Typography.h2.copyWith(
                      color: V2Colors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () => _shiftMonth(1),
                ),
                const SizedBox(width: V2Spacing.lg),
                Text('${expenses.length} 件',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary)),
                const Spacer(),
                Text('合計',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary)),
                const SizedBox(width: V2Spacing.sm),
                Text(formatYen(-total, withSign: true),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: V2Colors.negative,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.sm),
          // ── ウォレット一覧ボタン（銀行/現金/電子/クレカ→各詳細） ──
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _openWalletList,
              icon: const Icon(
                  Icons.account_balance_wallet_outlined, size: 16),
              label: const Text('ウォレット一覧'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(height: V2Spacing.sm),
          // ── 取引一覧（経費明細）を上に ────────────────────
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
                      Icon(Icons.receipt_long_outlined,
                          size: 18, color: widget.accent),
                      const SizedBox(width: V2Spacing.sm),
                      Text(isBusiness ? '経費明細' : '支出明細',
                          style: V2Typography.h2),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => _openInput(),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('追加'),
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
                if (expenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: V2Spacing.sm),
                        Text('${_focused.month}月の支出記録なし',
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.textSecondary)),
                      ],
                    ),
                  )
                else
                  _ExpensesTable(
                    rows: expenses,
                    payments: _payments,
                    onTapRow: _showTxnSummary,
                  ),
              ],
            ),
          ),
          if (_monthlyCharges.isNotEmpty)
            const SizedBox(height: V2Spacing.lg),
          // ── 毎月支出予定（固定費 / 変動費）を経費明細の下に ──────
          _MonthlyChargesSection(
            charges: _monthlyCharges,
            onTapItem: _openSubscriptionEdit,
            isCurrentMonth: _focused.year == DateTime.now().year &&
                _focused.month == DateTime.now().month,
            ym: _ymKey,
            onInputVariable: _inputVariableActual,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 毎月引落予定セクション（固定費 / 変動費）
// ═════════════════════════════════════════════════

class _MonthlyChargesSection extends StatefulWidget {
  final List<core.Subscription> charges;
  final void Function(String id) onTapItem;
  final bool isCurrentMonth;

  /// 表示中の月キー "YYYY-MM"（変動費の実額参照用）。
  final String ym;

  /// 変動費の月額入力を開くコールバック。
  final void Function(core.Subscription s) onInputVariable;
  const _MonthlyChargesSection({
    required this.charges,
    required this.onTapItem,
    required this.isCurrentMonth,
    required this.ym,
    required this.onInputVariable,
  });

  @override
  State<_MonthlyChargesSection> createState() =>
      _MonthlyChargesSectionState();
}

class _MonthlyChargesSectionState extends State<_MonthlyChargesSection> {
  bool _fixedExpanded = true;
  bool _variableExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.charges.isEmpty) return const SizedBox.shrink();
    final fixed = widget.charges
        .where((s) =>
            s.amountType == core.SubscriptionAmountType.fixed)
        .toList();
    final variable = widget.charges
        .where((s) =>
            s.amountType ==
            core.SubscriptionAmountType.variable)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: V2Spacing.sm),
          child: Row(
            children: [
              const Icon(Icons.event_repeat,
                  size: 18, color: Color(0xFFEA580C)),
              const SizedBox(width: V2Spacing.sm),
              Text('毎月支出予定',
                  style: V2Typography.h2
                      .copyWith(color: V2Colors.textPrimary)),
            ],
          ),
        ),
        // 固定費カード
        if (fixed.isNotEmpty)
          _ChargeCard(
            title: '固定費（定額）',
            icon: Icons.lock_outline,
            accent: const Color(0xFF1A237E),
            bg: const Color(0xFFE0E7FF),
            charges: fixed,
            isVariable: false,
            ym: widget.ym,
            isCurrentMonth: widget.isCurrentMonth,
            expanded: _fixedExpanded,
            onToggle: () =>
                setState(() => _fixedExpanded = !_fixedExpanded),
            onTapItem: widget.onTapItem,
            onInputVariable: widget.onInputVariable,
          ),
        if (fixed.isNotEmpty && variable.isNotEmpty)
          const SizedBox(height: V2Spacing.lg),
        // 変動費カード（その月の実額。未入力は0）
        if (variable.isNotEmpty)
          _ChargeCard(
            title: '変動費',
            icon: Icons.bolt_outlined,
            accent: const Color(0xFFEA580C),
            bg: const Color(0xFFFFEDD5),
            charges: variable,
            isVariable: true,
            ym: widget.ym,
            isCurrentMonth: widget.isCurrentMonth,
            expanded: _variableExpanded,
            onToggle: () =>
                setState(() => _variableExpanded = !_variableExpanded),
            onTapItem: widget.onTapItem,
            onInputVariable: widget.onInputVariable,
          ),
      ],
    );
  }
}

/// 固定費 / 変動費 を1枚ずつのカードで表示する。
class _ChargeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Color bg;
  final List<core.Subscription> charges;
  final bool isVariable;
  final String ym;
  final bool isCurrentMonth;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String id) onTapItem;
  final void Function(core.Subscription s) onInputVariable;
  const _ChargeCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.bg,
    required this.charges,
    required this.isVariable,
    required this.ym,
    required this.isCurrentMonth,
    required this.expanded,
    required this.onToggle,
    required this.onTapItem,
    required this.onInputVariable,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal =
        charges.fold<int>(0, (s, c) => s + c.amountForMonth(ym));
    final today = DateTime.now();
    return V2Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(V2Spacing.lg,
                  V2Spacing.md, V2Spacing.lg, V2Spacing.md),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: V2Spacing.sm),
                  Text(title,
                      style: V2Typography.h2.copyWith(color: accent)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${charges.length}',
                        style: TextStyle(
                            fontSize: 11,
                            color: accent,
                            fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text(formatYen(subtotal),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: V2Colors.textPrimary,
                          fontFeatures: V2Typography.tabularNums)),
                  const SizedBox(width: 6),
                  Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: V2Colors.textSecondary),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final s in charges)
              _ChargeRow(
                s: s,
                isCurrentMonth: isCurrentMonth,
                today: today,
                isVariable: isVariable,
                monthAmount: s.amountForMonth(ym),
                onTap: () => onTapItem(s.id),
                onInputAmount:
                    isVariable ? () => onInputVariable(s) : null,
              ),
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  final core.Subscription s;
  final bool isCurrentMonth;
  final DateTime today;
  final VoidCallback onTap;

  /// 変動費かどうか。変動費は当月の実額（未入力は0）を入力ピルで表示。
  final bool isVariable;

  /// 表示中の月の金額（固定費=定額、変動費=その月の実額。未入力は0）。
  final int monthAmount;

  /// 変動費の月額入力を開く（変動費のみ非null）。
  final VoidCallback? onInputAmount;
  const _ChargeRow({
    required this.s,
    required this.isCurrentMonth,
    required this.today,
    required this.onTap,
    this.isVariable = false,
    required this.monthAmount,
    this.onInputAmount,
  });

  @override
  Widget build(BuildContext context) {
    final day = s.billingDay;
    String? statusLabel;
    Color? statusColor;
    if (isCurrentMonth && day != null) {
      if (day < today.day) {
        statusLabel = '引落済';
        statusColor = V2Colors.positive;
      } else if (day == today.day) {
        statusLabel = '今日';
        statusColor = V2Colors.negative;
      } else {
        final left = day - today.day;
        statusLabel = 'あと$left日';
        statusColor =
            left <= 3 ? V2Colors.warning : V2Colors.info;
      }
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: V2Colors.divider, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(day == null ? '—' : '$day日',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.warning,
                      fontFeatures: V2Typography.tabularNums)),
            ),
            BrandLogo(
              iconUrl: s.iconUrl,
              fallbackIcon: Icons.subscriptions_outlined,
              size: 22,
              borderRadius: 4,
            ),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: V2Typography.body),
                  if (s.paymentMethod != null &&
                      s.paymentMethod!.isNotEmpty)
                    Text(s.paymentMethod!,
                        style: V2Typography.micro.copyWith(
                            color: V2Colors.textMuted)),
                ],
              ),
            ),
            if (statusLabel != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor!.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
              ),
              const SizedBox(width: V2Spacing.sm),
            ],
            if (isVariable) ...[
              // 変動費: 当月の実額をタップして入力。未入力は¥0。目安を薄く併記。
              if (s.amount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('目安 ${formatYen(s.amount)}',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                ),
              InkWell(
                onTap: onInputAmount,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: monthAmount > 0
                        ? const Color(0xFFFFEDD5)
                        : V2Colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: monthAmount > 0
                            ? const Color(0xFFEA580C)
                            : V2Colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatYen(monthAmount),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: monthAmount > 0
                                  ? const Color(0xFFEA580C)
                                  : V2Colors.textMuted,
                              fontFeatures: V2Typography.tabularNums)),
                      const SizedBox(width: 3),
                      Icon(Icons.edit,
                          size: 12,
                          color: monthAmount > 0
                              ? const Color(0xFFEA580C)
                              : V2Colors.textMuted),
                    ],
                  ),
                ),
              ),
            ] else
              Text(formatYen(monthAmount),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.textPrimary,
                      fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 取引一覧テーブル（マネフォクラウド寄り）
// ═════════════════════════════════════════════════

class _ExpensesTable extends StatelessWidget {
  final List<core.Transaction> rows;
  final core.PaymentMethodsConfig payments;
  final void Function(core.Transaction t) onTapRow;
  const _ExpensesTable({
    required this.rows,
    required this.payments,
    required this.onTapRow,
  });

  String? _iconUrlFor(String name) {
    for (final b in payments.bankAccounts) {
      if (b.name == name) return b.iconUrl;
    }
    for (final c in payments.creditCards) {
      if (c.name == name) return c.iconUrl;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // データ行（スマホで潰れないよう、列ヘッダーは廃止し2段表示）
        for (final t in rows) _ExpenseRow(
          t: t,
          iconUrl: _iconUrlFor(t.paymentMethod),
          onTap: () => onTapRow(t),
        ),
      ],
    );
  }
}

class _ExpenseRow extends StatefulWidget {
  final core.Transaction t;
  final String? iconUrl;
  final VoidCallback onTap;
  const _ExpenseRow({
    required this.t,
    required this.iconUrl,
    required this.onTap,
  });

  @override
  State<_ExpenseRow> createState() => _ExpenseRowState();
}

class _ExpenseRowState extends State<_ExpenseRow> {
  bool _hover = false;

  String _categoryLabel() {
    final major = widget.t.category.major.trim();
    final sub = widget.t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return '未分類';
    if (sub.isEmpty) return major;
    return sub;
  }

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
          color: _hover ? V2Colors.hover : V2Colors.surface,
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? V2Colors.hover : V2Colors.surface,
            border: const Border(
                top: BorderSide(color: V2Colors.divider, width: 1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 日付（M/D・2段）
              SizedBox(
                width: 38,
                child: Text(
                    '${widget.t.date.month}/${widget.t.date.day}',
                    style: V2Typography.numericCell),
              ),
              const SizedBox(width: V2Spacing.sm),
              // 中央: 1段目=カテゴリ＋内容、2段目=支払方法
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: V2Colors.surfaceMuted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(_categoryLabel(),
                              style: V2Typography.micro),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.t.description.isEmpty
                                ? '—'
                                : widget.t.description,
                            style: V2Typography.body,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        BrandLogo(
                          iconUrl: widget.iconUrl,
                          fallbackIcon: Icons.account_balance,
                          size: 13,
                          borderRadius: 3,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(widget.t.paymentMethod,
                              style: V2Typography.micro.copyWith(
                                  color: V2Colors.textMuted),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              // 金額（右・固定幅なしで見切れ防止）
              Text(
                '-${formatYen(widget.t.amount)}',
                style: V2Typography.numericCell.copyWith(
                    color: V2Colors.negative,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
