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

import '../widgets/web_layout.dart';
/// 資産タブ：**ためた合計**（記録し始めてからの 収入−支出）を主役にした画面。
///
/// 口座ごとの残高管理は使っていないので、口座を登録していないときは
/// 「ためた合計」と「その月の動き」だけを見せる。口座を登録した場合だけ、
/// 下に口座ごとの残高カードが並ぶ（口座名＝取引の支払元 で集計）。
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
      body: WebCenterFill(
        maxWidth: 1040,
        child: hid == null
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
      ),
    );
  }

  Widget _body(List<Account> accounts, List<core.Transaction> txns) {
    // 口座を登録しているなら、その初期残高も「手元のお金」として足す。
    // クレカは負債なので資産の合計からは除く。
    final assets =
        accounts.where((a) => a.type != AccountType.card && a.active).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final seed = assets.fold<int>(0, (s, a) => s + a.initialBalance);

    // 記録し始めてからの累計。
    var income = 0, expense = 0;
    DateTime? first;
    for (final t in txns) {
      if (t.type == core.TransactionType.income) {
        income += t.amount;
      } else if (t.type == core.TransactionType.expense) {
        expense += t.amount;
      } else {
        continue;
      }
      if (first == null || t.date.isBefore(first)) first = t.date;
    }

    // 選択中の月の動き（日付の新しい順）。
    final moves = txns.where(_inMonth).where((t) {
      return t.type == core.TransactionType.income ||
          t.type == core.TransactionType.expense;
    }).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
    final mIncome = moves
        .where((t) => t.type == core.TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final mExpense = moves
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _totalCard(seed + income - expense, income, expense, first),
        const SizedBox(height: 18),
        _monthBar(),
        const SizedBox(height: 8),
        _monthCard(moves, mIncome, mExpense),
        if (assets.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionTitle('口座の残高'),
          const SizedBox(height: 8),
          ...assets.map((a) => _assetCard(a, a.balanceFrom(txns), txns)),
        ],
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

  /// 主役のカード：ためた合計（記録開始からの 収入−支出）。
  Widget _totalCard(int total, int income, int expense, DateTime? first) =>
      Container(
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
            const Text('ためた合計',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(formatYen(total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
                first == null
                    ? '記録がまだないよ'
                    : '${first.year}年${first.month}月から今までの 収入 − 支出',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _whiteStat('ぜんぶの収入', income)),
                Container(width: 1, height: 34, color: Colors.white24),
                Expanded(child: _whiteStat('ぜんぶの支出', expense)),
              ],
            ),
          ],
        ),
      );

  Widget _whiteStat(String label, int value) => Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 2),
          Text(formatYen(value),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
        ],
      );

  /// 選択中の月の動き（入金・出金・差引＋明細）。
  Widget _monthCard(List<core.Transaction> moves, int income, int expense) {
    final diff = income - expense;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${_month.month}月に増えた分',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Text('${diff >= 0 ? '+' : ''}${formatYen(diff)}',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color:
                            diff >= 0 ? AppColors.income : AppColors.expense)),
              ],
            ),
            const SizedBox(height: 12),
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
            if (moves.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('この月の動きはまだないよ',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
              )
            else
              ...moves.map(_moveRow),
          ],
        ),
      ),
    );
  }

  /// 1口座ぶんのカード：残高＋今月の入出金サマリー＋その月の明細。
  /// 口座を登録したときだけ出る（口座名＝取引の支払元 で集計）。
  Widget _assetCard(Account a, int balance, List<core.Transaction> allTxns) {
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
            if (moves.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('この月の動きはまだないよ',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
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
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textSub)),
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

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      );
}
