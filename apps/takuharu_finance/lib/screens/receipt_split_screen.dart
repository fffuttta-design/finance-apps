import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/account.dart';
import '../data/account_repository.dart';
import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/drive_receipt_service.dart';
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

  const ReceiptSplitScreen({
    super.key,
    required this.result,
    this.receiptId,
    this.receiptUrl,
  });

  @override
  State<ReceiptSplitScreen> createState() => _ReceiptSplitScreenState();
}

class _Item {
  final TextEditingController name;
  final TextEditingController price;
  String? category;
  bool personalFood = false; // この品目を個人の食費わくから引くか（食費のときのみ）
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
  String? _payment = _defaultPayment; // 支払元（既定はワンバンク）
  List<Account> _accounts = []; // 登録済みの口座/クレカ
  final _items = <_Item>[];
  late final TextEditingController _storeCtrl; // 店名（読み取り結果を編集できる）
  bool _saving = false;

  /// レシート記録の既定の支払元。手入力画面と揃える。
  static const _defaultPayment = 'ワンバンク';

  Map<String, String> get _members => HouseholdService.instance.memberNames;

  @override
  void initState() {
    super.initState();
    final r = widget.result;
    _date = r.date ?? DateTime.now();
    _storeCtrl = TextEditingController(text: r.store ?? '');
    _payer = AuthService.instance.currentUser?.uid;
    for (final it in r.items) {
      _items.add(_Item(it.name, it.price, it.category ?? r.category));
    }
    // 品目が読めなかった場合でも、編集できるよう空の1行を用意。
    if (_items.isEmpty) {
      _items.add(_Item('', 0, r.category));
    }
    // 登録済みの口座/クレカを読み込む（支払元の選択肢）。
    final hid = HouseholdService.instance.householdId;
    if (hid != null) {
      AccountRepository.instance.loadAll(hid).then((a) {
        if (mounted) setState(() => _accounts = a);
      });
    }
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  int get _total => _items.fold<int>(
      0, (s, i) => s + (int.tryParse(i.price.text) ?? 0));

  /// 食費の品目が1つでもあるか（一括トグルの表示判定）。
  bool get _hasFoodItem => _items.any((i) => i.category == '食費');

  /// 食費の品目が「すべて」個人わくONになっているか（一括トグルの状態）。
  bool get _allFoodPersonal =>
      _hasFoodItem &&
      _items.where((i) => i.category == '食費').every((i) => i.personalFood);

  /// 食費の品目をまとめて個人わくON/OFFする（一括設定）。
  void _toggleAllFoodPersonal() {
    final target = !_allFoodPersonal;
    setState(() {
      for (final i in _items) {
        if (i.category == '食費') i.personalFood = target;
      }
    });
  }

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
    // 支払い方法がないまま登録させない。
    if (_payment == null || _payment!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('支払い方法を選んでね')),
      );
      return;
    }
    final receiptId =
        widget.receiptId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final storeText = _storeCtrl.text.trim();
    final store = storeText.isEmpty ? null : storeText;
    final txns = <core.Transaction>[];
    for (final i in _items) {
      final price = int.tryParse(i.price.text) ?? 0;
      final name = i.name.text.trim();
      if (price <= 0 || name.isEmpty) continue;
      final cat = i.category ?? 'その他';
      txns.add(core.Transaction(
        id: '${DateTime.now().microsecondsSinceEpoch}-${txns.length}',
        date: _date,
        type: core.TransactionType.expense,
        category: core.Category(major: cat, sub: ''),
        paymentMethod: _payment ?? '',
        description: name,
        amount: price,
        store: store,
        receiptId: receiptId,
        // 裏のDrive保存が先に終わっていればキャッシュURLを付与（後付けでも補完）。
        receiptUrl: widget.receiptUrl ??
            DriveReceiptService.instance.urlFor(receiptId),
        paidBy: _payer,
        // 「食費」で個人わくONの品目は、ログイン中の自分の個人食費わくから引く。
        // （相手のわくには入れられない＝常に自分のわく）
        personalFor: (cat == '食費' && i.personalFood) ? uid : null,
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
    return Scaffold(
      appBar: AppBar(title: const Text('品目ごとに記録')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // 共通情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // 店名（読み取り結果を編集できる）
                    Row(children: [
                      const Icon(Icons.storefront_rounded,
                          size: 18, color: AppColors.pinkDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _storeCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '店名（任意）',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
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
                    const SizedBox(height: 10),
                    // 支払元（既定ワンバンク・未選択では登録できない）
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('支払元',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSub)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_accounts.isNotEmpty)
                                ..._accounts.map((a) => _payChip(a.name))
                              else
                                ...HouseholdService.instance.paymentMethods
                                    .map(_payChip),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                // 食費があるレシートだけ、見出しの横に一括トグルのチップを出す。
                if (_hasFoodItem) ...[
                  const SizedBox(width: 8),
                  _bulkPersonalFoodChip(),
                ],
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
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => setState(
                  () => _items.add(_Item('', 0, widget.result.category))),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('品目を追加'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.pinkDark,
                side: const BorderSide(color: AppColors.pinkSoft),
              ),
            ),
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

  /// 食費の品目をまとめて個人の食費わくに入れる一括チップ（見出しの横に置く）。
  /// 個別カードのトグルと連動（全部ONならピンクに点灯）。
  Widget _bulkPersonalFoodChip() {
    final on = _allFoodPersonal;
    return GestureDetector(
      onTap: _toggleAllFoodPersonal,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.pink.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? AppColors.pink : AppColors.divider,
            width: on ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                on
                    ? Icons.check_circle_rounded
                    : Icons.lunch_dining_rounded,
                size: 15,
                color: AppColors.pinkDark),
            const SizedBox(width: 5),
            Text('ぜんぶ個人わく',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _payChip(String name) {
    final selected = _payment == name;
    return GestureDetector(
      onTap: () => setState(() => _payment = name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.pink.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pink : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(name,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.text)),
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
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // カテゴリ選択チップ
                GestureDetector(
                  onTap: () => _pickCategory(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
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
                // 「食費」の品目だけ：個人の食費わくトグル
                if (item.category == '食費')
                  GestureDetector(
                    onTap: () => setState(
                        () => item.personalFood = !item.personalFood),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: item.personalFood
                            ? AppColors.pink.withValues(alpha: 0.18)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: item.personalFood
                              ? AppColors.pink
                              : AppColors.divider,
                          width: item.personalFood ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              item.personalFood
                                  ? Icons.check_circle_rounded
                                  : Icons.lunch_dining_rounded,
                              size: 15,
                              color: AppColors.pinkDark),
                          const SizedBox(width: 5),
                          const Text('個人の食費わく',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
