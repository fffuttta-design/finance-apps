import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 支出を1件入力する画面。
class ExpenseInputScreen extends StatefulWidget {
  const ExpenseInputScreen({super.key});

  @override
  State<ExpenseInputScreen> createState() => _ExpenseInputScreenState();
}

class _ExpenseInputScreenState extends State<ExpenseInputScreen> {
  final _settings = SettingsRepository();
  final _formKey = GlobalKey<FormState>();

  core.CategoryConfig? _categories;
  core.PaymentMethodsConfig? _payments;

  DateTime _date = DateTime.now();
  String? _majorCategory;
  String? _subCategory;
  String? _paymentMethod;
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await _settings.loadCategories();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _categories = c;
      _payments = p;
    });
  }

  List<String> get _availableSubs {
    final cfg = _categories;
    final major = _majorCategory;
    if (cfg == null || major == null) return const [];
    final idx = cfg.majors.indexWhere((m) => m.displayName(cfg.majors.indexOf(m)) == major);
    if (idx < 0) return const [];
    return cfg.majors[idx].subs;
  }

  /// 銀行口座 + クレジットカードを統合した支払方法リスト。
  List<String> get _availablePaymentMethods {
    final p = _payments;
    if (p == null) return const [];
    return [
      ...p.bankAccounts.map((b) => b.name),
      ...p.creditCards.map((c) => c.name),
    ];
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_majorCategory == null ||
        _subCategory == null ||
        _paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カテゴリ・支払方法を選んでください')),
      );
      return;
    }
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金額は1以上の整数を入力してください')),
      );
      return;
    }

    setState(() => _saving = true);
    final tx = core.Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      type: core.TransactionType.expense,
      category:
          core.Category(major: _majorCategory!, sub: _subCategory!),
      paymentMethod: _paymentMethod!,
      description: _descCtrl.text.trim(),
      amount: amount,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
    );
    await TransactionRepository.instance.add(tx);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final payments = _payments;
    if (categories == null || payments == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    // 表示用の大カテゴリ名（インデックス付き）
    final majorNames = List.generate(
        categories.majors.length,
        (i) => categories.majors[i].displayName(i));

    final paymentMethods = _availablePaymentMethods;

    return Scaffold(
      appBar: AppBar(
        title: const Text('支出を記録',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 日付
              _label('日付'),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: _fieldDecoration(),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: Color(0xFF6B7280)),
                      const SizedBox(width: 8),
                      Text(
                        '${_date.year}年${_date.month}月${_date.day}日（${weekdayKanji(_date)}）',
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF111827)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 大カテゴリ
              _label('大カテゴリ'),
              DropdownButtonFormField<String>(
                initialValue: _majorCategory,
                items: majorNames
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _majorCategory = v;
                  _subCategory = null;
                }),
                decoration: _inputDecoration(hint: '選択してください'),
              ),
              const SizedBox(height: 16),

              // 小カテゴリ
              _label('小カテゴリ'),
              DropdownButtonFormField<String>(
                initialValue: _subCategory,
                items: _availableSubs
                    .map((s) =>
                        DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: _majorCategory == null
                    ? null
                    : (v) => setState(() => _subCategory = v),
                decoration: _inputDecoration(
                    hint: _majorCategory == null ? '先に大カテゴリを選択' : '選択してください'),
              ),
              const SizedBox(height: 16),

              // 支払方法
              _label('支払方法'),
              if (paymentMethods.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '支払方法が未登録です。設定 → 銀行口座 / クレジットカード で登録してください。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  items: paymentMethods
                      .map((p) =>
                          DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v),
                  decoration: _inputDecoration(hint: '選択してください'),
                ),
              const SizedBox(height: 16),

              // 内容
              _label('取引内容'),
              TextFormField(
                controller: _descCtrl,
                decoration: _inputDecoration(),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '入力してください' : null,
              ),
              const SizedBox(height: 16),

              // 金額
              _label('金額（円）'),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 16),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '入力してください';
                  if (int.tryParse(v.trim()) == null) return '数字のみで入力';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 備考
              _label('備考（任意）'),
              TextFormField(
                controller: _memoCtrl,
                maxLines: 2,
                decoration: _inputDecoration(),
              ),
              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_saving ? '保存中…' : '記録する'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280)),
        ),
      );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      );

  BoxDecoration _fieldDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      );
}
