import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/account.dart';
import '../data/account_repository.dart';
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'receipt_camera_screen.dart';
import 'receipt_image_screen.dart';

/// 収支を1件記録／編集する画面（可愛い系）。
class AddTransactionScreen extends StatefulWidget {
  /// 編集対象（null なら新規）。
  final core.Transaction? editing;

  /// 新規時の初期種別（支出/収入タブのFABから指定）。editing 時は無視。
  final core.TransactionType? initialType;

  /// レシート読み取り等からの初期値（新規時のみ）。
  final int? initialAmount;
  final DateTime? initialDate;
  final String? initialCategory;
  final String? initialDescription;

  /// レシート画像をDrive保存したときの参照（新規時のみ）。
  final String? initialReceiptId;
  final String? initialReceiptUrl;

  /// レシートの品目リストなどの備考（メモ）。新規時のみ。
  /// まとめて1件記録のとき、品目を「・品名 ¥金額」でこの記録にぶら下げる。
  final String? initialMemo;

  const AddTransactionScreen({
    super.key,
    this.editing,
    this.initialType,
    this.initialAmount,
    this.initialDate,
    this.initialCategory,
    this.initialDescription,
    this.initialReceiptId,
    this.initialReceiptUrl,
    this.initialMemo,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  late core.TransactionType _type;
  late DateTime _date;
  String? _category;
  String? _paidBy; // だれが払ったか（uid）
  String? _payment; // 支払元（登録した口座/クレカの名前）
  List<Account> _accounts = []; // 登録済みの口座/クレカ
  bool _personalFood = false; // この食費を個人わく（だれの分）から引くか
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _saving = false;

  // ── くわしい情報（画像）─────────────────────────────────
  // 手入力でも、レシートと同じ仕組み（Drive保存＋receiptId/receiptUrl）で
  // 1枚の画像をぶら下げられる。手入力で付けた画像は receiptId を "detail_" で
  // 始める印にして、表示側のボタン名を「くわしい情報を見る」に出し分ける。
  String? _receiptId; // この記録に紐づく画像の参照ID
  String? _receiptUrl; // Drive保存済みの閲覧URL（裏で付く）
  Uint8List? _attachPreview; // 今この画面で選んだ画像（即プレビュー用）
  bool _uploadingImage = false; // 裏のDrive保存中フラグ

  /// 手入力で付けた「くわしい情報」画像かどうか（receiptId の印で判定）。
  bool get _isDetailImage => (_receiptId ?? '').startsWith('detail_');

  bool get _isIncome => _type == core.TransactionType.income;

  /// 新規記録の既定の支払元。
  static const _defaultPayment = 'ワンバンク';

  /// 個人食費わくの対象にできるカテゴリ（今は「食費」だけ）。
  static const _personalFoodCategory = '食費';
  bool get _canPersonalFood => !_isIncome && _category == _personalFoodCategory;

  /// レシートの品目メモ（まとめて1件にぶら下がる内訳）。新規=initialMemo、編集=既存メモ。
  String? get _receiptMemo => widget.initialMemo ?? widget.editing?.memo;


  @override
  void initState() {
    super.initState();
    final myUid = AuthService.instance.currentUser?.uid;
    final e = widget.editing;
    if (e != null) {
      _type = e.type == core.TransactionType.income
          ? core.TransactionType.income
          : core.TransactionType.expense;
      _date = e.date;
      _category = e.category.major;
      _amountCtrl.text = e.amount.toString();
      _memoCtrl.text = e.description;
      _paidBy = e.paidBy ?? e.recordedBy ?? myUid;
      _payment = e.paymentMethod.isEmpty ? null : e.paymentMethod;
      _personalFood = e.personalFor != null;
      _receiptId = e.receiptId;
      _receiptUrl = e.receiptUrl;
    } else {
      _type = widget.initialType ?? core.TransactionType.expense;
      _date = widget.initialDate ?? DateTime.now();
      _category = widget.initialCategory;
      if (widget.initialAmount != null && widget.initialAmount! > 0) {
        _amountCtrl.text = widget.initialAmount.toString();
      }
      if (widget.initialDescription != null &&
          widget.initialDescription!.isNotEmpty) {
        _memoCtrl.text = widget.initialDescription!;
      }
      _paidBy = myUid;
      // 新規記録の支払元は「ワンバンク」を既定にする。
      _payment = _defaultPayment;
      // レシート読み取りから来た場合の画像参照を引き継ぐ。
      _receiptId = widget.initialReceiptId;
      _receiptUrl = widget.initialReceiptUrl ??
          (widget.initialReceiptId != null
              ? DriveReceiptService.instance.urlFor(widget.initialReceiptId!)
              : null);
    }
    // 登録済みの口座/クレカを読み込む（支払元の選択肢）。
    final hid = HouseholdService.instance.householdId;
    if (hid != null) {
      AccountRepository.instance.loadAll(hid).then((a) {
        if (mounted) setState(() => _accounts = a);
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  List<TxCategory> get _cats {
    final base = _isIncome ? incomeCategories : expenseCategories;
    final custom = HouseholdService.instance.customCats(income: _isIncome);
    return [
      ...base,
      for (final n in custom) categoryFor(n, income: _isIncome),
    ];
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.pink),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = parseYen(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _toast('金額を入力してね');
      return;
    }
    if (_category == null) {
      _toast('カテゴリを選んでね');
      return;
    }
    // 支払い方法がないまま登録させない。
    if (_payment == null || _payment!.isEmpty) {
      _toast('支払い方法を選んでね');
      return;
    }
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) {
      _toast('世帯情報の読み込み中です');
      return;
    }
    setState(() => _saving = true);
    final tx = core.Transaction(
      id: widget.editing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      type: _type,
      category: core.Category(major: _category!, sub: ''),
      paymentMethod: _payment ?? '',
      description: _memoCtrl.text.trim(),
      amount: amount,
      paidBy: _paidBy,
      // 備考（レシートの品目リスト等）。編集時は既存を維持。
      memo: widget.editing?.memo ?? widget.initialMemo,
      // 「食費」で個人わくONのときだけ、だれの個人わくから引くか記録。
      personalFor: (_canPersonalFood && _personalFood) ? _paidBy : null,
      // レシート/くわしい情報の画像参照。手入力で添付した画像もここに乗る。
      // 裏のDrive保存が先に終わっていればキャッシュURLを付与。
      receiptId: _receiptId,
      receiptUrl: _receiptUrl ??
          (_receiptId != null
              ? DriveReceiptService.instance.urlFor(_receiptId!)
              : null),
    );
    try {
      if (widget.editing != null) {
        await TxRepository.instance.update(hid, tx, uid);
      } else {
        await TxRepository.instance.add(hid, tx, uid);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('保存に失敗しました');
      }
    }
  }

  /// 「くわしい情報」画像をカメラ/アルバムから選んで添付する。
  /// レシートと同じく Drive へは“裏で”保存し、ユーザーは待たない。
  Future<void> _attachDetailImage() async {
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const ReceiptCameraScreen(hint: 'くわしい情報を写真に撮る ♡'),
      ),
    );
    if (bytes == null || !mounted) return;

    final imgBytes = await _compressImage(bytes);
    if (!mounted) return;

    // 手入力で付けた画像の印として receiptId を "detail_" で始める。
    final receiptId = 'detail_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _receiptId = receiptId;
      _receiptUrl = null;
      _attachPreview = imgBytes;
      _uploadingImage = true;
    });

    // 裏でDrive保存。完了したら URL をキャッシュ＋（保存済みなら）後付けする。
    final hid = HouseholdService.instance.householdId;
    unawaited(() async {
      final url = await DriveReceiptService.instance
          .uploadReceiptImage(bytes: imgBytes, date: _date);
      if (url != null) {
        DriveReceiptService.instance.rememberUrl(receiptId, url);
        if (hid != null) {
          try {
            await TxRepository.instance.attachReceiptUrl(hid, receiptId, url);
          } catch (_) {/* 後付け失敗は無視（リンクが付かないだけ） */}
        }
      }
      if (mounted) {
        setState(() {
          if (url != null) _receiptUrl = url;
          _uploadingImage = false;
        });
      }
    }());
  }

