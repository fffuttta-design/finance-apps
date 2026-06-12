import 'package:flutter/material.dart';

import '../utils/thousands_separator_input_formatter.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/income_source_repository.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/date_pick.dart';
import '../utils/duplicate_check.dart';
import '../utils/formatters.dart';
import 'income_master_screen.dart';

/// 収入入力モーダルを表示する。保存成功時は true を返す。
Future<bool?> showIncomeInputModal(BuildContext context) {
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
          child: const IncomeInputScreen(),
        ),
      );
    },
  );
}

/// 収入を1件入力する画面（マスタから選択）。
///
/// 残高の自動計算・手動上書きは廃止（金の流れは取引で記録。残高調整は
/// 専用画面＋「残高調整」科目の取引で厳正に行う方針）。現在残高は参考表示のみ。
class IncomeInputScreen extends StatefulWidget {
  const IncomeInputScreen(
      {super.key, this.initialReceiveAccount, this.editing});

  /// 起動時に入金先口座をプリセット（口座詳細画面から呼ばれた時など）。
  final String? initialReceiveAccount;

  /// 既存の収入取引の編集（指定すると編集モード：プリフィル＋更新/削除）。
  final core.Transaction? editing;

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
  final _amountCtrl = NoComposingUnderlineController();
  final _memoCtrl = TextEditingController();

  /// 見込み売上として記録するか。デフォルト false（=確定）。
  /// 発生主義の運用で「発生月に計上、実額は来月確定」の時に使う。
  bool _isPending = false;
  final _amountFocus = FocusNode();
  bool _saving = false;

