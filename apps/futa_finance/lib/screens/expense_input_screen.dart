import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:url_launcher/url_launcher.dart';

import '../data/app_mode.dart';
import '../data/drive_receipt_service.dart';
import '../data/receipt_ocr.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/date_pick.dart';
import '../utils/duplicate_check.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../widgets/drive_receipt_picker.dart';
import 'category_editor_screen.dart';
import 'receipt_camera_screen.dart';

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
/// 支払元に銀行/現金/電子マネーを選んだ場合、保存時にその残高を
/// 金額ぶん自動で減らす（現残高 - 支出額）。
/// 手で残高を直接いじる機能は無し（厳格管理。調整は専用画面＋
/// 「残高調整」科目の取引で行う）。クレカは請求側なので残高は触らない。
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
  bool _savingReceipt = false; // レシート画像の保存中フラグ。
  String? _majorCategory;
  String? _subCategory;
  String? _paymentMethod;

  /// 現在選択中の支払元カテゴリ。デフォルト: クレカ（最も使用頻度が高いため）。
  _PayCategory _payCategory = _PayCategory.card;
  final _descCtrl = TextEditingController();
  // 取引内容のサジェスト用フォーカス（フォーカス中だけ候補リストを出す）。
  final _descFocus = FocusNode();
  // 過去の取引内容 → 出現回数（サジェストの並び＝頻度順に使う）。
  Map<String, int> _descCounts = const {};
  // composing 下線（入力中の無駄なアンダーバー）を出さないコントローラ。
  final _amountCtrl =
      NoComposingUnderlineController(); // 円金額（USD時はここに概算円）
  final _usdAmountCtrl = TextEditingController(); // USD金額
  final _memoCtrl = TextEditingController();
  final _storeCtrl = TextEditingController();
  final _receiptUrlCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  bool _saving = false;

  /// 入力通貨。'JPY' or 'USD'。
  String _currency = 'JPY';

  /// 選択中の支払い元の現在値。銀行/現金/電子マネーなら残高、カードなら累積額。
  int? _currentBalance;

  /// 選択中の支払い元がクレジットカードなら true。
  /// (true: 支出は累積額に +、false: 支出は残高から -)
  bool _selectedIsCard = false;

  /// 立替精算モード。ON のとき、支出は全額を計上しつつ、
  /// 他人から受け取る現金ぶんを指定ウォレットに加算する（PL非計上の振替扱い）。
  bool _treatSplit = false;

  /// 自分の負担額（円）。受け取る現金 = 入力金額 − 自分の負担。
  final _myShareCtrl = NoComposingUnderlineController();

  /// 受け取った現金の入金先ウォレット名（現金/口座）。
  String? _splitReceiveWallet;

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
    // フォーカスの変化で候補リストを出し入れするため再描画。
    _descFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _descFocus.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _usdAmountCtrl.dispose();
    _memoCtrl.dispose();
    _storeCtrl.dispose();
    _receiptUrlCtrl.dispose();
    _myShareCtrl.dispose();
    _amountFocus.dispose();
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
    // 取引内容サジェスト用に、過去の支出の内容を頻度集計しておく。
    final descCounts = <String, int>{};
    for (final t in history) {
      if (t.type != core.TransactionType.expense) continue;
      final d = t.description.trim();
      if (d.isEmpty) continue;
      descCounts[d] = (descCounts[d] ?? 0) + 1;
    }
    setState(() {
      _categories = c;
      _payments = p;
      _history = history;
      _descCounts = descCounts;
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
        weight = 4; // 店舗完全一致を最優先
      } else if (desc.isNotEmpty && tDesc.isNotEmpty && tDesc == desc) {
        weight = 3; // 件名（取引内容）の完全一致を強めに
      } else if (desc.isNotEmpty &&
          tDesc.isNotEmpty &&
          (tDesc.contains(desc) || desc.contains(tDesc))) {
        weight = 1; // 部分一致
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
    // 現在の大カテゴリ一覧から、番号を無視して名前一致するものを採用。
    // （並び替えで番号が変わっても過去の予測が効くように）
    String? matchedMajor;
    int matchedIdx = -1;
    for (var i = 0; i < cfg.majors.length; i++) {
      final dn = cfg.majors[i].displayName(i);
      if (dn == major || norm(dn) == norm(major)) {
        matchedMajor = dn;
        matchedIdx = i;
        break;
      }
    }
    if (matchedMajor == null) return;
    _majorCategory = matchedMajor;
    // 予測した小カテゴリは、その大カテゴリの小カテゴリ一覧に在る場合のみ採用
    // （無い値を入れるとドロップダウンが壊れるため）。
    final subsOfMajor =
        matchedIdx >= 0 ? cfg.majors[matchedIdx].subs : const <String>[];
    _subCategory = (sub.isNotEmpty && subsOfMajor.contains(sub)) ? sub : null;
    _categoryPredicted = true;
  }

  /// 取引内容のサジェスト候補（過去の入力から・頻度順に最大6件）。
  /// 入力文字を含む過去の内容を返す（完全一致は除外＝もう入力済みなので）。
  List<String> _descSuggestions() {
    final q = _descCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final matches = _descCounts.keys.where((d) {
      final dl = d.toLowerCase();
      return dl != q && dl.contains(q);
    }).toList()
      ..sort((a, b) => _descCounts[b]!.compareTo(_descCounts[a]!));
    return matches.take(6).toList();
  }

  /// サジェストを選んだとき：内容を確定し、カテゴリ予測も走らせる。
  void _applyDescSuggestion(String text) {
    _descCtrl.text = text;
    _descCtrl.selection = TextSelection.collapsed(offset: text.length);
    setState(() {
      if (!_categoryTouched) _autoPredictCategory();
    });
  }

  /// 取引内容のサジェストリスト（Google風・入力欄の直下に出す）。
  Widget _descSuggestionList() {
    final suggestions = _descSuggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < suggestions.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
            InkWell(
              onTap: () => _applyDescSuggestion(suggestions[i]),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    const Icon(Icons.history,
                        size: 16, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(suggestions[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF111827))),
                    ),
                    const Icon(Icons.north_west,
                        size: 14, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

  /// 支出記録の途中でカテゴリを編集したくなるケース向け。
  /// カテゴリ編集画面を開き、戻ったら最新のカテゴリを読み直して反映する。
  Future<void> _openCategoryEditor() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const CategoryEditorScreen()),
    );
    if (!mounted) return;
    final c = await _settings.loadCategories();
    if (!mounted) return;
    setState(() {
      _categories = c;
      // 選択中のカテゴリが消えていたら整合を取る。
      final majorNames = List.generate(
          c.majors.length, (i) => c.majors[i].displayName(i));
      if (_majorCategory != null && !majorNames.contains(_majorCategory)) {
        _majorCategory = null;
        _subCategory = null;
      } else if (_subCategory != null &&
          !_availableSubs.contains(_subCategory)) {
        _subCategory = null;
      }
      // ドロップダウンを作り直して最新の項目を反映。
      _majorDropdownNonce++;
      _subDropdownNonce++;
    });
  }

  Future<void> _pickDate() async {
    // モード別カットオフ（事業=2025/10・個人=2026/01）より前は選べない。
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

  /// 日付を前後に日単位でずらす（カットオフより前・2030年末より後は不可）。
  void _shiftDate(int deltaDays) {
    final min = AppModeManager.instance.current.minDate;
    final d = DateTime(_date.year, _date.month, _date.day + deltaDays);
    if (d.isBefore(min) || d.isAfter(DateTime(2030, 12, 31))) return;
    setState(() => _date = d);
  }

  /// 「今日/昨日/一昨日」など、今日から[daysAgo]日前に一発セット。
  void _setDateDaysAgo(int daysAgo) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day - daysAgo);
    final min = AppModeManager.instance.current.minDate;
    if (d.isBefore(min)) return;
    setState(() => _date = d);
  }

  bool _dateIsDaysAgo(int daysAgo) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day - daysAgo);
    return _date.year == d.year &&
        _date.month == d.month &&
        _date.day == d.day;
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

    // 立替精算のバリデーション。
    if (_treatSplit) {
      final myShare = parseAmount(_myShareCtrl.text) ?? 0;
      if (myShare > amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自分の負担額が金額を超えています')),
        );
        return;
      }
      if (myShare < amount && _splitReceiveWallet == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現金の受け取り先を選んでください')),
        );
        return;
      }
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

    setState(() => _saving = true);
    final editing = widget.editing;
    // 入力欄が空なら、裏のDrive保存が先に終わっていればキャッシュURLを付与。
    final receiptUrlVal = _receiptUrlCtrl.text.trim().isNotEmpty
        ? _receiptUrlCtrl.text.trim()
        : (widget.receiptId != null
            ? DriveReceiptService.instance.urlFor(widget.receiptId!)
            : null);
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
      receiptUrl: receiptUrlVal,
      receiptId: widget.receiptId ?? editing?.receiptId,
      // 領収書リンク/画像があれば「保存済み」を自動ON。無ければ既存の手動チェックを維持。
      receiptSaved: (receiptUrlVal != null && receiptUrlVal.isNotEmpty)
          ? true
          : (editing?.receiptSaved ?? false),
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
    // 新規追加：同じ日付・同じ金額の既存データがあれば確認（秘書登録分も検知）。
    if (!await confirmIfDuplicateTransaction(context, tx)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    await TransactionRepository.instance.add(tx);

    // 支出元ウォレットの残高を自動で減らす（金額ぶん）。
    // 手で残高を調整する機能は廃止＝厳格管理。残高の調整が要るときは
    // 専用画面＋「残高調整」科目の取引で厳正に行う。
    // 銀行/現金/電子マネーのみ。クレカは請求側なので残高は触らない。
    if (!_selectedIsCard && _currentBalance != null && _payments != null) {
      final newBalance = _currentBalance! - amount;
      final updated = _payments!.bankAccounts.map((b) {
        if (b.name == _paymentMethod) {
          return b.copyWith(currentBalance: newBalance);
        }
        return b;
      }).toList();
      _payments = _payments!.copyWith(bankAccounts: updated);
      await _settings.savePayments(_payments!);
    }

    // 立替精算：もらう現金を指定ウォレットに加算する。
    // 支出は全額のまま計上済み。受け取りは振替扱いでPLには載せない。
    if (_treatSplit && _payments != null) {
      final receive = amount - (parseAmount(_myShareCtrl.text) ?? 0);
      final wallet = _splitReceiveWallet;
      if (receive > 0 && wallet != null) {
        // 監査用に振替取引を作成（受け取り先 +receive・PL非計上）。
        // transferFromAccount は実口座でないラベルにして、口座台帳で
        // 引かれないようにする（外部からの立替回収のため）。
        final settle = core.Transaction(
          id: '${DateTime.now().microsecondsSinceEpoch}s',
          date: _date,
          type: core.TransactionType.transfer,
          category: const core.Category(major: '振替', sub: ''),
          paymentMethod: '',
          description: '立替精算（現金回収）: ${_descCtrl.text.trim()}',
          amount: receive,
          transferFromAccount: '立替精算',
          transferToAccount: wallet,
          memo: '立替分の現金受け取り（支出「${_descCtrl.text.trim()}」に紐づく）',
        );
        await TransactionRepository.instance.add(settle);
        // 受け取りウォレットの現在残高を加算（クイック表示の整合）。
        final updated = _payments!.bankAccounts.map((b) {
          if (b.name == wallet) {
            return b.copyWith(
                currentBalance: (b.displayBalance ?? 0) + receive);
          }
          return b;
        }).toList();
        _payments = _payments!.copyWith(bankAccounts: updated);
        await _settings.savePayments(_payments!);
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
              // 取引内容を一番上に（要望：先に内容を書くのが入力しやすい）。
              _label('取引内容'),
              TextFormField(
                controller: _descCtrl,
                focusNode: _descFocus,
                decoration: _inputDecoration(),
                onChanged: (_) {
                  // 変換中（IME composing中）は setState で再描画しない。
                  // Windowsデスクトップで「変換しようとスペースを押すとカーソルが
                  // 先頭へ飛ぶ」フレームワーク不具合を誘発しないため、予測と
                  // サジェスト更新は変換が確定してから走らせる。
                  if (_descCtrl.value.composing.isValid) return;
                  setState(() {
                    if (!_categoryTouched) _autoPredictCategory();
                  });
                },
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '入力してください' : null,
              ),
              // 過去の取引内容からサジェスト（フォーカス中だけ表示）。
              if (_descFocus.hasFocus) _descSuggestionList(),
              const SizedBox(height: 16),
              // 場所（必須）。店舗名や購入元。明細タブの「場所」列に出る。
              _label('場所（必須）'),
              TextFormField(
                controller: _storeCtrl,
                decoration: _inputDecoration(hint: '例: ファミリーマート / Amazon'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '場所を入力してください' : null,
              ),
              const SizedBox(height: 16),
              // 金額をヒーローとして大きく表示。
              _heroAmount(),
              const SizedBox(height: 14),
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
              // PC でもサッと入れられるよう：前後日の矢印＋日付ボタン（タップで
              // カレンダー）＋「今日/昨日/一昨日」ワンタップチップ。
              Row(
                children: [
                  _dayArrowButton(Icons.chevron_left, () => _shiftDate(-1)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
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
                  ),
                  const SizedBox(width: 6),
                  _dayArrowButton(Icons.chevron_right, () => _shiftDate(1)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _quickDateChip('今日', 0),
                  const SizedBox(width: 8),
                  _quickDateChip('昨日', 1),
                  const SizedBox(width: 8),
                  _quickDateChip('一昨日', 2),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: _label('大カテゴリ')),
                  InkWell(
                    onTap: _openCategoryEditor,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, size: 14, color: Color(0xFF1A237E)),
                          SizedBox(width: 3),
                          Text('カテゴリ編集',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A237E))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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

              // 支払方法（金額・カテゴリの次に配置）。
              ..._paymentMethodSection(
                  paymentMethods, hasBalanceTracking, isCard),
              const SizedBox(height: 16),

              // 立替精算。一括で払って他人から現金を受け取るケース。
              if (widget.editing == null) ...[
                _treatSplitSection(payments),
                const SizedBox(height: 16),
              ],

              // 備考はデフォルト表示。
              _label('備考（任意）'),
              TextFormField(
                controller: _memoCtrl,
                maxLines: 2,
                decoration: _inputDecoration(),
              ),
              const SizedBox(height: 18),

              // 領収書（事業モードのみ・税理士提出用）。
              // リンクを貼る／レシート画像を直接保存、どちらでも選べる。
              if (AppModeManager.instance.current == AppMode.business) ...[
                _label('領収書（任意・税理士提出用）'),
                TextFormField(
                  controller: _receiptUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration:
                      _inputDecoration(hint: 'リンクを貼り付け（Drive 等）'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_saving || _savingReceipt)
                            ? null
                            : _saveReceiptImage,
                        icon: _savingReceipt
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('画像を保存'),
                        style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickFromDrive,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('Driveから選ぶ'),
                        style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                  ],
                ),
                if (_receiptUrlCtrl.text.trim().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openReceiptLink,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('領収書を開く'),
                    ),
                  ),
                const SizedBox(height: 18),
              ],

              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_saving
                    ? '保存中…'
                    : (widget.editing != null ? '更新する' : '記録する')),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
    ];
  }

  /// 立替精算セクション。
  ///
  /// 「自分が一括で支払い、他人から現金をもらう」ケース。
  /// 支出は全額を計上したまま（経費・カード請求はそのまま）、もらう現金を
  /// 指定ウォレットに加算する。受け取りは振替扱い（PL非計上）。
  Widget _treatSplitSection(core.PaymentMethodsConfig payments) {
    // 受け取り先候補＝非カードの有効ウォレット（現金/口座/電子マネー）。
    final wallets = payments.bankAccounts
        .where((b) => !b.inactive)
        .map((b) => b.name)
        .toList();
    final amount = parseAmount(_amountCtrl.text) ?? 0;
    final myShare = parseAmount(_myShareCtrl.text) ?? 0;
    final receive = amount - myShare;

    return Container(
      decoration: BoxDecoration(
        color: _treatSplit ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _treatSplit
                ? const Color(0xFF86EFAC)
                : const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.volunteer_activism_outlined,
                  size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('立替精算',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
              ),
              Switch(
                value: _treatSplit,
                activeTrackColor: const Color(0xFF059669),
                onChanged: (v) {
                  setState(() {
                    _treatSplit = v;
                    if (v && _splitReceiveWallet == null) {
                      // 既定の受け取り先：現金口座 → 無ければ先頭。
                      final cash = payments.bankAccounts.firstWhere(
                        (b) =>
                            !b.inactive &&
                            b.accountType == core.AccountType.cash,
                        orElse: () => payments.bankAccounts.firstWhere(
                          (b) => !b.inactive,
                          orElse: () => payments.bankAccounts.isNotEmpty
                              ? payments.bankAccounts.first
                              : (throw StateError('no wallet'))),
                      );
                      _splitReceiveWallet = cash.name;
                    }
                  });
                },
              ),
            ],
          ),
          if (_treatSplit) ...[
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                '一括で支払い、他人から現金をもらうとき。経費は全額のまま、'
                'もらう現金を財布（指定ウォレット）に加算します。',
                style: TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
              ),
            ),
            _label('自分の負担額（円）'),
            TextFormField(
              controller: _myShareCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                HalfWidthDigitsFormatter(),
                ThousandsSeparatorInputFormatter(),
              ],
              decoration: _inputDecoration(hint: '例: 4000').copyWith(
                prefixIcon: const Icon(Icons.person_outline, size: 18),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            // もらう現金（自動計算）。
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: Color(0xFF059669)),
                  const SizedBox(width: 8),
                  const Text('もらう現金',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                  const Spacer(),
                  Text(
                    receive > 0 ? '+${formatYen(receive)}' : '—',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: receive > 0
                            ? const Color(0xFF059669)
                            : const Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
            if (receive < 0)
              const Padding(
                padding: EdgeInsets.only(left: 2, top: 4),
                child: Text('自分の負担が金額を超えています。',
                    style:
                        TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
              ),
            const SizedBox(height: 10),
            _label('受け取り先（現金が増えるウォレット）'),
            if (wallets.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '現金/口座が未登録です。設定で登録してください。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: wallets.contains(_splitReceiveWallet)
                    ? _splitReceiveWallet
                    : null,
                items: wallets
                    .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                    .toList(),
                onChanged: (v) => setState(() => _splitReceiveWallet = v),
                decoration: _inputDecoration(hint: '選択してください'),
              ),
          ],
        ],
      ),
    );
  }

  /// 金額入力（ヒーロー）。画面上部に大きく表示。USD 切替もここで行う。
  Widget _heroAmount() {
    final isUsd = _currency == 'USD';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
              HalfWidthDigitsFormatter(),
              ThousandsSeparatorInputFormatter(),
            ],
            decoration: _inputDecoration().copyWith(
              prefixText: '¥ ',
              prefixStyle: const TextStyle(
                  fontSize: 20, color: Color(0xFF9CA3AF)),
            ),
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 26,
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

  /// Drive に保存済みの領収書（この取引の月フォルダ）から選んで紐付ける。
  Future<void> _pickFromDrive() async {
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final url = await showDriveReceiptPicker(context,
        date: _date, isBusiness: isBusiness);
    if (url == null || !mounted) return;
    setState(() => _receiptUrlCtrl.text = url);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('領収書を紐付けました')));
  }

  /// レシート画像を直接保存（カメラ/ギャラリー → Drive アップロード → URL をセット）。
  Future<void> _saveReceiptImage() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const ReceiptCameraScreen()),
    );
    if (bytes == null || !mounted) return;
    setState(() => _savingReceipt = true);
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final url = await DriveReceiptService.instance.uploadReceiptImage(
        bytes: bytes, date: _date, isBusiness: isBusiness);
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      setState(() => _savingReceipt = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'レシートの保存に失敗しました: ${DriveReceiptService.instance.lastError ?? ''}')));
      return;
    }
    setState(() {
      _receiptUrlCtrl.text = url;
      _savingReceipt = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レシートを保存しました')));
  }

  /// 領収書を開く。Driveのファイルならアプリ内ビューアで表示（ブラウザ不要）。
  Future<void> _openReceiptLink() async {
    final url = _receiptUrlCtrl.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レシートのリンクがありません')),
      );
      return;
    }
    // Driveの閲覧リンクを外部で開く（自前ビューアはアカウント違い等で404に
    // なりやすいので、ログイン済みのDriveセッションに任せる）。
    final fileId = DriveReceiptService.fileIdFromUrl(url);
    final open = fileId != null
        ? 'https://drive.google.com/file/d/$fileId/view'
        : url;
    final uri = Uri.tryParse(open);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }


  /// 日付を前後にずらす矢印ボタン（日付欄の左右）。
  Widget _dayArrowButton(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 44,
            height: 48,
            alignment: Alignment.center,
            decoration: _fieldDecoration(),
            child: Icon(icon, size: 22, color: const Color(0xFF6B7280)),
          ),
        ),
      );

  /// 「今日/昨日/一昨日」ワンタップチップ。該当日は色付きで強調。
  Widget _quickDateChip(String label, int daysAgo) {
    final selected = _dateIsDaysAgo(daysAgo);
    return InkWell(
      onTap: () => _setDateDaysAgo(daysAgo),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? const Color(0xFF1A237E)
                  : const Color(0xFFE5E7EB),
              width: selected ? 1.4 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF6B7280))),
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
