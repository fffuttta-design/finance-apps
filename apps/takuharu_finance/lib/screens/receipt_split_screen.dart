import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/receipt_ocr.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// レシートを品目ごとに1件ずつ記録する画面。
class ReceiptSplitScreen extends StatefulWidget {
  final ReceiptResult result;

  /// レシート画像をDrive保存したときの参照（同じレシートの品目で共有）。
  final String? receiptId;
  final String? receiptUrl;

  /// 上部に「まとめて1件 / 品目ごと」トグルを出すか（OCRフローから true）。
  /// 「まとめて1件」を選ぶと [kReceiptSwitchMode] を返して閉じる。
  final bool showModeToggle;
  const ReceiptSplitScreen({
    super.key,
    required this.result,
    this.receiptId,
    this.receiptUrl,
    this.showModeToggle = false,
  });

  @override
  State<ReceiptSplitScreen> createState() => _ReceiptSplitScreenState();
}

class _Item {
  final TextEditingController name;
  final TextEditingController price;
  String? category;
  _Item(String n, int p, this.category)
      : name = TextEditingController(text: n),
        price = TextEditingController(text: p > 0 ? p.toString() : '');
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _ReceiptSplitScreenState extends State<ReceiptSplitScreen> {
  late DateTime _date;
  String? _payer;
  final _items = <_Item>[];
  bool _saving = false;

  Map<String, String> get _members => HouseholdService.instance.memberNames;

  @override
  void initState() {
    super.initState();
    final r = widget.result;
    _date = r.date ?? DateTime.now();
    _payer = AuthService.instance.currentUser?.uid;
    for (final it in r.items) {
      _items.add(_Item(it.name, it.price, it.category ?? r.category));
    }
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  int get _total => _items.fold<int>(
      0, (s, i) => s + (int.tryParse(i.price.text) ?? 0));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.pink),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCategory(int index) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in expenseCategories)
                GestureDetector(
                  onTap: () => Navigator.pop(sheet, c.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.icon, size: 18, color: c.color),
                        const SizedBox(width: 6),
                        Text(c.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => _items[index].category = chosen);
  }

  Future<void> _save() async {
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return;
    final receiptId =
        widget.receiptId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final store = widget.result.store;
    final txns = <core.Transaction>[];
    for (final i in _items) {
      final price = int.tryParse(i.price.text) ?? 0;
      final name = i.name.text.trim();
      if (price <= 0 || name.isEmpty) continue;
      txns.add(core.Transaction(
        id: '${DateTime.now().microsecondsSinceEpoch}-${txns.length}',
        date: _date,
        type: core.TransactionType.expense,
        category: core.Category(major: i.category ?? 'その他', sub: ''),
        paymentMethod: '',
        description: name,
        amount: price,
        store: store,
        receiptId: receiptId,
        receiptUrl: widget.receiptUrl,
        paidBy: _payer,
      ));
    }
    if (txns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録できる品目がありません')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await TxRepository.instance.addAll(hid, txns, uid);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.result.store;
    return Scaffold(
      appBar: AppBar(title: const Text('品目ごとに記録')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // まとめて1件 / 品目ごと トグル（OCRフローから開いたときだけ）
            if (widget.showModeToggle) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.receipt_long_rounded, size: 16),
                      label: Text('まとめて1件', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.list_alt_rounded, size: 16),
                      label: Text('品目ごと', style: TextStyle(fontSize: 12))),
                ],
                selected: const {true},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  if (s.first == false) {
                    Navigator.pop(context, kReceiptSwitchMode);
                  }
                },
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 12),
            ],
            // 共通情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (store != null && store.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.storefront_rounded,
                            size: 18, color: AppColors.pinkDark),
                        const SizedBox(width: 8),
                        Text(store,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    if (store != null && store.isNotEmpty)
                      const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickDate,
                      child: Row(children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: AppColors.pinkDark),
                        const SizedBox(width: 8),
                        Text('${_date.year}年${_date.month}月${_date.day}日'),
                      ]),
                    ),
                    if (_members.length >= 2) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('だれが払った？',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSub)),
                          const SizedBox(width: 8),
                          ..._members.entries.map((e) {
                            final sel = _payer == e.key;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(e.value),
                                selected: sel,
                                onSelected: (_) =>
                                    setState(() => _payer = e.key),
                                selectedColor: AppColors.pinkSoft,
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('品目（${_items.length}件）',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('合計 ${formatYen(_total)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.expense)),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _items.length; i++) _itemCard(i),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.expense),
              child: Text(_saving ? '保存中…' : '${_items.length}件をきろくする ♡'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(int i) {
    final item = _items[i];
    final cat = categoryFor(item.category ?? 'その他', income: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.name,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '品目名',
                    ),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: item.price,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '¥',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.expense),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textSub),
                  onPressed: () => setState(() => _items.removeAt(i).dispose()),
                ),
              ],
            ),
            const Divider(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _pickCategory(i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.icon, size: 15, color: cat.color),
                      const SizedBox(width: 5),
                      Text(item.category ?? 'カテゴリを選ぶ',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const Icon(Icons.expand_more_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
