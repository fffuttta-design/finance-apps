import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/date_pick.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// ウォレット（銀行/現金/電子マネー）の残高を、実際の金額に手で合わせる画面。
///
/// 方針（厳格管理）：
/// - 記録上の残高と実際の残高のズレ分を「残高調整」取引として記録する
///   （収入＝増えた / 支出＝減った）。金の流れを途切れさせない。
/// - 収支（月次）に含める。事業モードのPLでは営業外（営業外収益/費用）に分類。
/// - 後から「どれだけ残高調整したか」を取引履歴で振り返れる。
class BalanceAdjustScreen extends StatefulWidget {
  const BalanceAdjustScreen({super.key});

  @override
  State<BalanceAdjustScreen> createState() => _BalanceAdjustScreenState();
}

class _BalanceAdjustScreenState extends State<BalanceAdjustScreen> {
  final _settings = SettingsRepository();
  core.PaymentMethodsConfig? _payments;
  String? _selected; // 選択中ウォレット名
  DateTime _date = DateTime.now();
  final _amountCtrl = NoComposingUnderlineController();
  final _memoCtrl = TextEditingController();
  bool _saving = false;

  /// 残高調整の大カテゴリ名（PL分類で営業外に振り分けるキーにもなる）。
  static const String kCategory = '残高調整';

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() => _payments = p);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  List<core.RegisteredBankAccount> get _wallets {
    final p = _payments;
    if (p == null) return const [];
    return p.bankAccounts.where((b) => !b.inactive).toList();
  }

  core.RegisteredBankAccount? get _selectedAccount {
    final name = _selected;
    if (name == null) return null;
    for (final b in _wallets) {
      if (b.name == name) return b;
    }
    return null;
  }

  int get _currentBalance => _selectedAccount?.displayBalance ?? 0;

  Future<void> _pickDate() async {
    final minDate = AppModeManager.instance.current.minDate;
    final picked = await pickAdaptiveDate(
      context,
      initial: _date,
      first: minDate,
      last: DateTime(2030, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final acc = _selectedAccount;
    final actual = parseAmount(_amountCtrl.text);
    final p = _payments;
    if (acc == null || actual == null || p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ウォレットと実際の残高を入力してください')),
      );
      return;
    }
    final diff = actual - (acc.displayBalance ?? 0);
    setState(() => _saving = true);
    try {
      if (diff != 0) {
        final tx = core.Transaction(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          date: _date,
          type: diff > 0
              ? core.TransactionType.income
              : core.TransactionType.expense,
          category: core.Category(major: kCategory, sub: ''),
          paymentMethod: acc.name,
          description: '残高調整（${acc.name}）',
          amount: diff.abs(),
          memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        );
        await TransactionRepository.instance.add(tx);
      }
      final updated = p.bankAccounts
          .map((b) =>
              b.name == acc.name ? b.copyWith(currentBalance: actual) : b)
          .toList();
      await _settings.savePayments(p.copyWith(bankAccounts: updated));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(diff == 0
              ? '残高は変わりませんでした'
              : '${acc.name} の残高を ${formatYen(actual)} に調整しました'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('調整に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    if (payments == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final wallets = _wallets;
    final acc = _selectedAccount;
    final actual = parseAmount(_amountCtrl.text);
    final diff = (acc != null && actual != null)
        ? actual - (acc.displayBalance ?? 0)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('残高調整',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'ウォレットの残高を実際の金額に合わせます。ズレ分は「残高調整」として'
                    '記録され、収支に含まれます（事業は営業外）。あとから履歴で'
                    'どれだけ調整したか振り返れます。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                ),
                const SizedBox(height: 16),
                _label('ウォレットを選ぶ'),
                if (wallets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('登録済みのウォレットがありません。設定の支払方法マスタで登録してください。',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                  )
                else
                  ...wallets.map(_walletTile),
                if (acc != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: _fieldDeco(),
                    child: Row(
                      children: [
                        const Text('現在の残高（記録上）',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280))),
                        const Spacer(),
                        Text(formatYen(_currentBalance),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('実際の残高（円）'),
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      HalfWidthDigitsFormatter(),
                      ThousandsSeparatorInputFormatter(),
                    ],
                    decoration: _inputDeco().copyWith(prefixText: '¥ '),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (diff != null) _diffPreview(diff),
                  const SizedBox(height: 16),
                  _label('日付'),
                  InkWell(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: _fieldDeco(),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 18, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Text(
                              '${_date.year}年${_date.month}月${_date.day}日（${weekdayKanji(_date)}）',
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('メモ（任意・理由など）'),
                  TextFormField(
                    controller: _memoCtrl,
                    maxLines: 2,
                    decoration: _inputDeco(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(_saving ? '保存中…' : '残高を調整する'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _walletTile(core.RegisteredBankAccount b) {
    final selected = b.name == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selected = b.name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? const Color(0xFF1A237E)
                    : const Color(0xFFE5E7EB),
                width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected
                      ? const Color(0xFF1A237E)
                      : const Color(0xFF9CA3AF)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(b.accountType.shortLabel,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF64748B))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(b.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(formatYen(b.displayBalance ?? 0),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: Color(0xFF374151))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diffPreview(int diff) {
    if (diff == 0) {
      return const Text('差はありません（記録上の残高と同じ）',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)));
    }
    final up = diff > 0;
    final color = up ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              up
                  ? '差額 +${formatYen(diff)} を「残高調整（収入）」として記録'
                  : '差額 -${formatYen(diff.abs())} を「残高調整（支出）」として記録',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280))),
      );

  InputDecoration _inputDeco() => InputDecoration(
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

  BoxDecoration _fieldDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      );
}
