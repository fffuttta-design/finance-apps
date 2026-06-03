import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/receipt_ocr.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// 支払元のカテゴリ。表示順 = クレカ・電子・現金・銀行。
enum _PayCat { card, emoney, cash, bank }

extension _PayCatX on _PayCat {
  String get label {
    switch (this) {
      case _PayCat.card:
        return 'クレカ';
      case _PayCat.emoney:
        return '電子';
      case _PayCat.cash:
        return '現金';
      case _PayCat.bank:
        return '銀行';
    }
  }

  IconData get icon {
    switch (this) {
      case _PayCat.card:
        return Icons.credit_card;
      case _PayCat.emoney:
        return Icons.phone_iphone;
      case _PayCat.cash:
        return Icons.payments;
      case _PayCat.bank:
        return Icons.account_balance;
    }
  }
}

/// レシートの品目ごとに「1品目=1取引」で複数まとめて記録する画面。
/// 日付・支払方法・会計科目は共通で設定し、各品目の名前/金額は編集可。
class ReceiptSplitScreen extends StatefulWidget {
  final List<ReceiptItem> items;
  final DateTime? date;
  final String? storeName;

  const ReceiptSplitScreen({
    super.key,
    required this.items,
    this.date,
    this.storeName,
  });

  @override
  State<ReceiptSplitScreen> createState() => _ReceiptSplitScreenState();
}

class _Row {
  bool include;
  final TextEditingController name;
  final TextEditingController amount;
  _Row(this.include, this.name, this.amount);
}

class _ReceiptSplitScreenState extends State<ReceiptSplitScreen> {
  final _settings = SettingsRepository();
  core.CategoryConfig? _categories;
  core.PaymentMethodsConfig? _payments;

