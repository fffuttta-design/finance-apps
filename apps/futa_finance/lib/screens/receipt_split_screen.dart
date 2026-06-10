import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/drive_receipt_service.dart';
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
  /// 初期品目（レシートOCR由来）。手入力モードでは空でよい。
  final List<ReceiptItem> items;
  final DateTime? date;
  final String? storeName;

  /// 手入力モード（レシート無しで、自分で品目行を足して明細を分ける）。
  /// タイトルや初期行（空1行）などが変わる。
  final bool manual;

  /// 上部に「まとめて1件 / 品目ごと」トグルを表示するか（OCRフローから true）。
  /// 「まとめて1件」を選ぶと [kReceiptSwitchMode] を返して閉じる。
  final bool showModeToggle;

  /// OCRが推定した会計科目（大カテゴリ名）。共通大カテゴリの初期値に使う。
  final String? initialCategoryMajor;

  /// OCRが推定した小カテゴリ名。
  final String? initialCategorySub;

  const ReceiptSplitScreen({
    super.key,
    this.items = const [],
    this.date,
    this.storeName,
    this.showModeToggle = false,
    this.initialCategoryMajor,
    this.initialCategorySub,
    this.receiptId,
    this.receiptUrl,
    this.manual = false,
  });

  /// 親レシートのグループID（全品目に同じIDを付与）。任意。
  final String? receiptId;

  /// Drive保存したレシート画像の閲覧リンク（全品目に付与）。任意。
  final String? receiptUrl;

  @override
  State<ReceiptSplitScreen> createState() => _ReceiptSplitScreenState();
}

class _Row {
  bool include;
  final TextEditingController name;
  final TextEditingController amount;

  /// 個数・単価（OCR由来。表示用）。
  final int? quantity;
  final int? unitPrice;

  /// 品目ごとのカテゴリ上書き（null なら共通カテゴリを継承）。
  String? catMajor;
  String? catSub;

  _Row(this.include, this.name, this.amount, this.quantity, this.unitPrice);

  bool get hasOverride => catMajor != null && catSub != null;

  /// 「¥単価 × 個数」表記（個数2以上かつ単価ありのとき）。
  String? get unitBreakdown =>
      (unitPrice != null && quantity != null && quantity! > 1)
          ? '¥$unitPrice × $quantity'
          : null;
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

  late final TextEditingController _storeCtrl =
      TextEditingController(text: widget.storeName ?? '');

  late final List<_Row> _rows = widget.items.isEmpty
      // 手入力モード等で品目が無いときは、空の1行から始める。
      ? [_emptyRow()]
      : widget.items
          .map((it) => _Row(
              true,
              TextEditingController(text: it.name),
              NoComposingUnderlineController(text: formatAmount(it.price)),
              it.quantity,
              it.unitPrice))
          .toList();

  /// 空の品目行（手入力で追加するとき用）。金額欄は変換中下線を出さない。
  _Row _emptyRow() => _Row(
      true, TextEditingController(), NoComposingUnderlineController(), null, null);

  /// 品目行を1つ追加。
  void _addRow() => setState(() => _rows.add(_emptyRow()));

