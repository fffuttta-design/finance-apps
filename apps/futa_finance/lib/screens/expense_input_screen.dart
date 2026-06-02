import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// 支払元のカテゴリ。UI 上はまずこれを選択 → 該当の項目プルダウンが切り替わる。
enum _PayCategory { card, bank, cash, emoney }

extension _PayCategoryX on _PayCategory {
  String get label {
    switch (this) {
      case _PayCategory.card:
        return 'クレカ';
      case _PayCategory.bank:
        return '銀行';
      case _PayCategory.cash:
        return '現金';
      case _PayCategory.emoney:
        return '電子';
    }
  }

  IconData get icon {
    switch (this) {
      case _PayCategory.card:
        return Icons.credit_card;
      case _PayCategory.bank:
        return Icons.account_balance;
      case _PayCategory.cash:
        return Icons.payments;
      case _PayCategory.emoney:
        return Icons.phone_iphone;
    }
  }
}

/// 支出入力モーダルを表示する。保存成功時は true を返す。
Future<bool?> showExpenseInputModal(BuildContext context) {
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
          child: const ExpenseInputScreen(),
        ),
      );
    },
  );
}

/// 支出を1件入力する画面。
///
/// 支払方法に銀行口座を選んだ場合、支出後残高が自動計算される：
/// - 金額編集 → 残高自動更新（現残高 - 支出額）
/// - 残高編集 → 金額自動更新（現残高 - 残高）
/// 保存時は該当銀行のcurrentBalanceを新残高で上書き。
/// クレジットカード選択時は残高欄を表示しない。
class ExpenseInputScreen extends StatefulWidget {
  const ExpenseInputScreen({super.key, this.initialPaymentMethod});

  /// 起動時に支払方法をプリセット（口座詳細画面から呼ばれた時など）。
  final String? initialPaymentMethod;

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

  /// 現在選択中の支払元カテゴリ。デフォルト: クレカ（最も使用頻度が高いため）。
  _PayCategory _payCategory = _PayCategory.card;
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(); // 円金額（USD時はここに概算円）
  final _usdAmountCtrl = TextEditingController(); // USD金額
  final _balanceAfterCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _balanceFocus = FocusNode();
  bool _saving = false;

  /// 入力通貨。'JPY' or 'USD'。
  String _currency = 'JPY';

  /// 選択中の支払い元の現在値。銀行/現金/電子マネーなら残高、カードなら累積額。
  int? _currentBalance;

  /// 選択中の支払い元がクレジットカードなら true。
  /// (true: 支出は累積額に +、false: 支出は残高から -)
  bool _selectedIsCard = false;

  /// 双方向同期の再帰呼び出し防止フラグ。
  bool _syncing = false;

