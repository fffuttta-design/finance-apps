import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/account.dart';
import '../data/account_repository.dart';
import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 長押しメニューの結果。
/// - changed … データを変更した（一覧を再読み込みしてほしい）
/// - expand  … 「品目を1つずつ直す」が選ばれた（その場で展開してほしい）
/// - none    … 何もしなかった
enum ReceiptActionResult { changed, expand, none }

/// 「まとめレシート（同じ receiptId の品目が複数）」を長押ししたときに出る
/// 編集メニュー。まとめて編集 / レシートごと削除 を提供する。
Future<ReceiptActionResult> showReceiptActionsSheet(
    BuildContext context, List<core.Transaction> members) async {
  if (members.isEmpty) return ReceiptActionResult.none;
  final total = members.fold<int>(0, (s, t) => s + t.amount);
  final store = members
      .map((t) => t.store?.trim() ?? '')
      .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');

  final action = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.pinkSoft,
                      borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: AppColors.pinkDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      Text('🧾 ${members.length}件まとめ・合計 ${formatYen(total)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppColors.pinkDark),
            title: const Text('まとめて編集',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('日付・支払元・だれ・個人の食費わくを品目ぜんぶに反映'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.touch_app_rounded,
                color: AppColors.pinkDark),
            title: const Text('品目を1つずつ直す',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('レシートをひらいて、品目をタップすると直せます'),
            onTap: () => Navigator.pop(ctx, 'expand'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded,
                color: AppColors.expense),
            title: Text('レシートを削除（${members.length}件すべて）',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.expense)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted) return ReceiptActionResult.none;
  switch (action) {
    case 'edit':
      final c = await _showBatchEditSheet(context, members);
      return c ? ReceiptActionResult.changed : ReceiptActionResult.none;
    case 'expand':
      return ReceiptActionResult.expand;
    case 'delete':
      if (!context.mounted) return ReceiptActionResult.none;
      final c = await _confirmDeleteReceipt(context, members);
      return c ? ReceiptActionResult.changed : ReceiptActionResult.none;
    default:
      return ReceiptActionResult.none;
  }
}

/// レシートを丸ごと削除する確認 → 削除。
Future<bool> _confirmDeleteReceipt(
    BuildContext context, List<core.Transaction> members) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('このレシートを削除しますか？'),
      content: Text('品目 ${members.length}件をまとめて削除します。\nこの操作は取り消せません。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('やめる')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('削除する'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final hid = HouseholdService.instance.householdId;
  final uid = AuthService.instance.currentUser?.uid ?? '';
  if (hid == null) return false;
  for (final m in members) {
    await TxRepository.instance.delete(hid, m.id, uid);
  }
  return true;
}

Future<bool> _showBatchEditSheet(
    BuildContext context, List<core.Transaction> members) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _BatchEditSheet(members: members),
    ),
  );
  return result == true;
}

/// まとめレシートの共通項目（日付・支払元・だれ・個人の食費わく）を
/// 品目ぜんぶに一括で適用するフォーム。
class _BatchEditSheet extends StatefulWidget {
  final List<core.Transaction> members;
  const _BatchEditSheet({required this.members});

  @override
  State<_BatchEditSheet> createState() => _BatchEditSheetState();
}

class _BatchEditSheetState extends State<_BatchEditSheet> {
  static const _personalFoodCategory = '食費';

  late DateTime _date;
  String? _payment;
  String? _paidBy;
  bool _personalFood = false;
  List<Account> _accounts = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final first = widget.members.first;
    _date = first.date;
    _payment = first.paymentMethod.isEmpty ? null : first.paymentMethod;
    _paidBy = first.paidBy ?? first.recordedBy;
    // どれか1件でも個人わくが付いていれば初期ONにする。
    _personalFood = widget.members.any((m) => m.personalFor != null);
    final hid = HouseholdService.instance.householdId;
    if (hid != null) {
      AccountRepository.instance.loadAll(hid).then((a) {
        if (mounted) setState(() => _accounts = a);
      });
    }
  }

  /// まとめの中に「食費」の支出が含まれるか（個人わくトグルを出すか判定）。
  bool get _hasFood => widget.members.any((m) =>
      m.type == core.TransactionType.expense &&
      m.category.major == _personalFoodCategory);

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
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return;
    setState(() => _saving = true);
    for (final m in widget.members) {
      // 個人わくは「食費の支出」だけに付ける。ON のときは支払者(だれ)のわくへ。
      final isFood = m.type == core.TransactionType.expense &&
          m.category.major == _personalFoodCategory;
      final wantPersonal = _personalFood && isFood;
      final updated = m.copyWith(
        date: _date,
        paymentMethod: _payment ?? m.paymentMethod,
        paidBy: _paidBy,
        personalFor: wantPersonal ? _paidBy : null,
        clearPersonalFor: !wantPersonal,
      );
      await TxRepository.instance.update(hid, updated, uid);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final names = HouseholdService.instance.memberNames;
    final whoName = (_paidBy != null ? names[_paidBy] : null) ?? '本人';
    final limit = _paidBy != null
        ? HouseholdService.instance.personalFoodBudgetFor(_paidBy!)
        : HouseholdService.defaultPersonalFoodBudget;
    final payOptions = _accounts.isNotEmpty
        ? _accounts.map((a) => a.name).toList()
        : HouseholdService.instance.paymentMethods;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
            const SizedBox(height: 14),
            Text('まとめて編集（${widget.members.length}件）',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('ここで変えた内容を、レシートの品目ぜんぶに反映します。',
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(height: 16),
            _label('いつ？'),
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
                    Text('${_date.year}年${_date.month}月${_date.day}日',
                        style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label('支払元'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final p in payOptions) _payChip(p)],
            ),
            const SizedBox(height: 16),
            _label('だれ'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in names.entries) _personChip(e.key, e.value),
              ],
            ),
            if (_hasFood) ...[
              const SizedBox(height: 16),
              _personalFoodToggle(whoName, limit),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.pink,
                  minimumSize: const Size.fromHeight(48)),
              child: Text(_saving ? '保存中…' : 'まとめて反映する ♡'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );

  Widget _payChip(String name) {
    final selected = _payment == name;
    return GestureDetector(
      onTap: () => setState(() => _payment = name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.pink.withValues(alpha: 0.18)
              : Colors.white,
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

  Widget _personChip(String uid, String name) {
    final selected = _paidBy == uid;
    final icon = HouseholdService.instance.memberIcons[uid];
    return GestureDetector(
      onTap: () => setState(() => _paidBy = uid),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.pink.withValues(alpha: 0.18)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pink : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null && icon.isNotEmpty) ...[
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
            ],
            Text(name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _personalFoodToggle(String whoName, int limit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _personalFood
            ? AppColors.pink.withValues(alpha: 0.10)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _personalFood ? AppColors.pink : AppColors.divider,
          width: _personalFood ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lunch_dining_rounded,
              size: 20, color: AppColors.pinkDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('個人の食費わくから',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text('$whoName の月${formatYen(limit)}わくから引きます（食費の品目のみ）',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          Switch(
            value: _personalFood,
            activeThumbColor: AppColors.pink,
            onChanged: (v) => setState(() => _personalFood = v),
          ),
        ],
      ),
    );
  }
}
