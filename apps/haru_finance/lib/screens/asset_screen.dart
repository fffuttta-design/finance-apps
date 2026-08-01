import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/account.dart';
import '../data/account_repository.dart';
import '../data/household_service.dart';
import '../data/month_scope.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/settings_button.dart';
import 'accounts_screen.dart';

/// 資産タブ：登録した各口座の「今の残高」と、
/// 選択中の月（全タブ共通）の入出金の動きを表示する。
/// 口座は初期登録せず、本人が「口座・残高を編集」から自由に追加する。
class AssetScreen extends StatefulWidget {
  const AssetScreen({super.key});

  @override
  State<AssetScreen> createState() => _AssetScreenState();
}

class _AssetScreenState extends State<AssetScreen> {
  // 表示中の月は全タブ共通（MonthScope）。
  DateTime get _month => MonthScope.instance.month;

  @override
  void initState() {
    super.initState();
    MonthScope.instance.notifier.addListener(_onMonthChanged);
  }

  @override
  void dispose() {
    MonthScope.instance.notifier.removeListener(_onMonthChanged);
    super.dispose();
  }

  void _onMonthChanged() {
    if (mounted) setState(() {});
  }

  void _shift(int d) => MonthScope.instance.shift(d);

  bool _inMonth(core.Transaction t) =>
      t.date.year == _month.year && t.date.month == _month.month;

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('資産'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.account_balance_rounded, color: AppColors.pink),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: '口座・残高を編集',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
          const SettingsButton(),
        ],
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Account>>(
              stream: AccountRepository.instance.watch(hid),
              builder: (context, accSnap) {
                if (accSnap.connectionState == ConnectionState.waiting &&
                    !accSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final accounts = accSnap.data ?? const <Account>[];
                return StreamBuilder<List<core.Transaction>>(
                  stream: TxRepository.instance.watch(hid),
                  builder: (context, txSnap) {
                    final txns = txSnap.data ?? const <core.Transaction>[];
                    return _body(accounts, txns);
                  },
                );
              },
            ),
    );
  }

  Widget _body(List<Account> accounts, List<core.Transaction> txns) {
    // 資産＝クレカ以外（銀行/現金/電子マネー）。クレカは負債なので除く。
    final assets =
        accounts.where((a) => a.type != AccountType.card && a.active).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final balances = {for (final a in assets) a.id: a.balanceFrom(txns)};
    final total = balances.values.fold<int>(0, (s, b) => s + b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _monthBar(),
        const SizedBox(height: 12),
        _totalCard(total),
        const SizedBox(height: 16),
        if (assets.isEmpty)
          _empty()
        else
          ...assets.map((a) => _assetCard(a, balances[a.id] ?? 0, txns)),
      ],
    );
  }

  Widget _monthBar() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _shift(-1)),
          Text('${_month.year}年 ${_month.month}月',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _shift(1)),
        ],
      );

  Widget _totalCard(int total) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6FD0F5), Color(0xFF1E9FD9)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppColors.pink.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            const Text('総資産',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(formatYen(total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      );

  /// 1口座ぶんのカード：残高＋今月の入出金サマリー＋その月の明細。
  Widget _assetCard(Account a, int balance, List<core.Transaction> allTxns) {
    // この口座の当月の動き（支払元名の一致で判定）。日付の新しい順。
    final moves = allTxns
        .where((t) => t.paymentMethod == a.name && _inMonth(t))
        .toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
    final income = moves
        .where((t) => t.type == core.TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = moves
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    final neg = balance < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー：口座名＋現在残高
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.pink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(13)),
                  child: Icon(a.type.icon, color: AppColors.pinkDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const Text('今の残高',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSub)),
                    ],
                  ),
                ),
                Text(formatYen(balance),
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: neg ? AppColors.expense : AppColors.text)),
              ],
            ),
            const SizedBox(height: 12),
            // 今月の入出金サマリー
            Row(
              children: [
                Expanded(
                  child: _sumChip(
                      '${_month.month}月の入金', income, AppColors.income, '+'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sumChip(
                      '${_month.month}月の出金', expense, AppColors.expense, '-'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 18),
            // その月の明細
            if (moves.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('この月の動きはまだないよ',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
              )
            else
              ...moves.map(_moveRow),
          ],
        ),
      ),
    );
  }

  Widget _sumChip(String label, int amount, Color color, String sign) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
            const SizedBox(height: 2),
            Text('$sign${formatYen(amount)}',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );

  /// 明細1行（日付・内容・±金額）。
  Widget _moveRow(core.Transaction t) {
    final isIncome = t.type == core.TransactionType.income;
    final color = isIncome ? AppColors.income : AppColors.expense;
    final sign = isIncome ? '+' : '-';
    final title = t.description.isEmpty ? t.category.major : t.description;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text('${t.date.month}/${t.date.day}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Text('$sign${formatYen(t.amount)}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.account_balance_wallet_rounded,
                size: 48, color: Color(0xFFB6E1F5)),
            const SizedBox(height: 10),
            const Text('資産口座がまだないよ',
                style: TextStyle(color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              ),
              child: const Text('口座を追加する'),
            ),
          ],
        ),
      );
}