  /// 品目行を削除（最後の1行はクリアのみ）。
  void _removeRow(_Row r) {
    if (_rows.length <= 1) {
      setState(() {
        r.name.clear();
        r.amount.clear();
        r.include = true;
        r.catMajor = null;
        r.catSub = null;
      });
      return;
    }
    setState(() => _rows.remove(r));
    r.name.dispose();
    r.amount.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
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
      // OCRの科目候補があれば共通大カテゴリに自動セット。
      _applyCategoryGuess();
    });
  }

  /// OCR推定カテゴリを共通大/小カテゴリに反映。
  void _applyCategoryGuess() {
    final guess = widget.initialCategoryMajor?.trim();
    if (guess == null || guess.isEmpty || _major != null) return;
    String norm(String s) =>
        s.replaceFirst(RegExp(r'^\d+\.'), '').trim();
    for (final name in _majorNames) {
      if (name == guess || norm(name) == norm(guess)) {
        _major = name;
        final subs = _subsForMajor(name);
        final guessSub = widget.initialCategorySub?.trim();
        if (guessSub != null && subs.contains(guessSub)) {
          _sub = guessSub;
        } else if (subs.isNotEmpty) {
          _sub = subs.first;
        }
        break;
      }
    }
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

  List<String> get _subNames => _subsForMajor(_major);

  /// 指定した大カテゴリ表示名に属する小カテゴリ一覧。
  List<String> _subsForMajor(String? major) {
    final c = _categories;
    if (c == null || major == null) return const [];
    final idx = c.majors
        .indexWhere((m) => m.displayName(c.majors.indexOf(m)) == major);
    if (idx < 0) return const [];
    return c.majors[idx].subs;
  }

  /// 行の実効カテゴリ（上書きがあればそれ、無ければ共通）。
  String? _effMajor(_Row r) => r.catMajor ?? _major;
  String? _effSub(_Row r) => r.catSub ?? _sub;

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
    if (_paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('支払方法を選んでください')),
      );
      return;
    }
    final store = _storeCtrl.text.trim();
    final toSave = <core.Transaction>[];
    for (final r in _rows) {
      if (!r.include) continue;
      final amt = parseAmount(r.amount.text);
      if (amt == null || amt <= 0) continue;
      final major = _effMajor(r);
      final sub = _effSub(r);
      // 共通も上書きも未設定の品目があればエラー（どのカテゴリか確定できない）。
      if (major == null || sub == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('カテゴリ未設定の品目があります（共通カテゴリを選ぶか各品目で設定）')),
        );
        return;
      }
      final name = r.name.text.trim();
      toSave.add(core.Transaction(
        id: '${DateTime.now().microsecondsSinceEpoch}-${toSave.length}',
        date: _date,
        type: core.TransactionType.expense,
        category: core.Category(major: major, sub: sub),
        paymentMethod: _paymentMethod!,
        description: name.isEmpty ? (store.isEmpty ? '品目' : store) : name,
        amount: amt,
        store: store.isEmpty ? null : store,
        // 同じレシートの品目は同じ receiptId で束ね、receiptUrl で画像を開ける。
        // 裏のDrive保存が先に終わっていればキャッシュURLを付与。
        receiptId: widget.receiptId,
        receiptUrl: widget.receiptUrl ??
            (widget.receiptId != null
                ? DriveReceiptService.instance.urlFor(widget.receiptId!)
                : null),
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
        title: Text(widget.manual ? '明細を分けて記録' : '品目ごとに記録',
            style: const TextStyle(
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
                        if (widget.showModeToggle) ...[
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.receipt_long, size: 16),
                                  label: Text('まとめて1件',
                                      style: TextStyle(fontSize: 12))),
                              ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.list_alt, size: 16),
                                  label: Text('品目ごと',
                                      style: TextStyle(fontSize: 12))),
                            ],
                            selected: const {true},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) {
                              if (s.first == false) {
                                Navigator.pop(context, kReceiptSwitchMode);
                              }
                            },
                            style: const ButtonStyle(
                                visualDensity: VisualDensity.compact),
                          ),
                          const SizedBox(height: 16),
                        ],
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
                        _label('店舗（共通）'),
                        TextField(
                          controller: _storeCtrl,
                          decoration: _dec('例: ファミリーマート')
                              .copyWith(
                            prefixIcon: const Icon(Icons.storefront_outlined,
                                size: 18),
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
                                    value: m, child: Text(_bareName(m))))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _paymentMethod = v),
                            decoration: _dec('選択してください'),
                          ),
                        const SizedBox(height: 12),
                        _label('大カテゴリ（共通・各品目の初期値）'),
                        DropdownButtonFormField<String>(
                          key: ValueKey('maj-${_major ?? ''}'),
                          initialValue:
                              _majorNames.contains(_major) ? _major : null,
                          items: _majorNames
                              .map((m) => DropdownMenuItem(
                                  value: m, child: Text(_bareName(m))))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _major = v;
                            _sub = null;
                          }),
                          decoration: _dec('選択してください'),
                        ),
                        const SizedBox(height: 12),
                        _label('小カテゴリ（共通・各品目の初期値）'),
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
                        // 合計を大きく目立たせる。
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('合計',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF6B7280))),
                                  Text('$_includedCount件',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9CA3AF))),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                formatYen(_includedTotal),
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFDC2626),
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _label('品目'),
                        for (final r in _rows) _itemRow(r),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _addRow,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('品目を追加'),
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1A237E)),
                          ),
                        ),
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
    final dim = !r.include;
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Row(
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
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '品名'),
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
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close,
                      size: 16, color: Color(0xFF9CA3AF)),
                  onPressed: () => _removeRow(r),
                  tooltip: '品目を削除',
                ),
              ],
            ),
            // カテゴリ行（共通継承 or 品目別上書き）＋単価×個数。
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 2),
              child: Row(
                children: [
                  Expanded(child: _itemCategoryChip(r)),
                  if (r.unitBreakdown != null) ...[
                    Text(r.unitBreakdown!,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            fontFamily: 'monospace')),
                    const SizedBox(width: 8),
                  ],
                  if (r.hasOverride)
                    InkWell(
                      onTap: () => setState(() {
                        r.catMajor = null;
                        r.catSub = null;
                      }),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text('共通に戻す',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFF1A237E))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 品目のカテゴリチップ（タップで上書き編集）。
  /// 未上書きは控えめな鉛筆アイコンのみ（共通を継承していることが前提）。
  /// 上書き済みのときだけ、設定したカテゴリを淡色チップで表示する。
  Widget _itemCategoryChip(_Row r) {
    if (!r.hasOverride) {
      // 初期表示は鉛筆アイコンだけ（個別設定できることが分かればよい）。
      return InkWell(
        onTap: () => _editItemCategory(r),
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Icon(Icons.edit_outlined,
              size: 14, color: Color(0xFFC4C8CF)),
        ),
      );
    }
    return InkWell(
      onTap: () => _editItemCategory(r),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell, size: 12, color: Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${_bareName(r.catMajor!)} › ${r.catSub}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.edit, size: 11, color: Color(0xFF9CA3AF)),
        ],
      ),
    );
  }

  /// 品目ごとのカテゴリ上書きを選ぶ（大→小）。共通に戻す選択肢付き。
  Future<void> _editItemCategory(_Row r) async {
    String? tmpMajor = r.catMajor ?? _major;
    String? tmpSub = r.catSub ?? _sub;
    final result = await showModalBottomSheet<List<String?>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final subs = _subsForMajor(tmpMajor);
          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('「${r.name.text.trim()}」のカテゴリ',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      _majorNames.contains(tmpMajor) ? tmpMajor : null,
                  isExpanded: true,
                  items: _majorNames
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(_bareName(m))))
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    tmpMajor = v;
                    tmpSub = null;
                  }),
                  decoration: _dec('大カテゴリ'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: subs.contains(tmpSub) ? tmpSub : null,
                  isExpanded: true,
                  items: subs
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setLocal(() => tmpSub = v),
                  decoration: _dec(
                      tmpMajor == null ? '先に大カテゴリを選択' : '小カテゴリ'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(sheet, <String?>[null, null]),
                        child: const Text('共通に従う'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: (tmpMajor != null && tmpSub != null)
                            ? () => Navigator.pop(
                                sheet, <String?>[tmpMajor, tmpSub])
                            : null,
                        child: const Text('この品目に設定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result == null) return; // キャンセル
    setState(() {
      r.catMajor = result[0];
      r.catSub = result[1];
    });
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

  /// 表示用に先頭の自動番号（"0." など）を取り除く。保存値は番号付きのまま。
  String _bareName(String s) =>
      s.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();

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