  void _removeDetailImage() {
    setState(() {
      _receiptId = null;
      _receiptUrl = null;
      _attachPreview = null;
      _uploadingImage = false;
    });
  }

  /// 既に保存済みの画像をアプリ内ビューアで開く。
  void _viewDetailImage() {
    final raw = _receiptUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final fileId = DriveReceiptService.fileIdFromUrl(raw);
    if (fileId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReceiptImageScreen(fileId: fileId)),
    );
  }

  /// 画像を軽く圧縮（保存・表示を速くする）。失敗時は元画像のまま。
  Future<Uint8List> _compressImage(Uint8List src) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        src,
        quality: 70,
        minWidth: 1080,
        minHeight: 1920,
        format: CompressFormat.jpeg,
      );
      if (out.isNotEmpty && out.length < src.length) {
        return Uint8List.fromList(out);
      }
    } catch (_) {/* 圧縮失敗時は元画像を使う */}
    return src;
  }

  Future<void> _delete() async {
    final e = widget.editing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('この記録を削除する？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pinkDark),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    setState(() => _saving = true);
    await TxRepository.instance.delete(hid, e.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final accent = _isIncome ? AppColors.income : AppColors.expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing != null ? '記録を編集' : 'きろくする'),
        actions: [
          if (widget.editing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.pinkDark),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            // 支出/収入トグル（新規記録時のみ。編集では種別は変えない）
            if (widget.editing == null) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.pinkSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _typeTab('支出', core.TransactionType.expense,
                        AppColors.expense),
                    _typeTab('収入', core.TransactionType.income,
                        AppColors.income),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            // 金額
            Center(
              child: Column(
                children: [
                  const Text('いくら？',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSub)),
                  const SizedBox(height: 4),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                      decoration: const InputDecoration(
                        prefixText: '¥ ',
                        prefixStyle: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSub),
                        hintText: '0',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 日付
            _section('いつ？'),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: AppColors.pinkDark),
                    const SizedBox(width: 10),
                    Text(
                        '${_date.year}年${_date.month}月${_date.day}日',
                        style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            // なにを買った？（購入物の品名＝一番大事なので日付の次に置く）
            _section('なにを買った？'),
            TextField(
              controller: _memoCtrl,
              decoration:
                  const InputDecoration(hintText: '例: たまご・牛乳 / ランチ'),
            ),
            // レシートの品目（メモ）プレビュー。まとめて1件にぶら下がる内訳。
            if (_receiptMemo != null && _receiptMemo!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pinkSoft.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long_rounded,
                            size: 15, color: AppColors.pinkDark),
                        SizedBox(width: 5),
                        Text('レシートの品目',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.pinkDark)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_receiptMemo!.trim(),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.text, height: 1.5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            // カテゴリ
            _section('カテゴリ'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._cats.map(_catChip),
                _addCatChip(),
              ],
            ),
            const SizedBox(height: 18),
            // 支払元（登録した口座/クレカから選択。残高がそこから増減する）
            _section('支払元'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_accounts.isNotEmpty)
                  ..._accounts.map((a) => _payChip(a.name, a.name))
                else
                  ...HouseholdService.instance.paymentMethods
                      .map((m) => _payChip(m, m)),
              ],
            ),
            const SizedBox(height: 18),
            // だれ（記録者／支払者。相手が登録したものでも変更できる）
            _section('だれ'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in HouseholdService.instance.memberNames.entries)
                  _personChip(e.key, e.value),
              ],
            ),
            // 個人の食費わく（カテゴリが「食費」のときだけ表示）
            if (_canPersonalFood) ...[
              const SizedBox(height: 18),
              _personalFoodToggle(),
            ],
            const SizedBox(height: 18),
            // くわしい情報（画像）。手入力でも写真を1枚ぶら下げられる。
            _section('くわしい情報（画像）'),
            _detailImageSection(),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: Text(_saving
                  ? '保存中…'
                  : (widget.editing != null ? '更新する' : 'きろくする ♡')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTab(String label, core.TransactionType type, Color color) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          _category = null; // 種別が変わるとカテゴリ候補も変わる
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: selected ? color : AppColors.textSub,
            ),
          ),
        ),
      ),
    );
  }

  Widget _catChip(TxCategory c) {
    final selected = _category == c.name;
    return GestureDetector(
      onTap: () => setState(() => _category = c.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.color.withValues(alpha: 0.22) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.color : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.icon, size: 18, color: c.color),
            const SizedBox(width: 6),
            Text(c.name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _addCatChip() {
    return GestureDetector(
      onTap: _addCustomCategory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.pink, width: 1, style: BorderStyle.solid),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: AppColors.pinkDark),
            SizedBox(width: 4),
            Text('追加',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.pinkDark)),
          ],
        ),
      ),
    );
  }

  Future<void> _addCustomCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('カテゴリを追加'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例: ペット / 車 / 推し活'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('追加')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await HouseholdService.instance
        .addCustomCategory(name, income: _isIncome);
    if (mounted) setState(() => _category = name);
  }

  Widget _payChip(String? value, String label) {
    final selected = _payment == value;
    return GestureDetector(
      onTap: () => setState(() => _payment = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.pink.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pink : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.text)),
      ),
    );
  }

  Widget _personChip(String uid, String name) {
    final selected = _paidBy == uid;
    final icon = HouseholdService.instance.memberIcons[uid];
    return GestureDetector(
      onTap: () => setState(() => _paidBy = uid),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.pink.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pink : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null && icon.isNotEmpty) ...[
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
            ],
            Text(name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  /// 「この食費を個人わくから引く」トグル。ONなら「だれ」の人の月8,000円わくから引く。
  Widget _personalFoodToggle() {
    final names = HouseholdService.instance.memberNames;
    final whoName = (_paidBy != null ? names[_paidBy] : null) ?? '本人';
    final limit = _paidBy != null
        ? HouseholdService.instance.personalFoodBudgetFor(_paidBy!)
        : HouseholdService.defaultPersonalFoodBudget;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _personalFood ? AppColors.pink.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _personalFood ? AppColors.pink : AppColors.divider,
          width: _personalFood ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lunch_dining_rounded,
              size: 20, color: AppColors.pinkDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('個人の食費わくから',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text('$whoName の月${formatYen(limit)}わくから引きます',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          Switch(
            value: _personalFood,
            activeThumbColor: AppColors.pink,
            onChanged: (v) => setState(() => _personalFood = v),
          ),
        ],
      ),
    );
  }

  /// 「くわしい情報（画像）」セクション。
  /// 画像が無ければ追加ボタン、有ればプレビュー＋変更/削除を出す。
  Widget _detailImageSection() {
    final hasImage =
        _attachPreview != null || (_receiptUrl != null && _receiptUrl!.isNotEmpty);

    if (!hasImage) {
      // まだ画像なし → カメラ/アルバムから追加ボタン。
      return OutlinedButton.icon(
        onPressed: _attachDetailImage,
        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
        label: const Text('写真を追加（カメラ / アルバム）'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.pinkDark,
          side: const BorderSide(color: AppColors.pinkSoft, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // サムネ（今選んだ画像があればそれ、無ければ保存済みをビューアで開く）。
          GestureDetector(
            onTap: _attachPreview != null ? null : _viewDetailImage,
            child: Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.pinkSoft.withValues(alpha: 0.35),
              ),
              child: _attachPreview != null
                  ? Image.memory(_attachPreview!, fit: BoxFit.cover)
                  : const Icon(Icons.image_rounded,
                      color: AppColors.pinkDark, size: 28),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_uploadingImage) ...[
                      const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.pinkDark)),
                      const SizedBox(width: 6),
                      const Text('保存中…',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ] else
                      const Text('画像を添付しました',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // 保存済み（今選んだ画像でない）ときは見るボタン。
                    if (_attachPreview == null &&
                        _receiptUrl != null &&
                        _receiptUrl!.isNotEmpty) ...[
                      _smallTextButton(
                          _isDetailImage ? 'くわしい情報を見る' : 'レシートを見る',
                          Icons.visibility_outlined, _viewDetailImage),
                      const SizedBox(width: 4),
                    ],
                    _smallTextButton(
                        '変更', Icons.swap_horiz_rounded, _attachDetailImage),
                    const SizedBox(width: 4),
                    _smallTextButton('削除', Icons.delete_outline_rounded,
                        _removeDetailImage,
                        danger: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTextButton(String label, IconData icon, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? AppColors.pinkDark : AppColors.text;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );
}