  /// 選択中の支払元がクレカ。null は未選択。
  core.RegisteredCreditCard? _cardFor(String? name) {
    if (name == null || _payments == null) return null;
    for (final c in _payments!.creditCards) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Dropdown のKeyを切り替えるカウンタ。"+ 新規追加"後にウィジェットを
  /// 再生成して内部state(sentinel選択状態)を捨てるために使用。
  int _majorDropdownNonce = 0;
  int _subDropdownNonce = 0;

  /// "+ 新規追加" のセンチネル値（実カテゴリ名と衝突しない一意な文字列）。
  static const _kAddNewSentinel = '__add_new__';

  @override
  void initState() {
    super.initState();
    _load();
    _amountCtrl.addListener(_syncBalanceFromAmount);
    _balanceAfterCtrl.addListener(_syncAmountFromBalance);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _usdAmountCtrl.dispose();
    _balanceAfterCtrl.dispose();
    _memoCtrl.dispose();
    _amountFocus.dispose();
    _balanceFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await _settings.loadCategories();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _categories = c;
      _payments = p;
      // 呼び出し元から支払方法プリセットがあれば、それに合わせてカテゴリも判定。
      if (_paymentMethod == null && widget.initialPaymentMethod != null) {
        _paymentMethod = widget.initialPaymentMethod;
        _payCategory = _categoryOf(_paymentMethod!) ?? _PayCategory.card;
        _onPaymentMethodChanged(_paymentMethod);
      } else {
        // プリセットなし → 現カテゴリ（デフォルト: クレカ）の最上位項目を選択。
        _applyCategoryDefault();
      }
    });
  }

  /// 指定カテゴリの登録項目リスト（並び順そのまま、先頭が最上位）。
  List<String> _methodsFor(_PayCategory cat) {
    final p = _payments;
    if (p == null) return const [];
    switch (cat) {
      case _PayCategory.card:
        return p.creditCards.map((c) => c.name).toList();
      case _PayCategory.bank:
        return p.bankAccounts
            .where((b) => b.accountType == core.AccountType.bank)
            .map((b) => b.name)
            .toList();
      case _PayCategory.cash:
        return p.bankAccounts
            .where((b) => b.accountType == core.AccountType.cash)
            .map((b) => b.name)
            .toList();
      case _PayCategory.emoney:
        return p.bankAccounts
            .where((b) => b.accountType == core.AccountType.emoney)
            .map((b) => b.name)
            .toList();
    }
  }

  /// 支払方法名から、それが属するカテゴリを逆引きする。
  _PayCategory? _categoryOf(String name) {
    final p = _payments;
    if (p == null) return null;
    if (p.creditCards.any((c) => c.name == name)) return _PayCategory.card;
    for (final b in p.bankAccounts) {
      if (b.name == name) {
        switch (b.accountType) {
          case core.AccountType.bank:
            return _PayCategory.bank;
          case core.AccountType.cash:
            return _PayCategory.cash;
          case core.AccountType.emoney:
            return _PayCategory.emoney;
        }
      }
    }
    return null;
  }

  /// 現カテゴリの先頭項目を _paymentMethod にセットして、残高情報も更新する。
  /// 該当カテゴリが空ならクリア。
  void _applyCategoryDefault() {
    final list = _methodsFor(_payCategory);
    if (list.isEmpty) {
      _paymentMethod = null;
      _onPaymentMethodChanged(null);
    } else {
      _paymentMethod = list.first;
      _onPaymentMethodChanged(list.first);
    }
  }

  List<String> get _availableSubs {
    final cfg = _categories;
    final major = _majorCategory;
    if (cfg == null || major == null) return const [];
    final idx = cfg.majors.indexWhere(
        (m) => m.displayName(cfg.majors.indexOf(m)) == major);
    if (idx < 0) return const [];
    return cfg.majors[idx].subs;
  }

  /// 選択中の支払い方法が銀行口座ならその口座を返す。カードなら null。
  core.RegisteredBankAccount? _bankFor(String? name) {
    if (name == null || _payments == null) return null;
    for (final b in _payments!.bankAccounts) {
      if (b.name == name) return b;
    }
    return null;
  }

  void _onPaymentMethodChanged(String? name) {
    setState(() => _paymentMethod = name);
    final bank = _bankFor(name);
    final card = _cardFor(name);
    if (bank != null) {
      setState(() {
        _currentBalance = bank.displayBalance ?? 0;
        _selectedIsCard = false;
      });
    } else if (card != null) {
      setState(() {
        _currentBalance = card.displayBalance;
        _selectedIsCard = true;
      });
    } else {
      setState(() {
        _currentBalance = null;
        _selectedIsCard = false;
      });
      _syncing = true;
      _balanceAfterCtrl.text = '';
      _syncing = false;
      return;
    }
    final amount = parseAmount(_amountCtrl.text) ?? 0;
    _syncing = true;
    _balanceAfterCtrl.text = formatAmount(_computeAfter(amount));
    _syncing = false;
  }

  /// 支出金額から「支出後の値」を計算。
  /// 銀行系: 残高 - 支出 / カード: 累積額 + 支出
  int _computeAfter(int amount) {
    if (_selectedIsCard) {
      return _currentBalance! + amount;
    }
    return _currentBalance! - amount;
  }

  /// 「支出後の値」から支出金額を逆算。
  int _computeAmount(int after) {
    if (_selectedIsCard) {
      return after - _currentBalance!;
    }
    return _currentBalance! - after;
  }

  void _syncBalanceFromAmount() {
    if (_syncing) return;
    if (_currentBalance == null) return;
    if (!_amountFocus.hasFocus) return;
    final amount = parseAmount(_amountCtrl.text) ?? 0;
    final newBalance = formatAmount(_computeAfter(amount));
    if (_balanceAfterCtrl.text != newBalance) {
      _syncing = true;
      _balanceAfterCtrl.text = newBalance;
      _syncing = false;
    }
  }

  void _syncAmountFromBalance() {
    if (_syncing) return;
    if (_currentBalance == null) return;
    if (!_balanceFocus.hasFocus) return;
    final balance = parseAmount(_balanceAfterCtrl.text) ?? 0;
    final newAmount = formatAmount(_computeAmount(balance));
    if (_amountCtrl.text != newAmount) {
      _syncing = true;
      _amountCtrl.text = newAmount;
      _syncing = false;
    }
  }

  /// 大カテゴリの新規追加ダイアログ → 保存 → ドロップダウン選択。
  Future<void> _addNewMajorCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.add_circle_outline, color: Color(0xFF1A237E)),
          SizedBox(width: 8),
          Text('新しい大カテゴリ'),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名前'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('追加')),
        ],
      ),
    );
    // ダイアログを閉じたタイミングで dropdown を再生成（sentinel選択状態を捨てる）
    setState(() => _majorDropdownNonce++);
    if (name == null || name.isEmpty) return;

    final cfg = _categories!;
    final newMajor = core.MajorCategory(name: name, subs: const []);
    final updated =
        cfg.copyWith(majors: [...cfg.majors, newMajor]);
    await _settings.saveCategories(updated);
    if (!mounted) return;
    final newIndex = updated.majors.length - 1;
    setState(() {
      _categories = updated;
      _majorCategory = newMajor.displayName(newIndex);
      _subCategory = null;
      _majorDropdownNonce++;
      _subDropdownNonce++;
    });
  }

  /// 小カテゴリの新規追加ダイアログ → 保存 → ドロップダウン選択。
  Future<void> _addNewSubCategory() async {
    final majorDisplayName = _majorCategory;
    if (majorDisplayName == null) return;

    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.add_circle_outline, color: Color(0xFF1A237E)),
          SizedBox(width: 8),
          Text('新しい小カテゴリ'),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名前'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('追加')),
        ],
      ),
    );
    setState(() => _subDropdownNonce++);
    if (name == null || name.isEmpty) return;

    final cfg = _categories!;
    final majorIdx = cfg.majors.indexWhere(
        (m) => m.displayName(cfg.majors.indexOf(m)) == majorDisplayName);
    if (majorIdx < 0) return;
    final newSubs = [...cfg.majors[majorIdx].subs, name];
    final updatedMajors = [...cfg.majors];
    updatedMajors[majorIdx] =
        cfg.majors[majorIdx].copyWith(subs: newSubs);
    final updated = cfg.copyWith(majors: updatedMajors);
    await _settings.saveCategories(updated);
    if (!mounted) return;
    setState(() {
      _categories = updated;
      _subCategory = name;
      _subDropdownNonce++;
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
                            color: Color(0xFF1A237E),
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
    if (_majorCategory == null ||
        _subCategory == null ||
        _paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カテゴリ・支払方法を選んでください')),
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

    double? usdAmount;
    if (_currency == 'USD') {
      usdAmount = double.tryParse(_usdAmountCtrl.text.trim());
      if (usdAmount == null || usdAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('USD金額は0より大きい数値で入力してください')),
        );
        return;
      }
    }

    final balanceAfter = parseAmount(_balanceAfterCtrl.text);

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
      originalCurrency: _currency == 'USD' ? 'USD' : null,
      originalAmount: usdAmount,
    );
    await TransactionRepository.instance.add(tx);

    // 銀行/カードの残高/累積額を更新
    if (_currentBalance != null && balanceAfter != null && _payments != null) {
      if (_selectedIsCard) {
        // クレジットカードの累積額を更新
        final updatedCards = _payments!.creditCards.map((c) {
          if (c.name == _paymentMethod) {
            return c.copyWith(currentBalance: balanceAfter);
          }
          return c;
        }).toList();
        await _settings
            .savePayments(_payments!.copyWith(creditCards: updatedCards));
      } else {
        // 銀行/現金/電子マネーの残高を更新
        final updated = _payments!.bankAccounts.map((b) {
          if (b.name == _paymentMethod) {
            return b.copyWith(currentBalance: balanceAfter);
          }
          return b;
        }).toList();
        await _settings
            .savePayments(_payments!.copyWith(bankAccounts: updated));
      }
    }

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

    final majorNames = List.generate(categories.majors.length,
        (i) => categories.majors[i].displayName(i));

    final paymentMethods = _methodsFor(_payCategory);
    final hasBalanceTracking = _currentBalance != null;
    final isCard = _selectedIsCard;

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

              _label('大カテゴリ'),
              DropdownButtonFormField<String>(
                key: ValueKey('major-$_majorDropdownNonce'),
                initialValue: _majorCategory,
                items: [
                  for (int i = 0; i < majorNames.length; i++)
                    DropdownMenuItem(
                      value: majorNames[i],
                      child: Text(
                        (categories.majors[i].section != null &&
                                categories.majors[i].section!.isNotEmpty)
                            ? '［${categories.majors[i].section}］${categories.majors[i].name}'
                            : categories.majors[i].name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const DropdownMenuItem(
                    value: _kAddNewSentinel,
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 18, color: Color(0xFF1A237E)),
                        SizedBox(width: 8),
                        Text('新しい大カテゴリを追加',
                            style: TextStyle(color: Color(0xFF1A237E))),
                      ],
                    ),
                  ),
                ],
                onChanged: (v) async {
                  if (v == _kAddNewSentinel) {
                    await _addNewMajorCategory();
                  } else {
                    setState(() {
                      _majorCategory = v;
                      _subCategory = null;
                    });
                  }
                },
                decoration: _inputDecoration(hint: '選択してください'),
              ),
              const SizedBox(height: 16),

              _label('小カテゴリ'),
              DropdownButtonFormField<String>(
                key: ValueKey('sub-$_majorCategory-$_subDropdownNonce'),
                initialValue: _subCategory,
                items: [
                  ..._availableSubs.map((s) =>
                      DropdownMenuItem(value: s, child: Text(s))),
                  if (_majorCategory != null)
                    const DropdownMenuItem(
                      value: _kAddNewSentinel,
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline,
                              size: 18, color: Color(0xFF1A237E)),
                          SizedBox(width: 8),
                          Text('新しい小カテゴリを追加',
                              style: TextStyle(color: Color(0xFF1A237E))),
                        ],
                      ),
                    ),
                ],
                onChanged: _majorCategory == null
                    ? null
                    : (v) async {
                        if (v == _kAddNewSentinel) {
                          await _addNewSubCategory();
                        } else {
                          setState(() => _subCategory = v);
                        }
                      },
                decoration: _inputDecoration(
                    hint: _majorCategory == null ? '先に大カテゴリを選択' : '選択してください'),
              ),
              const SizedBox(height: 16),

              _label('支払方法'),
              // 1段目: カテゴリ選択（クレカ/銀行/現金/電子）。
              // 切替時はそのカテゴリの先頭項目を自動選択（よく使うやつをデフォに）。
              SegmentedButton<_PayCategory>(
                segments: _PayCategory.values
                    .map((c) => ButtonSegment<_PayCategory>(
                          value: c,
                          icon: Icon(c.icon, size: 16),
                          label: Text(c.label,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                selected: {_payCategory},
                showSelectedIcon: false,
                onSelectionChanged: (set) {
                  setState(() {
                    _payCategory = set.first;
                  });
                  _applyCategoryDefault();
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
              ),
              const SizedBox(height: 8),
              // 2段目: 選択カテゴリの項目プルダウン。
              if (paymentMethods.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_payCategory.label}が未登録です。設定 → 銀行口座 / クレジットカード で登録してください。',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF92400E)),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  // カテゴリ切替で項目リストが変わると、前の選択値が無効に
                  // なるケースがあるためカテゴリを Key に含めて再生成。
                  key: ValueKey('pay-${_payCategory.name}'),
                  initialValue: paymentMethods.contains(_paymentMethod)
                      ? _paymentMethod
                      : null,
                  items: paymentMethods
                      .map((p) =>
                          DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: _onPaymentMethodChanged,
                  decoration: _inputDecoration(hint: '選択してください'),
                ),
              if (hasBalanceTracking) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    isCard
                        ? '現在の累積額: ${formatYen(_currentBalance!)}'
                        : '現在残高: ${formatYen(_currentBalance!)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              _label('取引内容'),
              TextFormField(
                controller: _descCtrl,
                decoration: _inputDecoration(),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '入力してください' : null,
              ),
              const SizedBox(height: 16),

              // 通貨は 99% 円なので、デフォルトは「金額（円）」のみ表示。
              // USD で記録したい時だけ右上の小さなリンクで切り替える。
              Row(
                children: [
                  _label(_currency == 'USD'
                      ? '概算金額（円）— 集計に使われる値'
                      : '金額（円）'),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() {
                      _currency = _currency == 'USD' ? 'JPY' : 'USD';
                    }),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        _currency == 'USD' ? '← 円に戻す' : '\$ USD で記録',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_currency == 'USD') ...[
                const SizedBox(height: 6),
                _label('USD金額（\$）'),
                TextFormField(
                  controller: _usdAmountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: _inputDecoration(),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 16),
                  validator: (v) {
                    if (_currency != 'USD') return null;
                    if (v == null || v.trim().isEmpty) return '入力してください';
                    if (double.tryParse(v.trim()) == null) return '数値で入力';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _label('概算金額（円）— 集計に使われる値'),
              ],
              TextFormField(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
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

              if (hasBalanceTracking) ...[
                const SizedBox(height: 16),
                _label(isCard
                    ? '累積後の利用額（円）— 自動計算・編集可'
                    : '支出後の残高（円）— 自動計算・編集可'),
                TextFormField(
                  controller: _balanceAfterCtrl,
                  focusNode: _balanceFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    ThousandsSeparatorInputFormatter(),
                  ],
                  decoration: _inputDecoration().copyWith(
                    prefixIcon: Icon(
                      isCard ? Icons.credit_card : Icons.account_balance,
                      size: 18,
                      color: isCard
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      color: isCard
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFFDC2626),
                      fontWeight: FontWeight.bold),
                ),
              ],
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
