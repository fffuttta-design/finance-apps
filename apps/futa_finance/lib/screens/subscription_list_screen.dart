import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../data/subscription_repository.dart';
import '../utils/formatters.dart';

/// サブスク一覧のCRUD画面。月払い/年払いを統一管理。
class SubscriptionListScreen extends StatefulWidget {
  const SubscriptionListScreen({super.key});

  @override
  State<SubscriptionListScreen> createState() => _SubscriptionListScreenState();
}

class _SubscriptionListScreenState extends State<SubscriptionListScreen> {
  final _repo = SubscriptionRepository.instance;
  final _settings = SettingsRepository();
  SubscriptionConfig? _config;
  PaymentMethodsConfig? _payments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.load();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _config = c;
      _payments = p;
    });
  }

  Future<void> _save() async {
    final c = _config;
    if (c != null) await _repo.save(c);
  }

  void _update(List<Subscription> newList) {
    setState(() => _config = _config!.copyWith(subscriptions: newList));
    _save();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  List<String> get _paymentMethods {
    final p = _payments;
    if (p == null) return const [];
    return [
      ...p.bankAccounts.map((b) => b.name),
      ...p.creditCards.map((c) => c.name),
    ];
  }

  Future<Subscription?> _editDialog(
      BuildContext context, Subscription? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final amountCtrl =
        TextEditingController(text: initial?.amount.toString() ?? '');
    final billingDayCtrl =
        TextEditingController(text: initial?.billingDay?.toString() ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
    SubscriptionCycle cycle = initial?.cycle ?? SubscriptionCycle.monthly;
    DateTime? nextDate = initial?.nextBillingDate;
    String? paymentMethod = initial?.paymentMethod;

    Future<void> pickAnnualDate(StateSetter setLocal) async {
      DateTime temp = nextDate ?? DateTime.now();
      final picked = await showModalBottomSheet<DateTime>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheet) => SafeArea(
          child: SizedBox(
            height: 280,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(sheet, null),
                        child: const Text('キャンセル')),
                    const Text('次回請求日',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    TextButton(
                        onPressed: () => Navigator.pop(sheet, temp),
                        child: const Text('完了',
                            style: TextStyle(
                                color: Color(0xFF1A237E),
                                fontWeight: FontWeight.w700))),
                  ],
                ),
                Container(height: 1, color: const Color(0xFFE5E7EB)),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: temp,
                    minimumDate: DateTime(2020),
                    maximumDate: DateTime(2035, 12, 31),
                    dateOrder: DatePickerDateOrder.ymd,
                    onDateTimeChanged: (d) => temp = d,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (picked != null) setLocal(() => nextDate = picked);
    }

    return showDialog<Subscription?>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(initial == null ? 'サブスクを追加' : 'サブスクを編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'サービス名（必須）',
                        hintText: '例: ChatGPT, Claude Pro')),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '金額 円（必須）'),
                ),
                const SizedBox(height: 12),
                // サイクル切替
                const Text('請求サイクル',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 4),
                SegmentedButton<SubscriptionCycle>(
                  segments: const [
                    ButtonSegment(
                      value: SubscriptionCycle.monthly,
                      label: Text('月払い'),
                      icon: Icon(Icons.calendar_view_month),
                    ),
                    ButtonSegment(
                      value: SubscriptionCycle.annually,
                      label: Text('年払い'),
                      icon: Icon(Icons.calendar_today),
                    ),
                  ],
                  selected: {cycle},
                  onSelectionChanged: (s) =>
                      setLocal(() => cycle = s.first),
                ),
                const SizedBox(height: 12),
                // サイクルごとの追加フィールド
                if (cycle == SubscriptionCycle.monthly) ...[
                  TextField(
                    controller: billingDayCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: '毎月の請求日（1〜31、任意）',
                      counterText: '',
                    ),
                  ),
                ] else ...[
                  InkWell(
                    onTap: () => pickAnnualDate(setLocal),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Text(
                            nextDate == null
                                ? '次回請求日を選択'
                                : '${nextDate!.year}年${nextDate!.month}月${nextDate!.day}日',
                            style: TextStyle(
                                fontSize: 14,
                                color: nextDate == null
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF111827)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_paymentMethods.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(
                        labelText: '支払方法（任意）'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('（未指定）')),
                      ..._paymentMethods.map((p) => DropdownMenuItem(
                          value: p, child: Text(p))),
                    ],
                    onChanged: (v) => setLocal(() => paymentMethod = v),
                  ),
                const SizedBox(height: 8),
                TextField(
                    controller: memoCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: '備考（任意）')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final amount = int.tryParse(amountCtrl.text.trim());
                if (name.isEmpty || amount == null || amount <= 0) {
                  Navigator.pop(ctx, null);
                  return;
                }
                final billingDay =
                    int.tryParse(billingDayCtrl.text.trim());
                final memo =
                    memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
                final result = Subscription(
                  id: initial?.id ?? _genId(),
                  name: name,
                  amount: amount,
                  cycle: cycle,
                  billingDay:
                      cycle == SubscriptionCycle.monthly ? billingDay : null,
                  nextBillingDate:
                      cycle == SubscriptionCycle.annually ? nextDate : null,
                  paymentMethod: paymentMethod,
                  memo: memo,
                );
                Navigator.pop(ctx, result);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final r = await _editDialog(context, null);
    if (r == null) return;
    _update([..._config!.subscriptions, r]);
  }

  Future<void> _edit(int i) async {
    final r = await _editDialog(context, _config!.subscriptions[i]);
    if (r == null) return;
    final list = [..._config!.subscriptions];
    list[i] = r;
    _update(list);
  }

  Future<void> _delete(int i) async {
    final s = _config!.subscriptions[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.name} を削除？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    final list = [..._config!.subscriptions]..removeAt(i);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('サブスク一覧',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: 'サブスクを追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  _summaryBar(config),
                  Expanded(
                    child: config.subscriptions.isEmpty
                        ? _empty()
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: config.subscriptions.length,
                            itemBuilder: (context, i) {
                              final s = config.subscriptions[i];
                              return _tile(
                                  s, () => _edit(i), () => _delete(i));
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryBar(SubscriptionConfig config) {
    if (config.subscriptions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
              child: _sumBlock(
                  '月額合計', formatYen(config.monthlyTotal))),
          Container(
              width: 1, height: 32, color: const Color(0xFFE5E7EB)),
          Expanded(
              child: _sumBlock('年額合計', formatYen(config.annualTotal))),
          Container(
              width: 1, height: 32, color: const Color(0xFFE5E7EB)),
          Expanded(
              child: _sumBlock(
                  '年間総コスト', formatYen(config.totalAnnualCost),
                  highlight: true)),
        ],
      ),
    );
  }

  Widget _sumBlock(String label, String value, {bool highlight = false}) =>
      Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: highlight
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF111827),
                  fontFamily: 'monospace')),
        ],
      );

  Widget _tile(
      Subscription s, VoidCallback onEdit, VoidCallback onDelete) {
    final isMonthly = s.cycle == SubscriptionCycle.monthly;
    final cycleColor =
        isMonthly ? const Color(0xFF1A237E) : const Color(0xFF7C3AED);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cycleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.cycleLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cycleColor),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                formatYen(s.amount),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF111827)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              if (isMonthly && s.billingDay != null)
                _chip(Icons.event, '毎月${s.billingDay}日'),
              if (!isMonthly && s.nextBillingDate != null)
                _chip(Icons.calendar_today,
                    '次回 ${s.nextBillingDate!.year}/${s.nextBillingDate!.month}/${s.nextBillingDate!.day}'),
              if (s.paymentMethod != null)
                _chip(Icons.payment, s.paymentMethod!),
              if (isMonthly)
                _chip(Icons.show_chart, '年換算 ${formatYen(s.annualEquivalent)}',
                    color: const Color(0xFF9CA3AF))
              else
                _chip(Icons.show_chart, '月換算 ${formatYen(s.monthlyEquivalent)}',
                    color: const Color(0xFF9CA3AF)),
            ],
          ),
          if (s.memo != null) ...[
            const SizedBox(height: 4),
            Text(s.memo!,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit,
                    size: 18, color: Color(0xFF6B7280)),
                onPressed: onEdit,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFDC2626)),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) {
    final c = color ?? const Color(0xFF6B7280);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11, color: c)),
      ],
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.subscriptions,
                size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('サブスクが未登録です',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            const Text('ChatGPT・Claude Pro・GMOバーチャルオフィスなどを登録',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('サブスクを追加'),
              onPressed: _add,
            ),
          ],
        ),
      );
}
