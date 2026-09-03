import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../widgets/load_error_view.dart';
import '../data/budget_repository.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/month_scope.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/receipt_group.dart';
import 'add_transaction_screen.dart';
import 'record_menu.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';

import '../widgets/web_layout.dart';
/// ホーム：月次サマリー＋カテゴリ内訳＋取引一覧（水色・シンプル）。
class HomeScreen extends StatefulWidget {
  /// 「支出をすべて見る」タップで支出タブへ切替えるためのコールバック。
  final VoidCallback? onOpenExpenses;
  const HomeScreen({super.key, this.onOpenExpenses});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 表示中の月は全タブ共通（MonthScope）。切替は他タブにも反映される。
  DateTime get _month => MonthScope.instance.month;

  // 支出の内訳で展開中のカテゴリ名（タップで開閉）。
  String? _openCat;

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

  /// 「きろく」ボタン：共通メニュー（手入力 / レシート）を開く。
  Future<void> _openRecordMenu() async {
    final changed = await showRecordMenu(context);
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('はるファイナンス'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.savings_rounded, color: AppColors.pink),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'カレンダー',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CalendarScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      // 広い画面では、中央に寄せた本文の右端にボタンを合わせる。
      floatingActionButtonLocation: const WebEndFloatFabLocation(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRecordMenu(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('きろく',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: WebCenterFill(
        maxWidth: 1040,
        child: hid == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<List<core.Transaction>>(
                stream: TxRepository.instance.watch(hid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    final err = snap.error;
                    final perm = err is FirebaseException &&
                        err.code == 'permission-denied';
                    return LoadErrorView(
                      permissionError: perm,
                      message: perm ? null : err.toString(),
                      onRetry: () => setState(() {}),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data ?? const <core.Transaction>[];
                  final month = all.where(_inMonth).toList()
                    ..sort((a, b) {
                      final c = b.date.compareTo(a.date);
                      if (c != 0) return c;
                      return b.id.compareTo(a.id);
                    });
                  return _body(month, month);
                },
              ),
      ),
    );
  }

  Widget _body(List<core.Transaction> month, List<core.Transaction> recentAll) {
    final income = month
        .where((t) => t.type == core.TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = month
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    final byCat = <String, int>{};
    final txnsByCat = <String, List<core.Transaction>>{};
    for (final t in month) {
      if (t.type != core.TransactionType.expense) continue;
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
      (txnsByCat[t.category.major] ??= []).add(t);
    }
    final catEntries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _monthBar(),
        const SizedBox(height: 12),
        _summaryCard(income, expense),
        const SizedBox(height: 12),
        _sectionTitle('今月の予算'),
        const SizedBox(height: 8),
        _budgetCard(expense),
        const SizedBox(height: 16),
        if (catEntries.isNotEmpty) ...[
          _sectionTitle('支出の内訳'),
          const SizedBox(height: 8),
          _categoryCard(catEntries, expense, txnsByCat, month),
          const SizedBox(height: 16),
        ],
        _sectionTitle('最近の入出金'),
        const SizedBox(height: 8),
        if (recentAll.isEmpty)
          _empty()
        else ...[
          ...groupByReceipt(recentAll).take(5).map((g) => g.isGroup
              ? ReceiptGroupTile(
                  members: g.members,
                  onChanged: () {
                    if (mounted) setState(() {});
                  })
              : _txTile(g.single!)),
          const SizedBox(height: 4),
          InkWell(
            onTap: widget.onOpenExpenses,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    month.length > 5
                        ? '支出をすべて見る（ほか ${month.length - 5}件）'
                        : '支出をすべて見る',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pinkDark),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.pinkDark),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _monthBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _shift(-1),
        ),
        Text('${_month.year}年 ${_month.month}月',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => _shift(1),
        ),
      ],
    );
  }

  Widget _summaryCard(int income, int expense) {
    final balance = income - expense;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7CD6F5), Color(0xFF4FC4F0)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.pink.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('今月の収支',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            formatYen(balance),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStat('収入', income, Icons.south_west_rounded),
              ),
              Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.3)),
              Expanded(
                child: _miniStat('支出', expense, Icons.north_east_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 予算カード。未設定なら設定ボタン、設定済みなら進捗バー＋使いすぎ警告。
  Widget _budgetCard(int expense) {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return const SizedBox.shrink();
    return StreamBuilder<int?>(
      stream: BudgetRepository.instance.watch(hid),
      builder: (context, snap) {
        final budget = snap.data;
        if (budget == null || budget <= 0) {
          return OutlinedButton.icon(
            onPressed: () => _editBudget(hid, null),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.pinkDark,
              side: const BorderSide(color: AppColors.pinkSoft, width: 1.4),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.savings_rounded, size: 18),
            label: const Text('今月の予算を決める'),
          );
        }
        final ratio = budget == 0 ? 0.0 : (expense / budget).clamp(0.0, 1.0);
        final over = expense > budget;
        final remain = budget - expense;
        final color = over
            ? AppColors.expense
            : (ratio > 0.8 ? Colors.orange : AppColors.pink);
        return GestureDetector(
          onTap: () => _editBudget(hid, budget),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: over ? AppColors.expense : AppColors.pinkSoft,
                  width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${formatYen(expense)} / ${formatYen(budget)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 9,
                    backgroundColor: AppColors.pinkSoft,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  over
                      ? '⚠️ 予算を ${formatYen(-remain)} オーバー！'
                      : 'あと ${formatYen(remain)} 使えるよ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: over ? AppColors.expense : AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editBudget(String hid, int? current) async {
    final ctrl = TextEditingController(
        text: (current != null && current > 0) ? current.toString() : '');
    final result = await showDialog<int?>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('今月の予算'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '¥ ', hintText: '例: 150000'),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(dctx, 0), // 0 = 解除
              child: const Text('解除', style: TextStyle(color: AppColors.textSub)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: const Text('やめる')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
              Navigator.pop(dctx, v ?? -1);
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );
    if (result == null || result == -1) return; // キャンセル/不正
    await BudgetRepository.instance.save(hid, result == 0 ? null : result);
  }

  Widget _miniStat(String label, int value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        Text(formatYen(value),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _categoryCard(List<MapEntry<String, int>> entries, int total,
      Map<String, List<core.Transaction>> txnsByCat,
      List<core.Transaction> monthAll) {
    final top = entries.take(6).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (int i = 0; i < top.length; i++) ...[
              if (i > 0)
                const Divider(
                    height: 1, thickness: 1, color: AppColors.pinkSoft),
              _catRow(
                  top[i], total, txnsByCat[top[i].key] ?? const [], monthAll),
            ],
          ],
        ),
      ),
    );
  }

  Widget _catRow(MapEntry<String, int> e, int total,
      List<core.Transaction> txns, List<core.Transaction> monthAll) {
    final open = _openCat == e.key;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _openCat = open ? null : e.key),
          borderRadius: BorderRadius.circular(12),
          child: _catBar(e.key, e.value, total, expanded: open),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: ReceiptGroupedDetailList(
              txns: txns,
              allTxns: monthAll,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
          ),
      ],
    );
  }

  Widget _catBar(String name, int amount, int total, {bool? expanded}) {
    final c = categoryFor(name, income: false);
    final ratio = total == 0 ? 0.0 : amount / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(c.icon, size: 17, color: c.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Text(formatYen(amount),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
              if (expanded != null) ...[
                const SizedBox(width: 4),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: AppColors.textSub),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppColors.pinkSoft,
              valueColor: AlwaysStoppedAnimation(c.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _txTile(core.Transaction t) {
    final income = t.type == core.TransactionType.income;
    final c = categoryFor(t.category.major, income: income);
    final sub = '${t.date.month}/${t.date.day}　${t.category.major}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => AddTransactionScreen(editing: t)),
          );
          if (changed == true && mounted) setState(() {});
        },
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: c.color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(c.icon, color: c.color),
        ),
        title: Text(
          t.description.isEmpty ? t.category.major : t.description,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(sub,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing: Text(
          '${income ? '+' : '-'}${formatYen(t.amount)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: income ? AppColors.income : AppColors.expense,
          ),
        ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.savings_outlined,
                size: 48, color: Color(0xFFBFE3F0)),
            const SizedBox(height: 10),
            Text('${_month.month}月の記録はまだないよ',
                style: const TextStyle(
                    color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('右下の「きろく」から追加してね',
                style: TextStyle(color: AppColors.textSub, fontSize: 11)),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      );
}
