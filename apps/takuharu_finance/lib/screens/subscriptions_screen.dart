import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/subscription.dart';
import '../data/subscription_repository.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 「一緒に（折半）」を表す paidBy のセンチネル値。
const String kPaidByBoth = 'both';

/// 固定費・サブスクの「今月合計」サマリーカード（支出タブから使う）。
/// タップで固定費・サブスク管理画面へ。
class SubscriptionSummaryCard extends StatelessWidget {
  const SubscriptionSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return const SizedBox.shrink();
    final now = DateTime.now();
    return StreamBuilder<List<Subscription>>(
      stream: SubscriptionRepository.instance.watch(hid),
      builder: (context, snap) {
        final subs = snap.data ?? const <Subscription>[];
        final total = subs
            .where((s) => s.appliesTo(now.year, now.month))
            .fold<int>(0, (t, s) => t + s.amountForMonth(now.year, now.month));
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
                Text(subs.isEmpty ? '毎月の固定費を登録' : '今月の合計',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSub)),
                const Spacer(),
                Text(subs.isEmpty ? '登録する' : formatYen(total),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
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
}

/// 固定費・サブスク管理（毎月/毎年の決まった支出）。
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _now = DateTime.now();
  bool _recording = false;

  Future<void> _openEdit([Subscription? editing]) async {
    final result = await showModalBottomSheet<Subscription>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _SubEditSheet(editing: editing),
      ),
    );
    if (result == null) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    if (result.amount < 0) {
      // 削除シグナル（amount=-1）
      await SubscriptionRepository.instance.delete(hid, result.id);
    } else {
      await SubscriptionRepository.instance.save(hid, result);
    }
  }

  Future<void> _recordThisMonth(List<Subscription> subs) async {
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return;
    final ym =
        '${_now.year}${_now.month.toString().padLeft(2, '0')}';
    final due = subs.where((s) => s.appliesTo(_now.year, _now.month)).toList();
    if (due.isEmpty) {
      _toast('今月の固定費はありません');
      return;
    }
    setState(() => _recording = true);
    final keys = {for (final s in due) s.id: 'sub-${s.id}-$ym'};
    final existing = await TxRepository.instance
        .existingReceiptIds(hid, keys.values.toList());
    final txns = <core.Transaction>[];
    for (final s in due) {
      final rid = keys[s.id]!;
      if (existing.contains(rid)) continue; // 既に記録済み
      final day = (s.payDay != null && s.payDay! >= 1 && s.payDay! <= 28)
          ? s.payDay!
          : 1;
      txns.add(core.Transaction(
        id: '${DateTime.now().microsecondsSinceEpoch}-${txns.length}',
        date: DateTime(_now.year, _now.month, day),
        type: core.TransactionType.expense,
        category: core.Category(major: s.category, sub: ''),
        paymentMethod: '',
        description: s.name,
        amount: s.amountForMonth(_now.year, _now.month),
        receiptId: rid,
        paidBy: s.paidBy,
        memo: '固定費',
      ));
    }
    if (txns.isNotEmpty) {
      await TxRepository.instance.addAll(hid, txns, uid);
    }
    if (!mounted) return;
    setState(() => _recording = false);
    final skipped = due.length - txns.length;
    _toast(txns.isEmpty
        ? '今月分はすべて記録済みです'
        : '${txns.length}件を支出に記録しました'
            '${skipped > 0 ? '（$skipped件は記録済み）' : ''}');
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// 変動費の「今月の実額」を入力して保存する。
  Future<void> _inputActual(Subscription s) async {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    final ym = Subscription.ymKey(_now.year, _now.month);
    final ctrl =
        TextEditingController(text: s.monthlyActuals[ym]?.toString() ?? '');
    final v = await showDialog<int>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${_now.month}月の「${s.name}」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.previousActual(_now.year, _now.month) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    '前月: ${formatYen(s.previousActual(_now.year, _now.month)!)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '今月の実額（円）',
                suffixText: '円',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('やめる')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dctx, int.tryParse(ctrl.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (v == null || v < 0) return;
    final next = Map<String, int>.from(s.monthlyActuals)..[ym] = v;
    await SubscriptionRepository.instance
        .save(hid, s.copyWith(monthlyActuals: next));
    if (mounted) _toast('${_now.month}月の実額を保存しました');
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(title: const Text('固定費・サブスク')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('追加', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Subscription>>(
              stream: SubscriptionRepository.instance.watch(hid),
              builder: (context, snap) {
                final subs = snap.data ?? const <Subscription>[];
                final monthly = subs
                    .where((s) => s.appliesTo(_now.year, _now.month))
                    .fold<int>(
                        0,
                        (t, s) =>
                            t + s.amountForMonth(_now.year, _now.month));
                final fixed = subs.where((s) => !s.variable).toList();
                final variable = subs.where((s) => s.variable).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    _header(monthly, subs),
                    const SizedBox(height: 16),
                    if (subs.isEmpty)
                      _empty()
                    else ...[
                      if (fixed.isNotEmpty) ...[
                        _sectionLabel('金額固定', Icons.lock_outline_rounded),
                        ...fixed.map(_tile),
                        const SizedBox(height: 8),
                      ],
                      if (variable.isNotEmpty) ...[
                        _sectionLabel(
                            '変動費（毎月入力）', Icons.show_chart_rounded),
                        ...variable.map(_tile),
                      ],
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _sectionLabel(String text, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.pinkDark),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
          ],
        ),
      );

  Widget _header(int monthly, List<Subscription> subs) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8FA8), Color(0xFFFF6B8A)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            const Text('今月の固定費',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(formatYen(monthly),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _recording ? null : () => _recordThisMonth(subs),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.pinkDark,
                ),
                icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
                label: Text(_recording ? '記録中…' : '今月分を支出に記録'),
              ),
            ),
          ],
        ),
      );

  Widget _tile(Subscription s) {
    final c = categoryFor(s.category, income: false);
    final freq = s.frequency == SubFrequency.yearly
        ? '毎年${s.yearlyMonth ?? ''}月'
        : '毎月';
    final names = HouseholdService.instance.memberNames;
    final payer = (s.paidBy == null || s.paidBy == kPaidByBoth)
        ? '一緒に'
        : names[s.paidBy];
    return Opacity(
      opacity: s.active ? 1 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onTap: () => _openEdit(s),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(c.icon, color: c.color),
          ),
          title: Text(s.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(
              '$freq　${s.category}'
              '${s.variable ? '　変動' : ''}'
              '${s.payDay != null ? '　${s.payDay}日' : ''}'
              '${payer != null ? '　💳 $payer' : ''}'
              '${s.active ? '' : '　（休止中）'}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
          trailing: s.variable
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        formatYen(
                            s.amountForMonth(_now.year, _now.month)),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.expense)),
                    InkWell(
                      onTap: () => _inputActual(s),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          s.hasActualFor(_now.year, _now.month)
                              ? '実額 ✎'
                              : (s.previousActual(_now.year, _now.month) !=
                                      null
                                  ? '前月 ✎'
                                  : '入力 ✎'),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.pinkDark),
                        ),
                      ),
                    ),
                  ],
                )
              : Text(formatYen(s.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.expense)),
        ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(
          children: [
            const Icon(Icons.event_repeat_rounded,
                size: 48, color: Color(0xFFF3C6D2)),
            const SizedBox(height: 10),
            const Text('家賃・光熱費・サブスクなどを登録しよう',
                style: TextStyle(color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('右下の「追加」から ♡',
                style: TextStyle(color: AppColors.textSub, fontSize: 11)),
          ],
        ),
      );
}

