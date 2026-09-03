import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/special_expense.dart';
import '../data/special_expense_repository.dart';
import '../data/special_expense_summary.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';
import 'special_expenses_screen.dart';

import '../widgets/web_layout.dart';
/// 特別支出1件の中身。合計・精算・明細をここで見る。
class SpecialExpenseDetailScreen extends StatefulWidget {
  const SpecialExpenseDetailScreen({super.key, required this.item});
  final SpecialExpense item;

  @override
  State<SpecialExpenseDetailScreen> createState() =>
      _SpecialExpenseDetailScreenState();
}

class _SpecialExpenseDetailScreenState
    extends State<SpecialExpenseDetailScreen> {
  late SpecialExpense _item = widget.item;

  String? get _hid => HouseholdService.instance.householdId;
  String? get _uid => AuthService.instance.currentUser?.uid;

  Map<String, String> get _names => HouseholdService.instance.memberNames;
  List<String> get _memberUids => _names.keys.toList();

  String _nameOf(String? uid) {
    if (uid == null) return '不明';
    if (uid == kPaidByBoth) return '一緒に';
    return _names[uid] ?? '不明';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _edit() async {
    final result = await showModalBottomSheet<SpecialExpense>(
      // 広い画面ではシートが横いっぱいに伸びるので、幅を抑えて中央に置く。
      constraints: const BoxConstraints(maxWidth: 560),
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SpecialExpenseEditSheet(editing: _item),
      ),
    );
    if (result == null) return;
    final hid = _hid, uid = _uid;
    if (hid == null || uid == null) return;
    await SpecialExpenseRepository.instance.save(hid, result, uid);
    if (mounted) setState(() => _item = result);
  }

  /// 予定をまとめて確定にする（現地でまとめて払ったとき）。
  Future<void> _confirmPending(int count) async {
    final hid = _hid;
    if (hid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('予定を「払った」にする'),
        content: Text('$count件を確定にします。金額と日付はそのままです。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定にする')),
        ],
      ),
    );
    if (ok != true) return;
    final n =
        await TxRepository.instance.confirmPendingOfSpecialExpense(hid, _item.id);
    _toast('$n件を確定にしました');
  }

  /// 精算が済んだ印をつける（一覧では「済んだもの」に落ちる）。
  Future<void> _toggleSettled() async {
    final hid = _hid, uid = _uid;
    if (hid == null || uid == null) return;
    final next = _item.copyWith(settled: !_item.settled);
    await SpecialExpenseRepository.instance.save(hid, next, uid);
    if (mounted) setState(() => _item = next);
    _toast(next.settled ? '精算済みにしました' : '進行中に戻しました');
  }

  Future<void> _delete() async {
    final hid = _hid;
    if (hid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('この特別支出を消す'),
        content: const Text('箱だけを消します。中の明細は消えず、ふつうの支出として残ります。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('消す')),
        ],
      ),
    );
    if (ok != true) return;
    await TxRepository.instance.detachSpecialExpense(hid, _item.id);
    await SpecialExpenseRepository.instance.delete(hid, _item.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hid = _hid;
    final k = kindOf(_item.kind);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_item.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: '直す',
              onPressed: _edit,
              icon: const Icon(Icons.edit_rounded)),
          IconButton(
              tooltip: '消す',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      // 広い画面では、中央に寄せた本文の右端にボタンを合わせる。
      floatingActionButtonLocation: const WebEndFloatFabLocation(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddTransactionScreen(
              initialType: core.TransactionType.expense,
              initialDate: _item.covers(DateTime.now())
                  ? DateTime.now()
                  : _item.start,
              initialSpecialExpenseId: _item.id,
            ),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('この特別支出に足す'),
      ),
      body: WebCenterFill(
        maxWidth: 1040,
        child: hid == null
            ? const SizedBox.shrink()
            : StreamBuilder<List<core.Transaction>>(
                stream: TxRepository.instance
                    .watchBySpecialExpense(hid, _item.id),
                builder: (context, snap) {
                  final txns = snap.data ?? const <core.Transaction>[];
                  final sum =
                      SpecialExpenseSummary.of(txns, _memberUids);
                  final pendingCount =
                      txns.where((t) => t.isPending).length;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      _headerCard(k, sum),
                      const SizedBox(height: 16),
                      _sectionTitle('精算'),
                      const SizedBox(height: 8),
                      _settleCard(sum),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _sectionTitle('明細'),
                          const Spacer(),
                          if (pendingCount > 0)
                            TextButton(
                              onPressed: () => _confirmPending(pendingCount),
                              child: Text('予定$pendingCount件を払った'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (txns.isEmpty)
                        _emptyTxns()
                      else
                        ...txns.map(_txTile),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text));

  /// 総額カード。確定と予定を分けて出す（予定は月の集計には入らない）。
  Widget _headerCard(SpecialExpenseKind k, SpecialExpenseSummary sum) {
    final n = _memberUids.isEmpty ? 1 : _memberUids.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8FA8), AppColors.pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(k.icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text('${k.name}・${formatSpecialExpensePeriod(_item)}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Text(formatYen(sum.total),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900)),
          Text('1人あたり ${formatYen(sum.perPerson(n))}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _miniStat('払った分', sum.confirmed)),
              Container(width: 1, height: 32, color: Colors.white24),
              Expanded(child: _miniStat('予定', sum.pending)),
            ],
          ),
          if (sum.pending > 0) ...[
            const SizedBox(height: 10),
            const Text('予定は月の支出・予算には入りません。',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, int value) => Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Text(formatYen(value),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ],
      );

  /// 精算カード。誰がいくら立て替えて、差引だれがだれに渡すか。
  Widget _settleCard(SpecialExpenseSummary sum) {
    final rows = <Widget>[];
    for (final uid in _memberUids) {
      final v = sum.paidByUid[uid] ?? 0;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(_nameOf(uid),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${formatYen(v)} 立替',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSub)),
          ],
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          const Divider(height: 20, color: AppColors.divider),
          if (!sum.needsSettle)
            const Text('立替はありません（その場で折半済み）',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSub))
          else
            Column(
              children: [
                Text(
                  '${_nameOf(sum.fromUid)} が ${_nameOf(sum.toUid)} に',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSub),
                ),
                const SizedBox(height: 2),
                Text(formatYen(sum.settleAmount),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.pinkDark)),
                const Text('わたすと精算',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _toggleSettled,
            icon: Icon(_item.settled
                ? Icons.undo_rounded
                : Icons.check_circle_outline_rounded),
            label: Text(_item.settled ? '進行中に戻す' : '精算した'),
          ),
        ],
      ),
    );
  }

  Widget _txTile(core.Transaction t) {
    final cat = categoryFor(t.category.major,
        income: t.type == core.TransactionType.income);
    final payer = t.paidBy ?? t.recordedBy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AddTransactionScreen(editing: t)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: cat.color.withValues(alpha: 0.25),
                  child: Icon(cat.icon, size: 15, color: AppColors.text),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(t.description,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (t.isPending) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.pinkSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('予定',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.pinkDark)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${t.date.month}/${t.date.day}・${t.category.major}'
                        '${payer == null ? '' : '・${_nameOf(payer)}が払った'}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSub),
                      ),
                    ],
                  ),
                ),
                Text(formatYen(t.effectiveAmount),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyTxns() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'まだ明細がありません。\n右下のボタンから足すか、ふだんの記録で「特別支出」を選んでください。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSub),
        ),
      );
}
