import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_service.dart';
import '../data/budget_repository.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/subscription.dart';
import '../data/subscription_repository.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'subscriptions_screen.dart';

/// ホーム：月次サマリー＋カテゴリ内訳＋取引一覧（可愛い系）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  // ── 相手の登録の「未読まとめ通知」用 ───────────────────────
  StreamSubscription<List<core.Transaction>>? _notifySub;
  Set<String> _seenIds = {};
  bool _seenLoaded = false;
  bool _primeOnFirstEmit = false; // 初回(既読データ無し)は通知せず既読化

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _initPartnerNotify();
  }

  @override
  void dispose() {
    _notifySub?.cancel();
    super.dispose();
  }

  Future<void> _initPartnerNotify() async {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'takuharu.seen_tx.$hid';
    final saved = prefs.getStringList(key);
    _primeOnFirstEmit = saved == null; // まだ一度も記録してない＝初回
    _seenIds = (saved ?? const <String>[]).toSet();
    _seenLoaded = true;
    _notifySub = TxRepository.instance.watch(hid).listen(_onTxnsForNotify);
  }

  Future<void> _persistSeen(String hid) async {
    final prefs = await SharedPreferences.getInstance();
    // 肥大化防止: 直近1000件だけ保持。
    final ids = _seenIds.toList();
    final trimmed =
        ids.length > 1000 ? ids.sublist(ids.length - 1000) : ids;
    await prefs.setStringList('takuharu.seen_tx.$hid', trimmed);
  }

  Future<void> _onTxnsForNotify(List<core.Transaction> txns) async {
    if (!_seenLoaded || !mounted) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    // 初回(既読データ無し)は、今あるものを全部「既読」にして通知しない。
    if (_primeOnFirstEmit) {
      _primeOnFirstEmit = false;
      _seenIds = txns.map((t) => t.id).toSet();
      await _persistSeen(hid);
      return;
    }
    final mine = _myUid;
    final unseen = txns
        .where((t) =>
            t.recordedBy != null &&
            t.recordedBy != mine &&
            !_seenIds.contains(t.id))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (unseen.isEmpty) return;
    _seenIds.addAll(unseen.map((t) => t.id));
    await _persistSeen(hid);
    if (mounted) _showPartnerDialog(unseen);
  }

  void _showPartnerDialog(List<core.Transaction> items) {
    final names = HouseholdService.instance.memberNames;
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('🛒 あいてのあたらしい記録（${items.length}件）'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in items.take(20))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '・${names[t.recordedBy] ?? 'パートナー'}：'
                    '${t.description.isEmpty ? '（無題）' : t.description} '
                    '${t.type == core.TransactionType.income ? '+' : '-'}'
                    '¥${t.amount}',
                    style: const TextStyle(fontSize: 14, color: AppColors.text),
                  ),
                ),
              if (items.length > 20)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('…ほか',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('OK ♡'),
          ),
        ],
      ),
    );
  }

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  bool _inMonth(core.Transaction t) =>
      t.date.year == _month.year && t.date.month == _month.month;

  Future<void> _openAdd([core.Transaction? editing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AddTransactionScreen(editing: editing)),
    );
    if (changed == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('たくはるファイナンス'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.favorite_rounded, color: AppColors.pink),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('きろく',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<core.Transaction>>(
              stream: TxRepository.instance.watch(hid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? const <core.Transaction>[];
                final month = all.where(_inMonth).toList();
                return _body(month);
              },
            ),
    );
  }

  Widget _body(List<core.Transaction> month) {
    final income = month
        .where((t) => t.type == core.TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = month
        .where((t) => t.type == core.TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    // カテゴリ別（支出）集計。
    final byCat = <String, int>{};
    for (final t in month) {
      if (t.type != core.TransactionType.expense) continue;
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
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
        _budgetCard(expense),
        const SizedBox(height: 12),
        _subscriptionCard(),
        if (_splitCard(month) case final w?) ...[
          const SizedBox(height: 12),
          w,
        ],
        const SizedBox(height: 16),
        if (catEntries.isNotEmpty) ...[
          _sectionTitle('支出の内訳'),
          const SizedBox(height: 8),
          _categoryCard(catEntries, expense),
          const SizedBox(height: 16),
        ],
        _sectionTitle('記録'),
        const SizedBox(height: 8),
        if (month.isEmpty)
          _empty()
        else
          ...month.map(_txTile),
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
          colors: [Color(0xFFFF8FA8), Color(0xFFFF6B8A)],
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
                Row(
                  children: [
                    Icon(Icons.savings_rounded, size: 18, color: color),
                    const SizedBox(width: 6),
                    const Text('今月の予算',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const Spacer(),
                    Text('${formatYen(expense)} / ${formatYen(budget)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  ],
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

  /// 固定費カード。今月の固定費合計を表示し、タップで管理画面へ。
  Widget _subscriptionCard() {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return const SizedBox.shrink();
    final now = DateTime.now();
    return StreamBuilder<List<Subscription>>(
      stream: SubscriptionRepository.instance.watch(hid),
      builder: (context, snap) {
        final subs = snap.data ?? const <Subscription>[];
        final total = subs
            .where((s) => s.appliesTo(now.year, now.month))
            .fold<int>(0, (t, s) => t + s.amount);
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.pinkSoft, width: 1.4),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_repeat_rounded,
                    size: 20, color: AppColors.pink),
                const SizedBox(width: 8),
                const Text('固定費・サブスク',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const Spacer(),
                Text(subs.isEmpty ? '登録する' : '今月 ${formatYen(total)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pinkDark)),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSub),
              ],
            ),
          ),
        );
      },
    );
  }

  /// わりかんカード（今月）。全支出を二人で折半する前提で精算額を出す。
  /// 2人世帯で、今月の支出があるときだけ表示。
  Widget? _splitCard(List<core.Transaction> month) {
    final names = HouseholdService.instance.memberNames;
    if (names.length != 2) return null;
    final uids = names.keys.toList();
    final a = uids[0], b = uids[1];
    int paidA = 0, paidB = 0;
    for (final t in month) {
      if (t.type != core.TransactionType.expense) continue;
      final payer = t.paidBy ?? t.recordedBy;
      if (payer == a) {
        paidA += t.amount;
      } else if (payer == b) {
        paidB += t.amount;
      } else {
        // 支払者不明（古い記録）は折半して残高がズレないようにする
        paidA += t.amount ~/ 2;
        paidB += t.amount - t.amount ~/ 2;
      }
    }
    final total = paidA + paidB;
    if (total == 0) return null;
    final diff = paidA - paidB; // >0: a が多く払った
    final settle = diff.abs() ~/ 2;

    final Widget conclusion;
    if (settle == 0) {
      conclusion = const Text('💗 ちょうど均等だよ！',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pinkDark));
    } else {
      final ower = diff > 0 ? b : a; // 払いが少ない人 → 渡す側
      final owee = diff > 0 ? a : b;
      conclusion = RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: AppColors.text),
          children: [
            const TextSpan(text: '💗 '),
            TextSpan(
                text: names[ower],
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' が '),
            TextSpan(
                text: names[owee],
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' に '),
            TextSpan(
                text: formatYen(settle),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: AppColors.pinkDark)),
            const TextSpan(text: ' わたすと精算 ♡'),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.volunteer_activism_rounded,
                  size: 18, color: AppColors.pink),
              const SizedBox(width: 6),
              const Text('わりかん（今月）',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
              const Spacer(),
              Text('支出 ${formatYen(total)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 10),
          _paidRow(names[a] ?? 'A', paidA, total),
          const SizedBox(height: 6),
          _paidRow(names[b] ?? 'B', paidB, total),
          const Divider(height: 18),
          conclusion,
        ],
      ),
    );
  }

  Widget _paidRow(String name, int paid, int total) {
    final ratio = total == 0 ? 0.0 : paid / total;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppColors.pinkSoft,
              valueColor: const AlwaysStoppedAnimation(AppColors.pink),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(formatYen(paid),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
      ],
    );
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

  Widget _categoryCard(List<MapEntry<String, int>> entries, int total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final e in entries.take(6)) _catBar(e.key, e.value, total),
          ],
        ),
      ),
    );
  }

  Widget _catBar(String name, int amount, int total) {
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
    // 支払者（支出・2人世帯のときだけ表示）
    final names = HouseholdService.instance.memberNames;
    final payerUid = t.paidBy ?? t.recordedBy;
    final payer = (!income && names.length >= 2 && payerUid != null)
        ? names[payerUid]
        : null;
    final sub = '${t.date.month}/${t.date.day}　${t.category.major}'
        '${payer != null ? '　💳 $payer' : ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () => _openAdd(t),
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
            const Icon(Icons.favorite_border_rounded,
                size: 48, color: Color(0xFFF3C6D2)),
            const SizedBox(height: 10),
            Text('${_month.month}月の記録はまだないよ',
                style: const TextStyle(
                    color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('右下の「きろく」から追加してね ♡',
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
