import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/account.dart';
import '../data/account_repository.dart';
import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 差額調整の品目名（レシート税込合計と品目合計の差を埋める1行）。
/// この名前の品目は編集画面では通常の品目リストに出さず、差額調整カードで管理する。
const _kAdjPlus = '消費税・調整'; // 税込合計 > 品目合計（外税レシートの消費税ぶん）
const _kAdjMinus = '値引き・調整'; // 品目合計 > 税込合計（値引き等でマイナス）

/// すでに登録済みの「まとめレシート」（同じ receiptId の品目が複数）を
/// 1画面でまとめて直す。レシート登録（ReceiptSplitScreen）と同じ挙動で、
/// 共通項目（日付・だれ・支払元）も品目ごと（品名・金額・カテゴリ・個人の食費わく）も
/// その場で一括編集できる。保存で「更新／追加／削除」をまとめて反映する。
class ReceiptEditScreen extends StatefulWidget {
  final List<core.Transaction> members;
  const ReceiptEditScreen({super.key, required this.members});

  @override
  State<ReceiptEditScreen> createState() => _ReceiptEditScreenState();
}

class _EItem {
  /// 既存取引の id（新しく足した品目は null）。
  final String? txId;

  /// 既存取引（type 等を引き継ぐため）。
  final core.Transaction? source;
  final TextEditingController name;
  final TextEditingController price;
  String? category;
  bool personalFood; // 食費の品目を個人わくから引くか