  late DateTime _date =
      widget.date ?? DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day);
  String? _major;
  String? _sub;
  String? _paymentMethod;
  _PayCat _payCat = _PayCat.card;
  bool _saving = false;

  late final List<_Row> _rows = widget.items
      .map((it) => _Row(true, TextEditingController(text: it.name),
          TextEditingController(text: formatAmount(it.price))))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.name.dispose();
      r.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = await _settings.loadCategories();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _categories = c;
      _payments = p;
      // 既定カテゴリ（クレカ）の先頭項目を支払方法に。
      _applyPayCategoryDefault();
    });
  }

  /// 現カテゴリの先頭項目を _paymentMethod にセット（空ならクリア）。
  void _applyPayCategoryDefault() {
    final list = _methodsFor(_payCat);
    _paymentMethod = list.isEmpty ? null : list.first;
  }

  /// 指定カテゴリの登録項目名リスト。
  List<String> _methodsFor(_PayCat cat) {
    final p = _payments;
    if (p == null) return const [];
    switch (cat) {
      case _PayCat.card:
        return p.creditCards.map((c) => c.name).toList();
      case _PayCat.bank:
        return p.bankAccounts
            .where((b) => b.accountType == core.AccountType.bank)
            .map((b) => b.name)
            .toList();
      case _PayCat.cash:
        return p.bankAccounts
            .where((b) => b.accountType == core.AccountType.cash)
            .map((b) => b.name)
            .toList();
      case _PayCat.emoney:
        return p.bankAccounts
            .where((b) => b.accountType == core.AccountType.emoney)
            .map((b) => b.name)
            .toList();
    }
  }

  List<String> get _majorNames {
    final c = _categories;
    if (c == null) return const [];
    return [
      for (int i = 0; i < c.majors.length; i++)
        if (!c.majors[i].inactive) c.majors[i].displayName(i)
    ];
  }

  List<String> get _subNames {
    final c = _categories;
    if (c == null || _major == null) return const [];
    final idx = c.majors
        .indexWhere((m) => m.displayName(c.majors.indexOf(m)) == _major);
    if (idx < 0) return const [];
    return c.majors[idx].subs;
  }

  int get _includedTotal {
    int t = 0;
    for (final r in _rows) {
      if (!r.include) continue;
      t += parseAmount(r.amount.text) ?? 0;
    }
    return t;
  }

  int get _includedCount => _rows.where((r) => r.include).length;

  Future<void> _save() async {
    if (_major == null || _sub == null || _paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('支払方法・カテゴリを選んでください')),
      );
      return;
    }
    final toSave = <core.Transaction>[];
    for (final r in _rows) {
      if (!r.include) continue;
      final amt = parseAmount(r.amount.text);
      if (amt == null || amt <= 0) continue;
      final name = r.name.text.trim();
      toSave.add(core.Transaction(
        id: '${DateTime.now().microsecondsSinceEpoch}-${toSave.length}',
        date: _date,
        type: core.TransactionType.expense,
        category: core.Category(major: _major!, sub: _sub!),
        paymentMethod: _paymentMethod!,
        description: name.isEmpty ? (widget.storeName ?? '品目') : name,
        amount: amt,
        memo: widget.storeName,
      ));
    }
    if (toSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録する品目がありません')),
      );
      return;
    }
    setState(() => _saving = true);
    for (final t in toSave) {
      await TransactionRepository.instance.add(t);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${toSave.length}件を記録しました')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _categories != null && _payments != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('品目ごとに記録',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _label('日付'),
                        InkWell(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFFE5E7EB)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_today,
                                  size: 18, color: Color(0xFF6B7280)),
                              const SizedBox(width: 8),
                              Text(
                                  '${_date.year}年${_date.month}月${_date.day}日'),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _label('支払方法（共通）'),
                        // 1段目: カテゴリ選択（クレカ/電子/現金/銀行）。
                        SegmentedButton<_PayCat>(
                          segments: _PayCat.values
                              .map((c) => ButtonSegment<_PayCat>(
                                    value: c,
                                    icon: Icon(c.icon, size: 16),
                                    label: Text(c.label,
                                        style: const TextStyle(fontSize: 12)),
                                  ))
                              .toList(),
                          selected: {_payCat},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => setState(() {
                            _payCat = s.first;
                            _applyPayCategoryDefault();
                          }),
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 2段目: そのカテゴリの項目プルダウン。
                        if (_methodsFor(_payCat).isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_payCat.label}が未登録です。設定で登録してください。',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF92400E)),
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            key: ValueKey('pay-${_payCat.name}'),
                            initialValue:
                                _methodsFor(_payCat).contains(_paymentMethod)
                                    ? _paymentMethod
                                    : null,
                            items: _methodsFor(_payCat)
                                .map((m) => DropdownMenuItem(
                                    value: m, child: Text(m)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _paymentMethod = v),
                            decoration: _dec('選択してください'),
                          ),
                        const SizedBox(height: 12),
                        _label('大カテゴリ（共通）'),
                        DropdownButtonFormField<String>(
                          key: ValueKey('maj-${_major ?? ''}'),
                          initialValue:
                              _majorNames.contains(_major) ? _major : null,
                          items: _majorNames
                              .map((m) => DropdownMenuItem(
                                  value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _major = v;
                            _sub = null;
                          }),
                          decoration: _dec('選択してください'),
                        ),
                        const SizedBox(height: 12),
                        _label('小カテゴリ（共通）'),
                        DropdownButtonFormField<String>(
                          key: ValueKey('sub-${_major ?? ''}-${_sub ?? ''}'),
                          initialValue:
                              _subNames.contains(_sub) ? _sub : null,
                          items: _subNames
                              .map((s) => DropdownMenuItem(
                                  value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => setState(() => _sub = v),
                          decoration: _dec(
                              _major == null ? '先に大カテゴリを選択' : '選択してください'),
                        ),
                        const SizedBox(height: 16),
                        Text('品目（$_includedCount件 / 合計 ${formatYen(_includedTotal)}）',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B7280))),
                        const SizedBox(height: 6),
                        for (final r in _rows) _itemRow(r),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.check),
                          label: Text(_saving
                              ? '保存中…'
                              : '$_includedCount 件を記録する'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _itemRow(_Row r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: r.include,
            onChanged: (v) => setState(() => r.include = v ?? true),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: r.name,
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none, hintText: '品名'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              controller: r.amount,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsSeparatorInputFormatter(),
              ],
              decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  prefixText: '¥',
                  hintText: '0'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2018),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      );
}