  /// 選択中の銀行口座の現在残高。
  int _currentBalance = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _date = e.date;
      _amountCtrl.text = formatAmount(e.amount);
      _descCtrl.text = e.description;
      if (e.memo != null) _memoCtrl.text = e.memo!;
      _isPending = e.isPending;
      _receiveAccount = e.paymentMethod;
    }
    _load();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await IncomeSourceRepository.instance.load();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _sources = s;
      _payments = p;
      final e = widget.editing;
      if (e != null) {
        // 編集モード：収入源と入金先を復元。
        core.IncomeSource? src;
        for (final x in s.sources) {
          if (x.id == e.incomeSourceId || x.name == e.category.major) {
            src = x;
            break;
          }
        }
        _selectedSource = src;
        _receiveAccount = e.paymentMethod;
        _onReceiveAccountChanged(e.paymentMethod);
      } else if (_receiveAccount == null &&
          widget.initialReceiveAccount != null) {
        // 呼び出し元から入金先プリセットがあれば適用
        _receiveAccount = widget.initialReceiveAccount;
        _onReceiveAccountChanged(_receiveAccount);
      }
    });
  }

  void _onSourceSelected(core.IncomeSource? s) {
    setState(() {
      _selectedSource = s;
      if (s != null) {
        _descCtrl.text = s.name;
        if (s.expectedAmount != null) {
          _amountCtrl.text = formatAmount(s.expectedAmount!);
        }
      }
    });
  }

  void _onReceiveAccountChanged(String? name) {
    setState(() => _receiveAccount = name);
    if (name == null) {
      setState(() => _currentBalance = 0);
      return;
    }
    final bank = _payments?.bankAccounts.firstWhere(
      (b) => b.name == name,
      orElse: () => const core.RegisteredBankAccount(id: '', name: ''),
    );
    setState(() {
      _currentBalance = bank?.displayBalance ?? 0;
    });
  }

  Future<void> _pickDate() async {
    // PC（広い画面）はカレンダー / スマホはホイール、で出し分け。
    final minDate = AppModeManager.instance.current.minDate;
    final picked = await pickAdaptiveDate(
      context,
      initial: _date,
      first: minDate,
      last: DateTime(2030, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _delete() async {
    final e = widget.editing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('この収入を削除？'),
        content: Text(
            '${e.date.month}/${e.date.day} ${e.description.isEmpty ? e.category.major : e.description} +${formatYen(e.amount)}\n削除すると元に戻せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    await TransactionRepository.instance.delete(e.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSource == null || _receiveAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('収入マスタと入金先を選んでください')),
      );
      return;
    }
    final amount = parseAmount(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金額は1以上の整数を入力してください')),
      );
      return;
    }
    setState(() => _saving = true);
    final editing = widget.editing;
    final tx = core.Transaction(
      id: editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      type: core.TransactionType.income,
      // 大カテゴリ＝収入源名（＝売上科目）。PLが売上を科目別に内訳表示でき、
      // 「受取利息/受取配当金/雑収入」等の名前なら自動で営業外収益に分類される。
      category: core.Category(
        major: _selectedSource!.name,
        sub: _selectedSource!.clientName ?? '',
      ),
      paymentMethod: _receiveAccount!,
      description: _descCtrl.text.trim(),
      amount: amount,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      incomeSourceId: _selectedSource!.id,
      isPending: _isPending,
    );
    if (editing != null) {
      // 編集：記録を更新するだけ（残高は二重加算を避けるため触らない）。
      await TransactionRepository.instance.update(tx);
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }
    // 新規追加：同じ日付・同じ金額の既存データがあれば確認（秘書登録分も検知）。
    if (!await confirmIfDuplicateTransaction(context, tx)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    await TransactionRepository.instance.add(tx);

    // 入金先ウォレットの残高を自動で増やす（金額ぶん）。手で残高をいじる機能は無し。
    // 見込み売上は実際にはまだ入金されていないので、残高は更新しない。
    if (!_isPending && _payments != null) {
      final newBalance = _currentBalance + amount;
      final updated = _payments!.bankAccounts.map((b) {
        if (b.name == _receiveAccount) {
          return b.copyWith(currentBalance: newBalance);
        }
        return b;
      }).toList();
      await _settings
          .savePayments(_payments!.copyWith(bankAccounts: updated));
    }

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
        title: Text(widget.editing != null ? '収入を編集' : '収入を記録',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.editing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFDC2626)),
              tooltip: 'この収入を削除',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
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
                        onChanged: _onReceiveAccountChanged,
                        decoration: _inputDecoration(hint: '選択してください'),
                      ),

                    if (_receiveAccount != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '現在残高: ${formatYen(_currentBalance)}',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    _label('理由・内容'),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: _inputDecoration(),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '入力してください' : null,
                    ),
                    const SizedBox(height: 16),

                    // 見込みトグル（発生主義・案A 拡張）。
                    // ON: 発生月に見込み額で計上、入金は来月以降。
                    //     残高は更新しない（実際に入金されてないため）。
                    // OFF: 通常の入金記録（残高も更新）。
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: _isPending
                            ? const Color(0xFFFEF3C7)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _isPending
                                ? const Color(0xFFD97706)
                                : const Color(0xFFE5E7EB)),
                      ),
                      child: SwitchListTile(
                        value: _isPending,
                        onChanged: (v) => setState(() => _isPending = v),
                        title: const Text('見込み売上として記録',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827))),
                        subtitle: Text(
                            _isPending
                                ? '発生月に計上。残高は更新しない。\n月末締めの「入金締め処理」で確定に切り替え。'
                                : 'OFF: 通常の確定入金として記録（残高も更新）',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280))),
                        secondary: Icon(
                            _isPending
                                ? Icons.hourglass_top
                                : Icons.check_circle_outline,
                            color: _isPending
                                ? const Color(0xFFD97706)
                                : const Color(0xFF6B7280)),
                      ),
                    ),

                    _label(_isPending ? '見込み売上額（円）' : '入金額（円）'),
                    TextFormField(
                      controller: _amountCtrl,
                      focusNode: _amountFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        HalfWidthDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: _inputDecoration(),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 16),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '入力してください';
                        if (parseAmount(v) == null) return '数字のみで入力';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

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
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
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
