import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 振替入力画面（口座間のお金の移動）。
/// 収支には影響せず、口座残高だけが付け替わる。
/// 例:
///   - GMOあおぞら → 三井住友（事業資金移動）
///   - 銀行 → 現金（ATM 引出し）
///   - 銀行 → クレジットカード（カード引落）
///
/// モバイル: モーダル表示。Web: 右側ドロワーで埋め込み表示。
class TransferInputScreen extends StatefulWidget {
  const TransferInputScreen({super.key});

  @override
  State<TransferInputScreen> createState() => _TransferInputScreenState();
}

class _TransferInputScreenState extends State<TransferInputScreen> {
  final _settings = SettingsRepository();
  core.PaymentMethodsConfig? _payments;

  DateTime _date = DateTime.now();
  String? _fromAccount;
  String? _toAccount;
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
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() => _payments = p);
  }

  /// 移動元/先の候補リスト。
  /// 銀行 + クレカ + 「現金」(固定) を統合。
  List<String> get _accountChoices {
    final p = _payments;
    if (p == null) return const ['現金'];
    return [
      ...p.bankAccounts.map((b) => b.name),
      ...p.creditCards.map((c) => c.name),
      '現金',
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_fromAccount == null || _toAccount == null) return;
    if (_fromAccount == _toAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移動元と移動先が同じです')),
      );
      return;
    }
    final amount = int.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正しい金額を入力してください')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final tx = core.Transaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        date: _date,
        type: core.TransactionType.transfer,
        // 振替時は category 不要だが、空文字でも初期化が要るため固定値。
        category: const core.Category(major: '振替', sub: ''),
        // paymentMethod は使わない。互換のため空文字。
        paymentMethod: '',
        description: '${_fromAccount!} → ${_toAccount!}',
        amount: amount,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        transferFromAccount: _fromAccount,
        transferToAccount: _toAccount,
      );
      await TransactionRepository.instance.add(tx);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: Colors.white,
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context, _date),
                    child: const Text('完了'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _date,
                onDateTimeChanged: (d) => _date = d,
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_payments == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final fromCandidates =
        _accountChoices.where((a) => a != _toAccount).toList();
    final toCandidates =
        _accountChoices.where((a) => a != _fromAccount).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('振替を記録',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _saving ||
                    _fromAccount == null ||
                    _toAccount == null ||
                    _amountCtrl.text.isEmpty
                ? null
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 日付
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '日付',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  '${_date.year}/${_date.month.toString().padLeft(2, '0')}/${_date.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 振替元
            DropdownButtonFormField<String>(
              initialValue: _fromAccount,
              decoration: const InputDecoration(
                labelText: '移動元（必須）',
                border: OutlineInputBorder(),
              ),
              items: fromCandidates
                  .map((a) =>
                      DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) => setState(() => _fromAccount = v),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Icon(Icons.arrow_downward,
                  color: Color(0xFF9CA3AF), size: 20),
            ),
            const SizedBox(height: 8),
            // 振替先
            DropdownButtonFormField<String>(
              initialValue: _toAccount,
              decoration: const InputDecoration(
                labelText: '移動先（必須）',
                border: OutlineInputBorder(),
              ),
              items: toCandidates
                  .map((a) =>
                      DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) => setState(() => _toAccount = v),
            ),
            const SizedBox(height: 12),
            // 金額
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '金額（円）',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_amountCtrl.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Builder(builder: (_) {
                  final v = int.tryParse(
                      _amountCtrl.text.replaceAll(',', ''));
                  if (v == null) return const SizedBox.shrink();
                  return Text(
                    formatYen(v),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  );
                }),
              ),
            const SizedBox(height: 12),
            // 備考
            TextField(
              controller: _memoCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '備考（任意）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                '※ 振替は収支には影響しません。各口座の残高だけが移動します。',
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