  _EItem({
    this.txId,
    this.source,
    required String n,
    required int p,
    this.category,
    this.personalFood = false,
  })  : name = TextEditingController(text: n),
        price = TextEditingController(text: p > 0 ? p.toString() : '');

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _ReceiptEditScreenState extends State<ReceiptEditScreen> {
  late DateTime _date;
  String? _payer;
  String? _payment;
  List<Account> _accounts = [];
  final _items = <_EItem>[];
  bool _saving = false;

  String? _receiptId;
  String? _receiptUrl;
  String? _store;
  late final TextEditingController _storeCtrl;
  // レシート印字の合計（税込）。品目合計とのズレを差額調整で吸収する。
  late final TextEditingController _receiptTotalCtrl;
  bool _addAdjustment = true; // 差額を「消費税・調整」として記録するか
  String? _adjTxId; // 既存の差額調整品目のid（あれば更新、なければ追加）
  core.Transaction? _adjSource; // 既存の差額調整品目（type等の引き継ぎ用）

  static bool _isAdjustment(core.Transaction m) =>
      m.description == _kAdjPlus || m.description == _kAdjMinus;

  Map<String, String> get _members => HouseholdService.instance.memberNames;

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

  @override
  void initState() {
    super.initState();
    final first = widget.members.first;
    _date = first.date;
    _payer = first.paidBy ??
        first.recordedBy ??
        AuthService.instance.currentUser?.uid;
    _payment = first.paymentMethod.isEmpty ? null : first.paymentMethod;
    _receiptId = first.receiptId;
    _receiptUrl = first.receiptUrl;
    _store = widget.members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    _storeCtrl = TextEditingController(text: _store ?? '');
    // 差額調整の品目は通常の品目リストから分離し、差額調整カードで管理する。
    final adjMembers = widget.members.where(_isAdjustment).toList();
    final normalMembers =
        widget.members.where((m) => !_isAdjustment(m)).toList();
    for (final m in normalMembers) {
      _items.add(_EItem(
        txId: m.id,
        source: m,
        n: m.description,
        p: m.amount,
        category: m.category.major,
        // 個人わくは「自分のわく」だけ扱う。相手のわくに入っている品目はOFF表示にし、
        // 保存時も相手のわくを勝手に奪わない（下の _save 参照）。
        personalFood: m.personalFor == AuthService.instance.currentUser?.uid,
      ));
    }
    if (adjMembers.isNotEmpty) {
      _adjSource = adjMembers.first;
      _adjTxId = adjMembers.first.id;
    }
    // 既に差額調整がある＝そのレシートの税込合計は「全品目（調整含む）の合計」。
    // 無ければ空欄にしておき、レシートを見て税込合計を手入力できるようにする。
    final fullTotal = widget.members.fold<int>(0, (s, m) => s + m.amount);
    _receiptTotalCtrl = TextEditingController(
        text: _adjTxId != null ? fullTotal.toString() : '');
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
    _receiptTotalCtrl.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  int get _total =>
      _items.fold<int>(0, (s, i) => s + (int.tryParse(i.price.text) ?? 0));

  /// レシート印字の合計（税込・手修正可）。未入力・0以下なら null。
  int? get _receiptTotal {
    final v = int.tryParse(_receiptTotalCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  /// レシート合計 − 品目合計（＝消費税・送料・値引きなどの差額）。
  int get _adjustment {
    final rt = _receiptTotal;
    return rt == null ? 0 : rt - _total;
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
    if (_payment == null || _payment!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('支払い方法を選んでね')),
      );
      return;
    }

    final storeVal = _storeCtrl.text.trim();
    final store = storeVal.isEmpty ? null : storeVal;
    final keepIds = <String>{};
    final updates = <core.Transaction>[];
    final adds = <core.Transaction>[];
    var newSeq = 0;
    for (final i in _items) {
      final price = int.tryParse(i.price.text) ?? 0;
      final name = i.name.text.trim();
      // 空・0円の品目は「消した」とみなす（既存なら削除、新規なら無視）。
      if (price <= 0 || name.isEmpty) continue;
      final cat = i.category ?? 'その他';
      // 個人わくは常に「自分（ログイン中）のわく」。相手のわくには入れない。
      // トグルOFFでも、相手のわくに入っている既存品目はそのまま維持する。
      final existingPf = i.source?.personalFor;
      final pf = (cat == '食費' && i.personalFood)
          ? uid
          : (existingPf != null && existingPf != uid ? existingPf : null);
      if (i.txId != null && i.source != null) {
        keepIds.add(i.txId!);
        updates.add(i.source!.copyWith(
          date: _date,
          paymentMethod: _payment,
          paidBy: _payer,
          store: store,
          category: core.Category(major: cat, sub: ''),
          description: name,
          amount: price,
          personalFor: pf,
          clearPersonalFor: pf == null,
        ));
      } else {
        adds.add(core.Transaction(
          id: '${DateTime.now().microsecondsSinceEpoch}-${newSeq++}',
          date: _date,
          type: core.TransactionType.expense,
          category: core.Category(major: cat, sub: ''),
          paymentMethod: _payment ?? '',
          description: name,
          amount: price,
          store: store,
          receiptId: _receiptId,
          receiptUrl: _receiptUrl,
          paidBy: _payer,
          personalFor: pf,
        ));
      }
    }

    if (updates.isEmpty && adds.isEmpty) {
      // 全部空 → このレシートを丸ごと消す確認。
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('品目が空です'),
          content: const Text('このレシートを丸ごと削除しますか？'),
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
      if (ok != true) return;
    }

    // 差額調整：レシート税込合計と品目合計の差を1行で吸収する。
    // 通常品目が1つでも残っているときだけ扱う（全消し→削除のケースには足さない）。
    final hasNormal = updates.isNotEmpty || adds.isNotEmpty;
    final adj = (_addAdjustment && _receiptTotal != null) ? _adjustment : 0;
    if (hasNormal && adj != 0) {
      final desc = adj >= 0 ? _kAdjPlus : _kAdjMinus;
      if (_adjTxId != null && _adjSource != null) {
        // 既存の調整行を更新（残すので keepIds に入れて削除対象から外す）。
        keepIds.add(_adjTxId!);
        updates.add(_adjSource!.copyWith(
          date: _date,
          paymentMethod: _payment,
          paidBy: _payer,
          store: store,
          category: core.Category(major: 'その他', sub: ''),
          description: desc,
          amount: adj,
          personalFor: null,
          clearPersonalFor: true,
        ));
      } else {
        adds.add(core.Transaction(
          id: '${DateTime.now().microsecondsSinceEpoch}-adj',
          date: _date,
          type: core.TransactionType.expense,
          category: core.Category(major: 'その他', sub: ''),
          paymentMethod: _payment ?? '',
          description: desc,
          amount: adj,
          store: store,
          receiptId: _receiptId,
          receiptUrl: _receiptUrl,
          paidBy: _payer,
        ));
      }
    }
    // adj==0（または調整OFF）かつ既存の調整行があれば、keepIds に入れないので
    // 下の deletes でそのまま消える（差額が解消されたら調整行も自動で消える）。

    // 残さない品目（消した既存品目＋OFFになった調整行）を削除対象に。
    // ※ keepIds は調整ブロックの後に確定するので、ここで算出する。
    final deletes =
        widget.members.where((m) => !keepIds.contains(m.id)).toList();

    setState(() => _saving = true);
    try {
      for (final d in deletes) {
        await TxRepository.instance.delete(hid, d.id, uid);
      }
      for (final u in updates) {
        await TxRepository.instance.update(hid, u, uid);
      }
      if (adds.isNotEmpty) {
        await TxRepository.instance.addAll(hid, adds, uid);
      }
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
      appBar: AppBar(title: const Text('レシートを編集')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // 共通情報（このレシート全体に効く）
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 店名（編集可）
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
                    const SizedBox(height: 10),
                    // 日付（タップで変更できると分かる見た目に）
                    const Text('日付',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textSub)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 18, color: AppColors.pinkDark),
                          const SizedBox(width: 8),
                          Text('${_date.year}年${_date.month}月${_date.day}日',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Icon(Icons.edit_calendar_rounded,
                              size: 18, color: AppColors.pinkDark),
                        ]),
                      ),
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
              onPressed: () =>
                  setState(() => _items.add(_EItem(n: '', p: 0, category: '食費'))),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('品目を追加'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.pinkDark,
                side: const BorderSide(color: AppColors.pinkSoft),
              ),
            ),
            const SizedBox(height: 16),
            _reconCard(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
              child: Text(_saving ? '保存中…' : '保存する ♡'),
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

  /// レシート印字の合計（税込）と品目合計を突き合わせ、差額を確認・調整するカード。
  /// 外税（税抜）レシートでは品目合計が税抜きになるため、差額＝消費税ぶんを1行で補う。
  /// 記録済みレシートを後から合わせ込むときにも使える（税込合計を手入力）。
  Widget _reconCard() {
    final rt = _receiptTotal;
    final adj = _adjustment;
    return Card(
      color: AppColors.pinkSoft.withValues(alpha: 0.35),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    size: 18, color: AppColors.pinkDark),
                const SizedBox(width: 8),
                const Text('レシート合計（税込）',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const Spacer(),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _receiptTotalCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '¥',
                      hintText: '未入力',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (rt != null) ...[
              const SizedBox(height: 4),
              _reconRow('品目合計', formatYen(_total)),
              _reconRow(adj >= 0 ? '差額（消費税・送料など）' : '差額（値引きなど）',
                  formatYen(adj)),
              if (adj != 0) ...[
                const Divider(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        adj >= 0
                            ? '差額 ${formatYen(adj)} を「消費税・調整」として記録'
                            : '差額 ${formatYen(adj)} を「値引き・調整」として記録',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.text),
                      ),
                    ),
                    Switch(
                      value: _addAdjustment,
                      activeThumbColor: AppColors.pink,
                      onChanged: (v) => setState(() => _addAdjustment = v),
                    ),
                  ],
                ),
                Text(
                  _addAdjustment
                      ? 'レシート合計とピッタリ合います ♡'
                      : '品目合計のまま記録します（差額は記録されません）',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('品目合計と一致しています ♡',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSub)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reconRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
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
                                  fontSize: 12, fontWeight: FontWeight.w600)),
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
