import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/transfer_template.dart';
import '../utils/date_pick.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// 振替入力モーダルを表示する。保存成功時は true を返す。
Future<bool?> showTransferInputModal(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.95,
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAFA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: const TransferInputScreen(),
        ),
      );
    },
  );
}

/// 振替入力画面（口座間のお金の移動）。
/// 収支には影響せず、口座残高だけが付け替わる。
/// 例:
///   - GMOあおぞら → 三井住友（事業資金移動）
///   - 銀行 → 現金（ATM 引出し）
///   - 銀行 → クレジットカード（カード引落）
class TransferInputScreen extends StatefulWidget {
  const TransferInputScreen({super.key, this.initialFromAccount});

  /// 起動時に移動元口座をプリセット（口座詳細画面から呼ばれた時など）。
  final String? initialFromAccount;

  @override
  State<TransferInputScreen> createState() => _TransferInputScreenState();
}

class _TransferInputScreenState extends State<TransferInputScreen> {
  final _settings = SettingsRepository();
  core.PaymentMethodsConfig? _payments;
  List<TransferTemplate> _templates = const [];

  DateTime _date = DateTime.now();
  String? _fromAccount;
  String? _toAccount;
  final _amountCtrl = NoComposingUnderlineController();
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
    final t = await _settings.loadTransferTemplates();
    if (!mounted) return;
    setState(() {
      _payments = p;
      _templates = t.templates;
      if (_fromAccount == null && widget.initialFromAccount != null) {
        _fromAccount = widget.initialFromAccount;
      }
    });
  }

  /// 移動元/先の候補（value=口座名 / label=[種別]口座名）。
  /// 銀行/現金/電子マネー + 固定の「現金」。休眠中(inactive)は除外、クレカは出さない。
  List<({String value, String label})> get _accountChoices {
    final p = _payments;
    final list = <({String value, String label})>[];
    if (p != null) {
      for (final b in p.bankAccounts) {
        if (b.inactive) continue; // 休眠中は候補に出さない
        list.add((
          value: b.name,
          label: '[${b.accountType.shortLabel}]${b.name}',
        ));
      }
    }
    list.add((value: '現金', label: '[現金]現金'));
    return list;
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
    final amount = parseAmount(_amountCtrl.text);
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
    // PC（広い画面）はカレンダー / スマホはホイール、で出し分け（支出・収入と統一）。
    final picked = await pickAdaptiveDate(
      context,
      initial: _date,
      first: DateTime(2018),
      last: DateTime(2035, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  // よく使う振替（テンプレ）セクション。チップタップで移動元/先をセット。
  Widget _buildTemplateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('よく使う振替',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
            const Spacer(),
            TextButton.icon(
              onPressed: _openTemplateManager,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('編集'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
        if (_templates.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: Text('「編集」からよく使う振替（例: 新生銀行→PayPay）を登録できます',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates
                .map((t) => ActionChip(
                      avatar: const Icon(Icons.swap_horiz, size: 16),
                      label: Text(t.label),
                      onPressed: () => _applyTemplate(t),
                    ))
                .toList(),
          ),
      ],
    );
  }

  void _applyTemplate(TransferTemplate t) {
    setState(() {
      _fromAccount = t.fromAccount;
      _toAccount = t.toAccount;
    });
  }

  // テンプレの登録・編集・削除シート。
  Future<void> _openTemplateManager() async {
    final working = List<TransferTemplate>.from(_templates);
    final choices = _accountChoices; // value/label
    String firstValue() => choices.isNotEmpty ? choices.first.value : '現金';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Widget acctDropdown(String value, ValueChanged<String> onChanged) {
              final exists = choices.any((c) => c.value == value);
              return DropdownButton<String>(
                value: exists ? value : null,
                isExpanded: true,
                hint: Text(value),
                items: choices
                    .map((c) => DropdownMenuItem(
                        value: c.value, child: Text(c.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('よく使う振替の編集',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      ...working.asMap().entries.map((e) {
                        final i = e.key;
                        final t = e.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: acctDropdown(t.fromAccount, (v) {
                                  setSheet(() => working[i] =
                                      t.copyWith(fromAccount: v));
                                }),
                              ),
                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward,
                                    size: 16, color: Color(0xFF9CA3AF)),
                              ),
                              Expanded(
                                child: acctDropdown(t.toAccount, (v) {
                                  setSheet(() => working[i] =
                                      working[i].copyWith(toAccount: v));
                                }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFDC2626)),
                                onPressed: () =>
                                    setSheet(() => working.removeAt(i)),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () {
                          final v = firstValue();
                          setSheet(() => working.add(TransferTemplate(
                                id: DateTime.now()
                                    .microsecondsSinceEpoch
                                    .toString(),
                                fromAccount:
                                    _fromAccount ?? v,
                                toAccount: _toAccount ?? v,
                              )));
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('セットを追加'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          // 移動元=先 の不正セットは除外して保存。
                          final cleaned = working
                              .where((t) =>
                                  t.fromAccount.isNotEmpty &&
                                  t.toAccount.isNotEmpty &&
                                  t.fromAccount != t.toAccount)
                              .toList();
                          await _settings.saveTransferTemplates(
                              TransferTemplatesConfig(templates: cleaned));
                          if (!mounted) return;
                          setState(() => _templates = cleaned);
                          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_payments == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final fromCandidates =
        _accountChoices.where((c) => c.value != _toAccount).toList();
    final toCandidates =
        _accountChoices.where((c) => c.value != _fromAccount).toList();
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // よく使う振替（テンプレ）
            _buildTemplateSection(),
            const SizedBox(height: 12),
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
              key: ValueKey('from_$_fromAccount'),
              initialValue: _fromAccount,
              decoration: const InputDecoration(
                labelText: '移動元（必須）',
                border: OutlineInputBorder(),
              ),
              items: fromCandidates
                  .map((c) =>
                      DropdownMenuItem(value: c.value, child: Text(c.label)))
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
              key: ValueKey('to_$_toAccount'),
              initialValue: _toAccount,
              decoration: const InputDecoration(
                labelText: '移動先（必須）',
                border: OutlineInputBorder(),
              ),
              items: toCandidates
                  .map((c) =>
                      DropdownMenuItem(value: c.value, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _toAccount = v),
            ),
            const SizedBox(height: 12),
            // 金額
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                HalfWidthDigitsFormatter(),
                ThousandsSeparatorInputFormatter(),
              ],
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
                  final v = parseAmount(_amountCtrl.text);
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
        ),
      ),
    );
  }
}
