import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/income_source_repository.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import 'income_master_screen.dart';

/// 収入を1件入力する画面（マスタから選択）。
class IncomeInputScreen extends StatefulWidget {
  const IncomeInputScreen({super.key});

  @override
  State<IncomeInputScreen> createState() => _IncomeInputScreenState();
}

class _IncomeInputScreenState extends State<IncomeInputScreen> {
  final _settings = SettingsRepository();
  final _formKey = GlobalKey<FormState>();

  core.IncomeSourceConfig? _sources;
  core.PaymentMethodsConfig? _payments;

  DateTime _date = DateTime.now();
  core.IncomeSource? _selectedSource;
  String? _receiveAccount;
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
    final s = await IncomeSourceRepository.instance.load();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _sources = s;
      _payments = p;
    });
  }

  void _onSourceSelected(core.IncomeSource? s) {
    setState(() {
      _selectedSource = s;
      if (s != null) {
        _descCtrl.text = s.name;
        if (s.expectedAmount != null) {
          _amountCtrl.text = s.expectedAmount.toString();
        }
      }
    });
  }

  Future<void> _pickDate() async {
    DateTime temp = _date;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Container(
          height: 280,
          color: Colors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(sheet, null),
                    child: const Text('キャンセル',
                        style: TextStyle(color: Color(0xFF6B7280))),
                  ),
                  const Text('日付を選択',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827))),
                  TextButton(
                    onPressed: () => Navigator.pop(sheet, temp),
                    child: const Text('完了',
                        style: TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              Container(height: 1, color: const Color(0xFFE5E7EB)),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _date,
                  minimumDate: DateTime(2020),
                  maximumDate: DateTime(2030, 12, 31),
                  dateOrder: DatePickerDateOrder.ymd,
                  onDateTimeChanged: (d) => temp = d,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSource == null || _receiveAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('収入マスタと入金先を選んでください')),
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
      type: core.TransactionType.income,
      // 収入の category は固定で "収入" + sub に取引先 or マスタ名
      category: core.Category(
        major: '収入',
        sub: _selectedSource!.clientName ?? _selectedSource!.name,
      ),
      paymentMethod: _receiveAccount!,
      description: _descCtrl.text.trim(),
      amount: amount,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      incomeSourceId: _selectedSource!.id,
    );
    await TransactionRepository.instance.add(tx);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    final payments = _payments;
    if (sources == null || payments == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final banks = payments.bankAccounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('収入を記録',
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
        child: sources.sources.isEmpty
            ? _emptySourcesPrompt()
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                                  fontSize: 14,
                                  color: Color(0xFF111827)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _label('収入マスタ'),
                    DropdownButtonFormField<core.IncomeSource>(
                      initialValue: _selectedSource,
                      isExpanded: true,
                      items: sources.sources
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  '${s.name}${s.clientName != null ? ' (${s.clientName})' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: _onSourceSelected,
                      decoration: _inputDecoration(hint: 'マスタを選択'),
                    ),
                    const SizedBox(height: 16),

                    _label('入金先（銀行口座）'),
                    if (banks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '銀行口座が未登録です。設定 → 銀行口座 で登録してください。',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF92400E)),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _receiveAccount,
                        items: banks
                            .map((b) => DropdownMenuItem(
                                value: b.name, child: Text(b.name)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _receiveAccount = v),
                        decoration: _inputDecoration(hint: '選択してください'),
                      ),
                    const SizedBox(height: 16),

                    _label('内容'),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: _inputDecoration(hint: '例: 5月分顧問料'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '入力してください' : null,
                    ),
                    const SizedBox(height: 16),

                    _label('金額（円）'),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(hint: '例: 100000'),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 16),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '入力してください';
                        if (int.tryParse(v.trim()) == null) return '数字のみで入力';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _label('備考（任意）'),
                    TextFormField(
                      controller: _memoCtrl,
                      maxLines: 2,
                      decoration: _inputDecoration(hint: ''),
                    ),
                    const SizedBox(height: 32),

                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check),
                      label: Text(_saving ? '保存中…' : '記録する'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _emptySourcesPrompt() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.attach_money,
                  size: 64, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              const Text('収入マスタが未登録です',
                  style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))),
              const SizedBox(height: 4),
              const Text('先に収入マスタを1件以上登録してください',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('収入マスタへ移動'),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IncomeMasterScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      );

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
          borderSide: const BorderSide(color: Color(0xFF16A34A), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      );

  BoxDecoration _fieldDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      );
}
