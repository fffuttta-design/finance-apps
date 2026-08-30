import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'receipt_image_screen.dart';

/// 収支を1件記録／編集する画面（水色・シンプル）。
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
  String? _payment; // 支払元（設定の支払方法：既定はクレカ／現金）
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _saving = false;

  // ── くわしい情報（画像）─────────────────────────────────
  String? _receiptId; // この記録に紐づく画像の参照ID
  String? _receiptUrl; // Drive保存済みの閲覧URL（裏で付く）
  Uint8List? _attachPreview; // 今この画面で選んだ画像（即プレビュー用）
  bool _uploadingImage = false; // 裏のDrive保存中フラグ
  /// 進行中のアップロード。保存ボタンはこれを待ってからURLを書き込む
  /// （待たずに保存すると画像がどの記録にも紐づかず迷子になる）。
  Future<String?>? _uploadTask;
  String? _uploadError; // 直近のアップロード失敗理由（nullなら失敗なし）

  /// 手入力で付けた「くわしい情報」画像かどうか（receiptId の印で判定）。
  bool get _isDetailImage => (_receiptId ?? '').startsWith('detail_');

  bool get _isIncome => _type == core.TransactionType.income;

  /// 添付画像の呼び名。収入は給与明細を貼ることが多いので言い方を変える。
  String get _imageLabel => _isIncome ? '給与明細など（画像）' : 'くわしい情報（画像）';

  /// レシートの品目メモ（まとめて1件にぶら下がる内訳）。新規=initialMemo、編集=既存メモ。
  String? get _receiptMemo => widget.initialMemo ?? widget.editing?.memo;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _type = e.type == core.TransactionType.income
          ? core.TransactionType.income
          : core.TransactionType.expense;
      _date = e.date;
      _category = e.category.major;
      _amountCtrl.text = e.amount.toString();
      _memoCtrl.text = e.description;
      _payment = e.paymentMethod.isEmpty ? null : e.paymentMethod;
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
      // 支払元は既定を持たず、本人が登録した口座から選んでもらう。
      _payment = null;
      _receiptId = widget.initialReceiptId;
      _receiptUrl = widget.initialReceiptUrl ??
          (widget.initialReceiptId != null
              ? DriveReceiptService.instance.urlFor(widget.initialReceiptId!)
              : null);
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
    if (_payment == null || _payment!.isEmpty) {
      _toast('支払い方法を選んでね');
      return;
    }
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) {
      _toast('読み込み中です');
      return;
    }
    setState(() => _saving = true);
    // 画像の保存が終わるのを待つ。ここを待たずに保存すると、あとから付く
    // URLがどの記録にも紐づかず「添付したのに見られない」状態になる。
    if (!await _waitForImageUpload()) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final tx = core.Transaction(
      id: widget.editing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      type: _type,
      category: core.Category(major: _category!, sub: ''),
      paymentMethod: _payment ?? '',
      description: _memoCtrl.text.trim(),
      amount: amount,
      // 備考（レシートの品目リスト等）。編集時は既存を維持。
      memo: widget.editing?.memo ?? widget.initialMemo,
      // レシート/くわしい情報の画像参照。
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

  /// 「くわしい情報」画像を添付する（ギャラリー優先・カメラは右のボタン）。
  Future<void> _attachDetailImage(
      {ImageSource source = ImageSource.gallery}) async {
    final XFile? x;
    try {
      x = await ImagePicker().pickImage(
          source: source, imageQuality: 85, maxWidth: 2200);
    } catch (_) {
      if (mounted) _toast('画像を取得できませんでした');
      return;
    }
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();

    final imgBytes = await _compressImage(bytes);
    if (!mounted) return;

    final receiptId = 'detail_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _receiptId = receiptId;
      _receiptUrl = null;
      _attachPreview = imgBytes;
      _uploadingImage = true;
      _uploadError = null;
    });
    _startUpload(receiptId, imgBytes);
  }

  /// 画像をドライブへ保存する処理を開始し、その Future を保持する。
  /// （保存ボタンはこの Future を待ってから記録を書き込む）
  void _startUpload(String receiptId, Uint8List imgBytes) {
    final hid = HouseholdService.instance.householdId;
    final task = () async {
      final url = await DriveReceiptService.instance
          .uploadReceiptImage(bytes: imgBytes, date: _date);
      if (url != null) {
        DriveReceiptService.instance.rememberUrl(receiptId, url);
        if (hid != null) {
          try {
            await TxRepository.instance.attachReceiptUrl(hid, receiptId, url);
          } catch (_) {/* 後付け失敗は無視 */}
        }
      }
      if (mounted) {
        setState(() {
          if (url != null) _receiptUrl = url;
          _uploadError =
              url == null ? (DriveReceiptService.instance.lastError ?? '') : null;
          _uploadingImage = false;
        });
      }
      return url;
    }();
    _uploadTask = task;
    unawaited(task);
  }

  /// 画像の保存待ち。保存してよければ true、やめるなら false を返す。
  /// 失敗したときは理由を見せて「もう一度」か「画像なしで保存」を選んでもらう。
  Future<bool> _waitForImageUpload() async {
    final task = _uploadTask;
    if (task == null || (_receiptUrl ?? '').isNotEmpty) return true;
    final url = await task;
    if (url != null) {
      _receiptUrl = url;
      return true;
    }
    if (!mounted) return false;
    final retry = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('画像を保存できませんでした'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ドライブへの保存に失敗しました。'
              'もう一度ためすか、画像なしで記録できます。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            if ((_uploadError ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_uploadError!,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSub, height: 1.4)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('画像なしで保存')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('もう一度ためす')),
        ],
      ),
    );
    if (retry == true) {
      final bytes = _attachPreview;
      final rid = _receiptId;
      if (bytes != null && rid != null) {
        setState(() {
          _uploadingImage = true;
          _uploadError = null;
        });
        _startUpload(rid, bytes);
        return _waitForImageUpload();
      }
      return false;
    }
    if (retry == null) return false; // ダイアログを閉じただけ＝保存もやめる
    // 画像なしで保存：迷子の参照を残さないよう画像の紐づけを外す。
    setState(() {
      _receiptId = null;
      _receiptUrl = null;
      _attachPreview = null;
      _uploadTask = null;
      _uploadError = null;
    });
    return true;
  }

  void _removeDetailImage() {
    setState(() {
      _receiptId = null;
      _receiptUrl = null;
      _attachPreview = null;
      _uploadingImage = false;
      _uploadTask = null;
      _uploadError = null;
    });
  }

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
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return;
    setState(() => _saving = true);
    await TxRepository.instance.delete(hid, e.id, uid);
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
            // 支出/収入トグル（新規記録時のみ）
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
            // なにを買った？
            _section('なにを買った？'),
            TextField(
              controller: _memoCtrl,
              decoration:
                  const InputDecoration(hintText: '例: たまご・牛乳 / ランチ'),
            ),
            // レシートの品目（メモ）プレビュー。
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
            // 支払元
            _section('支払元'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _paymentOptions()) _payChip(m, m),
              ],
            ),
            const SizedBox(height: 18),
            // くわしい情報（画像）／収入なら給与明細
            _section(_imageLabel),
            _detailImageSection(),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: Text(_saving
                  ? '保存中…'
                  : (widget.editing != null ? '更新する' : 'きろくする')),
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

  /// 支払元の選択肢。設定の支払方法（既定「クレカ」「現金」）を並べる。
  /// 昔の記録が今は無い支払元（口座名など）で保存されていたら、その値も
  /// 末尾に足して選択が外れないようにする。
  List<String> _paymentOptions() {
    final list = List<String>.of(HouseholdService.instance.paymentMethods);
    final cur = _payment;
    if (cur != null && cur.isNotEmpty && !list.contains(cur)) list.add(cur);
    return list;
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

  /// 「くわしい情報（画像）」セクション。
  Widget _detailImageSection() {
    final hasImage =
        _attachPreview != null || (_receiptUrl != null && _receiptUrl!.isNotEmpty);

    if (!hasImage) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () =>
                  _attachDetailImage(source: ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('アルバムから選ぶ'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.pinkDark,
                side: const BorderSide(color: AppColors.pinkSoft, width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _attachDetailImage(source: ImageSource.camera),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.pinkDark,
              side: const BorderSide(color: AppColors.pinkSoft, width: 1.4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: const Icon(Icons.photo_camera_outlined, size: 20),
          ),
        ],
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
                    ] else if (_uploadError != null)
                      const Expanded(
                        child: Text('保存できませんでした（記録すると出し直せます）',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.expense)),
                      )
                    else
                      const Text('画像を保存しました',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (_attachPreview == null &&
                        _receiptUrl != null &&
                        _receiptUrl!.isNotEmpty) ...[
                      _smallTextButton(
                          !_isDetailImage
                              ? 'レシートを見る'
                              : (_isIncome ? '明細を見る' : 'くわしい情報を見る'),
                          Icons.visibility_outlined, _viewDetailImage),
                      const SizedBox(width: 4),
                    ],
                    _smallTextButton('変更', Icons.swap_horiz_rounded,
                        () => _attachDetailImage()),
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
