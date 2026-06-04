import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_mode.dart';
import '../data/drive_receipt_service.dart';
import '../data/receipt_ocr.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// 支払元のカテゴリ。UI 上はまずこれを選択 → 該当の項目プルダウンが切り替わる。
/// 表示順 = クレカ・電子・現金・銀行（使用頻度の高い順）。
enum _PayCategory { card, emoney, cash, bank }

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
  const ExpenseInputScreen({
    super.key,
    this.initialPaymentMethod,
    this.initialAmount,
    this.initialDate,
    this.initialDescription,
    this.initialMemo,
    this.initialStore,
    this.initialCategoryMajor,
    this.initialCategorySub,
    this.editing,
    this.receiptItems,
    this.receiptId,
    this.initialReceiptUrl,
  });

  /// 起動時に支払方法をプリセット（口座詳細画面から呼ばれた時など）。
  final String? initialPaymentMethod;

  /// レシートOCR等からのプリフィル（任意）。
  final int? initialAmount;
  final DateTime? initialDate;
  final String? initialDescription;
  final String? initialMemo;
  final String? initialStore;

  /// OCRが推定した会計科目（大カテゴリ名）。大カテゴリの初期候補に使う。
  final String? initialCategoryMajor;

  /// OCRが推定した小カテゴリ名。
  final String? initialCategorySub;

  /// 既存取引の編集（指定すると編集モード：全項目プリフィル＋更新/削除）。
  final core.Transaction? editing;

  /// レシートOCRで読み取った品目（2件以上なら上部に記録方法トグルを表示）。
  /// トグルで「品目ごと」を選ぶと [kReceiptSwitchMode] を返して閉じる。
  final List<ReceiptItem>? receiptItems;

  /// 親レシートのグループID（OCR保存時に付与・任意）。
  final String? receiptId;

  /// Drive保存したレシート画像の閲覧リンク（OCR時にプリフィル・任意）。
  final String? initialReceiptUrl;

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
  final _storeCtrl = TextEditingController();
  final _receiptUrlCtrl = TextEditingController();
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

  /// 過去の取引（カテゴリ予測の履歴学習に使う）。
  List<core.Transaction> _history = const [];

  /// ユーザーが手動でカテゴリを選んだか。true なら自動予測で上書きしない。
  bool _categoryTouched = false;

  /// 直近の予測でカテゴリを自動セットしたか（ヒント表示用）。
  bool _categoryPredicted = false;

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
    final e = widget.editing;
    if (e != null) {
      // 編集モード：取引の値をプリフィル（カテゴリ/支払方法は _load で設定）。
      _date = e.date;
      _amountCtrl.text = formatAmount(e.amount);
      _descCtrl.text = e.description;
      if (e.memo != null) _memoCtrl.text = e.memo!;
      if (e.store != null) _storeCtrl.text = e.store!;
      if (e.receiptUrl != null) _receiptUrlCtrl.text = e.receiptUrl!;
      if (e.originalCurrency == 'USD') {
        _currency = 'USD';
        if (e.originalAmount != null) {
          _usdAmountCtrl.text = e.originalAmount!.toString();
        }
      }
    } else {
      // レシートOCR等からのプリフィル。
      if (widget.initialDate != null) _date = widget.initialDate!;
      if (widget.initialAmount != null && widget.initialAmount! > 0) {
        _amountCtrl.text = formatAmount(widget.initialAmount!);
      }
      if (widget.initialDescription != null &&
          widget.initialDescription!.trim().isNotEmpty) {
        _descCtrl.text = widget.initialDescription!.trim();
      }
      if (widget.initialMemo != null &&
          widget.initialMemo!.trim().isNotEmpty) {
        _memoCtrl.text = widget.initialMemo!.trim();
      }
      if (widget.initialStore != null &&
          widget.initialStore!.trim().isNotEmpty) {
        _storeCtrl.text = widget.initialStore!.trim();
      }
      if (widget.initialReceiptUrl != null &&
          widget.initialReceiptUrl!.trim().isNotEmpty) {
        _receiptUrlCtrl.text = widget.initialReceiptUrl!.trim();
      }
    }
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
    _storeCtrl.dispose();
    _receiptUrlCtrl.dispose();
    _amountFocus.dispose();
    _balanceFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await _settings.loadCategories();
    final p = await _settings.loadPayments();
    // カテゴリ予測（履歴学習）用に過去取引を読み込む。
    List<core.Transaction> history = const [];
    try {
      history = await TransactionRepository.instance.loadAll();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _categories = c;
      _payments = p;
      _history = history;
      final e = widget.editing;
      if (e != null) {
        // 編集モード：取引のカテゴリ・支払方法をそのまま復元。
        _majorCategory = e.category.major;
        _subCategory = e.category.sub;
        _categoryTouched = true; // 既存値は予測で上書きしない
        _paymentMethod = e.paymentMethod;
        _payCategory = _categoryOf(e.paymentMethod) ?? _PayCategory.card;
        _onPaymentMethodChanged(e.paymentMethod);
      } else if (_paymentMethod == null &&
          widget.initialPaymentMethod != null) {
        // 呼び出し元から支払方法プリセットがあれば、それに合わせてカテゴリも判定。
        _paymentMethod = widget.initialPaymentMethod;
        _payCategory = _categoryOf(_paymentMethod!) ?? _PayCategory.card;
        _onPaymentMethodChanged(_paymentMethod);
      } else {
        // プリセットなし → 現カテゴリ（デフォルト: クレカ）の最上位項目を選択。
        _applyCategoryDefault();
      }
      // 新規時のカテゴリ自動予測：①OCR科目候補 → ②履歴(店舗/内容)。
      if (e == null && !_categoryTouched) {
        _autoPredictCategory(initial: true);
      }
    });
  }

  /// カテゴリ自動予測。手動選択済みなら何もしない。
  /// 優先: OCR科目候補 → 店舗一致の履歴 → 取引内容一致の履歴。
  void _autoPredictCategory({bool initial = false}) {
    if (_categoryTouched || widget.editing != null) return;
    final cfg = _categories;
    if (cfg == null) return;

    String norm(String s) =>
        s.replaceFirst(RegExp(r'^\d+\.'), '').trim();

    // ① OCRが選んだ大/小カテゴリ（初回のみ）。一覧から選ばせているので基本一致する。
    if (initial) {
      final guess = widget.initialCategoryMajor?.trim();
      if (guess != null && guess.isNotEmpty) {
        for (var i = 0; i < cfg.majors.length; i++) {
          final dn = cfg.majors[i].displayName(i);
          if (dn == guess || norm(dn) == norm(guess)) {
            _majorCategory = dn;
            final subs = cfg.majors[i].subs;
            final guessSub = widget.initialCategorySub?.trim();
            if (guessSub != null && subs.contains(guessSub)) {
              _subCategory = guessSub;
            } else {
              _subCategory = subs.isNotEmpty ? subs.first : null;
            }
            _categoryPredicted = true;
            return;
          }
        }
      }
    }

    // ② 履歴学習：店舗 or 取引内容が一致する過去の支出から最頻カテゴリ。
    final store = _storeCtrl.text.trim().toLowerCase();
    final desc = _descCtrl.text.trim().toLowerCase();
    if (store.isEmpty && desc.isEmpty) return;

    final tally = <String, int>{}; // "majorsub" -> count
    for (final t in _history) {
      if (t.type != core.TransactionType.expense) continue;
      final tStore = (t.store ?? '').trim().toLowerCase();
      final tDesc = t.description.trim().toLowerCase();
      var weight = 0;
      if (store.isNotEmpty && tStore.isNotEmpty && tStore == store) {
        weight = 3; // 店舗完全一致を最優先
      } else if (desc.isNotEmpty &&
          tDesc.isNotEmpty &&
          (tDesc == desc || tDesc.contains(desc) || desc.contains(tDesc))) {
        weight = 1;
      }
      if (weight == 0) continue;
      final key = '${t.category.major}${t.category.sub}';
      tally[key] = (tally[key] ?? 0) + weight;
    }
    if (tally.isEmpty) return;
    final best =
        tally.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final parts = best.split('');
    final major = parts[0];
    final sub = parts.length > 1 ? parts[1] : '';
    // 候補が現在の大カテゴリ一覧に存在する場合のみ採用。
    final exists = [
      for (var i = 0; i < cfg.majors.length; i++) cfg.majors[i].displayName(i)
    ].contains(major);
    if (!exists) return;
    _majorCategory = major;
    _subCategory = sub.isEmpty ? null : sub;
    _categoryPredicted = true;
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

  Future<void> _deleteTxn() async {
    final e = widget.editing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('この取引を削除？'),
        content: Text(
            '${e.date.month}/${e.date.day} ${e.description.isEmpty ? e.paymentMethod : e.description} −${formatYen(e.amount)}\n削除すると元に戻せません。'),
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
    final editing = widget.editing;
    final tx = core.Transaction(
      id: editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      type: core.TransactionType.expense,
      category:
          core.Category(major: _majorCategory!, sub: _subCategory!),
      paymentMethod: _paymentMethod!,
      description: _descCtrl.text.trim(),
      amount: amount,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      store: _storeCtrl.text.trim().isEmpty ? null : _storeCtrl.text.trim(),
      receiptUrl: _receiptUrlCtrl.text.trim().isEmpty
          ? null
          : _receiptUrlCtrl.text.trim(),
      receiptId: widget.receiptId ?? editing?.receiptId,
      originalCurrency: _currency == 'USD' ? 'USD' : null,
      originalAmount: usdAmount,
      isPending: editing?.isPending ?? false,
    );
    if (editing != null) {
      // 編集：記録を更新するだけ（総資産等は取引から自動再計算される。
      // 実測残高=displayBalance は実際には変わらないので触らない）。
      await TransactionRepository.instance.update(tx);
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }
    await TransactionRepository.instance.add(tx);

    // 銀行/現金/電子マネーの残高のみ更新（新規記録時・クレカ累計は廃止）。
    if (!_selectedIsCard &&
        _currentBalance != null &&
        balanceAfter != null &&
        _payments != null) {
      final updated = _payments!.bankAccounts.map((b) {
        if (b.name == _paymentMethod) {
          return b.copyWith(currentBalance: balanceAfter);
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
        title: Text(widget.editing != null ? '支出を編集' : '支出を記録',
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
              tooltip: 'この取引を削除',
              onPressed: _saving ? null : _deleteTxn,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // レシートOCRから来て品目が複数ある時：記録方法トグル。
              if (widget.receiptItems != null &&
                  widget.receiptItems!.length >= 2 &&
                  widget.editing == null) ...[
                _recordModeToggle(perItem: false),
                const SizedBox(height: 16),
              ],
              // 金額をヒーローとして最上部に大きく表示。
              _heroAmount(),
              const SizedBox(height: 20),
              // レシート画像（Drive）がある取引は、上部に開くボタンを出す。
              if (_receiptUrlCtrl.text.trim().isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _openReceiptLink,
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('レシートを見る'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
                    // 休眠カテゴリは候補から隠す（選択中の値だけは残す）。
                    if (!categories.majors[i].inactive ||
                        majorNames[i] == _majorCategory)
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
                      _categoryTouched = true; // 手動選択 → 予測で上書きしない
                      _categoryPredicted = false;
                    });
                  }
                },
                decoration: _inputDecoration(hint: '選択してください'),
              ),
              if (_categoryPredicted) ...[
                const SizedBox(height: 6),
                Row(
                  children: const [
                    Icon(Icons.auto_awesome,
                        size: 13, color: Color(0xFF1A237E)),
                    SizedBox(width: 4),
                    Text('自動でカテゴリを予測しました（変更できます）',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF1A237E))),
                  ],
                ),
              ],
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
                          setState(() {
                            _subCategory = v;
                            _categoryTouched = true;
                            _categoryPredicted = false;
                          });
                        }
                      },
                decoration: _inputDecoration(
                    hint: _majorCategory == null ? '先に大カテゴリを選択' : '選択してください'),
              ),
              const SizedBox(height: 16),

              _label('取引内容'),
              TextFormField(
                controller: _descCtrl,
                decoration: _inputDecoration(),
                onChanged: (_) {
                  if (!_categoryTouched) {
                    setState(() => _autoPredictCategory());
                  }
                },
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '入力してください' : null,
              ),
              const SizedBox(height: 16),

              // 支払方法（金額・カテゴリの次に配置）。
              ..._paymentMethodSection(
                  paymentMethods, hasBalanceTracking, isCard),
              const SizedBox(height: 16),

              // 任意項目は「詳細を追加 ▾」で畳む（店舗・備考・領収書）。
              _detailsExpansion(),
              const SizedBox(height: 28),

              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_saving
                    ? '保存中…'
                    : (widget.editing != null ? '更新する' : '記録する')),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
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

  /// レシート記録の「まとめて1件 / 品目ごと」トグル。
  /// 現在と違う側を選ぶと kReceiptSwitchMode を返して閉じ、呼び出し側が
  /// もう片方の画面を開く。
  Widget _recordModeToggle({required bool perItem}) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
            value: false,
            icon: Icon(Icons.receipt_long, size: 16),
            label: Text('まとめて1件', style: TextStyle(fontSize: 12))),
        ButtonSegment(
            value: true,
            icon: Icon(Icons.list_alt, size: 16),
            label: Text('品目ごと', style: TextStyle(fontSize: 12))),
      ],
      selected: {perItem},
      showSelectedIcon: false,
      onSelectionChanged: (s) {
        if (s.first != perItem) {
          Navigator.pop(context, kReceiptSwitchMode);
        }
      },
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  /// 支払方法セクション（画面下部に配置）。カテゴリ選択＋項目プルダウン＋
  /// （銀行系のみ）現在残高表示・支出後残高入力。
  List<Widget> _paymentMethodSection(
      List<String> paymentMethods, bool hasBalanceTracking, bool isCard) {
    return [
      _label('支払方法'),
      // 1段目: カテゴリ選択（クレカ/電子/現金/銀行）。
      SegmentedButton<_PayCategory>(
        segments: _PayCategory.values
            .map((c) => ButtonSegment<_PayCategory>(
                  value: c,
                  icon: Icon(c.icon, size: 16),
                  label: Text(c.label, style: const TextStyle(fontSize: 12)),
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
      if (paymentMethods.isEmpty)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_payCategory.label}が未登録です。設定で登録してください。',
            style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
          ),
        )
      else
        DropdownButtonFormField<String>(
          key: ValueKey('pay-${_payCategory.name}'),
          initialValue:
              paymentMethods.contains(_paymentMethod) ? _paymentMethod : null,
          items: paymentMethods
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: _onPaymentMethodChanged,
          decoration: _inputDecoration(hint: '選択してください'),
        ),
      if (hasBalanceTracking && !isCard) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '現在残高: ${formatYen(_currentBalance!)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ),
      ],
      // 支出後の残高（銀行系のみ・新規時のみ）。
      if (hasBalanceTracking && widget.editing == null && !isCard) ...[
        const SizedBox(height: 12),
        _label('支出後の残高（円）— 自動計算・編集可'),
        TextFormField(
          controller: _balanceAfterCtrl,
          focusNode: _balanceFocus,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            ThousandsSeparatorInputFormatter(),
          ],
          decoration: _inputDecoration().copyWith(
            prefixIcon: const Icon(Icons.account_balance,
                size: 18, color: Color(0xFFDC2626)),
          ),
          style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              color: Color(0xFFDC2626),
              fontWeight: FontWeight.bold),
        ),
      ],
    ];
  }

  /// 金額入力（ヒーロー）。画面上部に大きく表示。USD 切替もここで行う。
  Widget _heroAmount() {
    final isUsd = _currency == 'USD';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(isUsd ? '概算金額（円）— 集計に使う値' : '金額（円）',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              const Spacer(),
              InkWell(
                onTap: () =>
                    setState(() => _currency = isUsd ? 'JPY' : 'USD'),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  child: Text(isUsd ? '← 円に戻す' : '\$ USD で記録',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          decoration: TextDecoration.underline)),
                ),
              ),
            ],
          ),
          if (isUsd) ...[
            const SizedBox(height: 8),
            _label('USD金額（\$）'),
            TextFormField(
              controller: _usdAmountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDecoration(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              validator: (v) {
                if (_currency != 'USD') return null;
                if (v == null || v.trim().isEmpty) return '入力してください';
                if (double.tryParse(v.trim()) == null) return '数値で入力';
                return null;
              },
            ),
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 8),
          TextFormField(
            controller: _amountCtrl,
            focusNode: _amountFocus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              ThousandsSeparatorInputFormatter(),
            ],
            decoration: _inputDecoration().copyWith(
              prefixText: '¥ ',
              prefixStyle: const TextStyle(
                  fontSize: 22, color: Color(0xFF9CA3AF)),
            ),
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827)),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '入力してください';
              if (parseAmount(v) == null) return '数字のみで入力';
              return null;
            },
          ),
        ],
      ),
    );
  }

  /// 任意項目（店舗・備考・領収書リンク）を「詳細を追加 ▾」で畳む。
  Widget _detailsExpansion() {
    return Theme(
      data: Theme.of(context)
          .copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: const Text('詳細を追加（店舗・備考・領収書）',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        children: [
          _label('店舗（任意）'),
          TextFormField(
            controller: _storeCtrl,
            decoration: _inputDecoration(hint: '例: ファミリーマート').copyWith(
              prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
            ),
            onChanged: (_) {
              if (!_categoryTouched) {
                setState(() => _autoPredictCategory());
              }
            },
          ),
          const SizedBox(height: 16),
          _label('備考（任意）'),
          TextFormField(
            controller: _memoCtrl,
            maxLines: 2,
            decoration: _inputDecoration(),
          ),
          const SizedBox(height: 16),
          _label('領収書リンク（任意）'),
          TextFormField(
            controller: _receiptUrlCtrl,
            keyboardType: TextInputType.url,
            decoration: _inputDecoration(hint: 'Drive等のURLを貼り付け').copyWith(
              prefixIcon: const Icon(Icons.receipt_long_outlined),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 2),
            child: Text(
              '領収書はGoogleドライブ等に保存し、その共有リンクを貼り付けてください（後で開けます）。',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _attachReceiptImage,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('ギャラリー/カメラから追加'),
              ),
              TextButton.icon(
                onPressed: _openReceiptLink,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('レシートを開く'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 領収書リンク（Drive等）を外部で開く。
  Future<void> _openReceiptLink() async {
    final url = _receiptUrlCtrl.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レシートのリンクがありません')),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// ギャラリー/カメラから領収書画像を選び、Driveに保存してリンクを設定する。
  /// レシートOCRを通さず、既存・手入力の支出にも後から画像を添付できる。
  Future<void> _attachReceiptImage() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dctx) => SimpleDialog(
        title: const Text('領収書画像の取得方法'),
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('カメラで撮影'),
            onTap: () => Navigator.pop(dctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('ギャラリーから選択'),
            onTap: () => Navigator.pop(dctx, ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    final xfile = await ImagePicker()
        .pickImage(source: source, imageQuality: 60, maxWidth: 1280);
    if (xfile == null || !mounted) return;
    final bytes = await xfile.readAsBytes();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Text('Driveに保存中...'),
        ]),
      ),
    );
    final link = await DriveReceiptService.instance.uploadReceiptImage(
      bytes: bytes,
      date: _date,
      isBusiness: AppModeManager.instance.current == AppMode.business,
      store: _storeCtrl.text.trim().isEmpty ? null : _storeCtrl.text.trim(),
      amount: parseAmount(_amountCtrl.text),
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (link != null) {
      setState(() => _receiptUrlCtrl.text = link);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レシート画像をDriveに保存しました')),
      );
    } else {
      final reason = DriveReceiptService.instance.lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(reason == null
              ? 'Drive保存に失敗（初回はGoogleの許可が必要・リンク手動貼付も可）'
              : 'Drive保存に失敗: $reason'),
        ),
      );
    }
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