/// 固定費の追加/編集シート。
class _SubEditSheet extends StatefulWidget {
  final Subscription? editing;
  const _SubEditSheet({this.editing});

  @override
  State<_SubEditSheet> createState() => _SubEditSheetState();
}

class _SubEditSheetState extends State<_SubEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _payDay;
  String? _category;
  SubFrequency _freq = SubFrequency.monthly;
  int _yearlyMonth = 1;
  String? _payer;
  bool _active = true;
  bool _variable = false;

  Map<String, String> get _members => HouseholdService.instance.memberNames;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(
        text: (e != null && e.amount > 0) ? e.amount.toString() : '');
    _payDay = TextEditingController(text: e?.payDay?.toString() ?? '');
    _category = e?.category;
    _freq = e?.frequency ?? SubFrequency.monthly;
    _yearlyMonth = e?.yearlyMonth ?? 1;
    // デフォルトは「一緒に」。旧データの未指定(null)も一緒に扱い。
    _payer = e?.paidBy ?? kPaidByBoth;
    _active = e?.active ?? true;
    _variable = e?.variable ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _payDay.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amount.text) ?? 0;
    // 変動費は金額不要（月ごとに実額入力）。固定費は金額必須。
    if (_name.text.trim().isEmpty ||
        _category == null ||
        (!_variable && amount <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_variable
                ? '名前・カテゴリを入力してね'
                : '名前・金額・カテゴリを入力してね')),
      );
      return;
    }
    final id = widget.editing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    Navigator.pop(
      context,
      Subscription(
        id: id,
        name: _name.text.trim(),
        amount: _variable ? 0 : amount,
        category: _category!,
        frequency: _freq,
        yearlyMonth: _freq == SubFrequency.yearly ? _yearlyMonth : null,
        payDay: int.tryParse(_payDay.text),
        paidBy: _payer,
        active: _active,
        variable: _variable,
        // 既存の月別実額は引き継ぐ。
        monthlyActuals: widget.editing?.monthlyActuals ?? const {},
      ),
    );
  }

  void _delete() {
    final e = widget.editing;
    if (e == null) return;
    // amount=-1 を削除シグナルにする
    Navigator.pop(context, e.copyWith(amount: -1));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(widget.editing != null ? '固定費を編集' : '固定費を追加',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (widget.editing != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.pinkDark),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '名前', hintText: '例: 家賃 / Netflix'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('変動費（毎月金額が変わる）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: const Text('水道光熱費など。ONにすると金額は毎月リストから入力します',
                  style: TextStyle(fontSize: 11)),
              activeThumbColor: AppColors.pink,
              value: _variable,
              onChanged: (v) => setState(() => _variable = v),
            ),
            if (!_variable) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration:
                    const InputDecoration(labelText: '金額', prefixText: '¥ '),
              ),
            ],
            const SizedBox(height: 12),
            const Text('カテゴリ',
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in expenseCategories)
                  ChoiceChip(
                    label: Text(c.name),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                    selectedColor: c.color.withValues(alpha: 0.25),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('頻度',
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(height: 6),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('毎月'),
                  selected: _freq == SubFrequency.monthly,
                  onSelected: (_) =>
                      setState(() => _freq = SubFrequency.monthly),
                  selectedColor: AppColors.pinkSoft,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('毎年'),
                  selected: _freq == SubFrequency.yearly,
                  onSelected: (_) =>
                      setState(() => _freq = SubFrequency.yearly),
                  selectedColor: AppColors.pinkSoft,
                ),
                if (_freq == SubFrequency.yearly) ...[
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _yearlyMonth,
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text('$m月')),
                    ],
                    onChanged: (v) =>
                        setState(() => _yearlyMonth = v ?? 1),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _payDay,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: '支払日（任意）', hintText: '例: 27', suffixText: '日'),
            ),
            if (_members.length >= 2) ...[
              const SizedBox(height: 16),
              const Text('だれが払う？',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('一緒に'),
                    selected: _payer == kPaidByBoth,
                    onSelected: (_) =>
                        setState(() => _payer = kPaidByBoth),
                    selectedColor: AppColors.pinkSoft,
                  ),
                  for (final e in _members.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _payer == e.key,
                      onSelected: (_) => setState(() => _payer = e.key),
                      selectedColor: AppColors.pinkSoft,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('有効（集計に含める）'),
              value: _active,
              activeThumbColor: AppColors.pink,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
              child: Text(widget.editing != null ? '保存する' : '追加する ♡'),
            ),
          ],
        ),
      ),
    );
  }
}
