import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 収支を1件記録／編集する画面（可愛い系）。
class AddTransactionScreen extends StatefulWidget {
  /// 編集対象（null なら新規）。
  final core.Transaction? editing;

  /// 新規時の初期種別（支出/収入タブのFABから指定）。editing 時は無視。
  final core.TransactionType? initialType;

  /// レシート読み取り等からの初期値（新規時のみ）。
  final int? initialAmount;
  final DateTime? initialDate;
  final String? initialCategory;
  final String? initialDescription;

  const AddTransactionScreen({
    super.key,
    this.editing,
    this.initialType,
    this.initialAmount,
    this.initialDate,
    this.initialCategory,
    this.initialDescription,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  late core.TransactionType _type;
  late DateTime _date;
  String? _category;
  String? _paidBy; // だれが払ったか（uid）
  String? _payment; // 支払方法（現金/クレカ等）
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _saving = false;

  bool get _isIncome => _type == core.TransactionType.income;

  /// 世帯メンバー {uid: 名前}。2人いれば支払者を選べる。
  Map<String, String> get _members => HouseholdService.instance.memberNames;

  @override
  void initState() {
    super.initState();
    final myUid = AuthService.instance.currentUser?.uid;
    final e = widget.editing;
    if (e != null) {
      _type = e.type == core.TransactionType.income
          ? core.TransactionType.income
          : core.TransactionType.expense;
      _date = e.date;
      _category = e.category.major;
      _amountCtrl.text = e.amount.toString();
      _memoCtrl.text = e.description;
      _paidBy = e.paidBy ?? e.recordedBy ?? myUid;
      _payment = e.paymentMethod.isEmpty ? null : e.paymentMethod;
    } else {
      _type = widget.initialType ?? core.TransactionType.expense;
      _date = widget.initialDate ?? DateTime.now();
      _category = widget.initialCategory;
      if (widget.initialAmount != null && widget.initialAmount! > 0) {
        _amountCtrl.text = widget.initialAmount.toString();
      }
      if (widget.initialDescription != null &&
          widget.initialDescription!.isNotEmpty) {
        _memoCtrl.text = widget.initialDescription!;
      }
      _paidBy = myUid;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  List<TxCategory> get _cats {
    final base = _isIncome ? incomeCategories : expenseCategories;
    final custom = HouseholdService.instance.customCats(income: _isIncome);
    return [
      ...base,
      for (final n in custom) categoryFor(n, income: _isIncome),
    ];
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

  Future<void> _save() async {
    final amount = parseYen(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _toast('金額を入力してね');
      return;
    }
    if (_category == null) {
      _toast('カテゴリを選んでね');
      return;
    }
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) {
      _toast('世帯情報の読み込み中です');
      return;
    }
    setState(() => _saving = true);
    final tx = core.Transaction(
      id: widget.editing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      type: _type,
      category: core.Category(major: _category!, sub: ''),
      paymentMethod: _payment ?? '',
      description: _memoCtrl.text.trim(),
      amount: amount,
      paidBy: _paidBy,
    );
    try {
      if (widget.editing != null) {
        await TxRepository.instance.update(hid, tx, uid);
      } else {
        await TxRepository.instance.add(hid, tx, uid);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('保存に失敗しました');
      }
    }
  }

  Future<void> _delete() async {
    final e = widget.editing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('この記録を削除する？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pinkDark),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    setState(() => _saving = true);
    await TxRepository.instance.delete(hid, e.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final accent = _isIncome ? AppColors.income : AppColors.expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing != null ? '記録を編集' : 'きろくする'),
        actions: [
          if (widget.editing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.pinkDark),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            // 支出/収入トグル
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.pinkSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _typeTab('支出', core.TransactionType.expense,
                      AppColors.expense),
                  _typeTab('収入', core.TransactionType.income,
                      AppColors.income),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 金額
            Center(
              child: Column(
                children: [
                  const Text('いくら？',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSub)),
                  const SizedBox(height: 4),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                      decoration: const InputDecoration(
                        prefixText: '¥ ',
                        prefixStyle: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSub),
                        hintText: '0',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 日付
            _section('いつ？'),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: AppColors.pinkDark),
                    const SizedBox(width: 10),
                    Text(
                        '${_date.year}年${_date.month}月${_date.day}日',
                        style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            // カテゴリ
            _section('カテゴリ'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._cats.map(_catChip),
                _addCatChip(),
              ],
            ),
            const SizedBox(height: 18),
            // だれが払った？（支出のみ・2人いるとき）
            if (!_isIncome && _members.length >= 2) ...[
              _section('だれが払った？'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _members.entries
                    .map((e) => _payerChip(e.key, e.value))
                    .toList(),
              ),
              const SizedBox(height: 18),
            ],
            // 支払方法（任意）
            _section('支払方法（任意）'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _payChip(null, 'なし'),
                ...HouseholdService.instance.paymentMethods
                    .map((m) => _payChip(m, m)),
              ],
            ),
            const SizedBox(height: 18),
            // メモ
            _section('メモ（任意）'),
            TextField(
              controller: _memoCtrl,
              decoration: const InputDecoration(hintText: '例: スーパーで買い物'),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: Text(_saving
                  ? '保存中…'
                  : (widget.editing != null ? '更新する' : 'きろくする ♡')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTab(String label, core.TransactionType type, Color color) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          _category = null; // 種別が変わるとカテゴリ候補も変わる
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: selected ? color : AppColors.textSub,
            ),
          ),
        ),
      ),
    );
  }

  Widget _catChip(TxCategory c) {
    final selected = _category == c.name;
    return GestureDetector(
      onTap: () => setState(() => _category = c.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.color.withValues(alpha: 0.22) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.color : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.icon, size: 18, color: c.color),
            const SizedBox(width: 6),
            Text(c.name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _payerChip(String uid, String name) {
    final selected = _paidBy == uid;
    final me = uid == AuthService.instance.currentUser?.uid;
    return GestureDetector(
      onTap: () => setState(() => _paidBy = uid),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.pink.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pink : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.favorite_rounded : Icons.person_rounded,
              size: 18,
              color: selected ? AppColors.pink : AppColors.textSub,
            ),
            const SizedBox(width: 6),
            Text(me ? '$name（じぶん）' : name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _addCatChip() {
    return GestureDetector(
      onTap: _addCustomCategory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.pink, width: 1, style: BorderStyle.solid),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: AppColors.pinkDark),
            SizedBox(width: 4),
            Text('追加',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.pinkDark)),
          ],
        ),
      ),
    );
  }

  Future<void> _addCustomCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('カテゴリを追加'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例: ペット / 車 / 推し活'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('追加')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await HouseholdService.instance
        .addCustomCategory(name, income: _isIncome);
    if (mounted) setState(() => _category = name);
  }

  Widget _payChip(String? value, String label) {
    final selected = _payment == value;
    return GestureDetector(
      onTap: () => setState(() => _payment = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.pink.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pink : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.text)),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );
}
