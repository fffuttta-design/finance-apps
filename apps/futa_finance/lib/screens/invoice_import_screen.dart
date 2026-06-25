import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter/material.dart';

import '../data/app_mode.dart';
import '../data/invoice_extractor.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 請求書PDFを複数選択 → Gemini が抽出 → プレビューで確認・修正 → 一括記帳する画面。
///
/// - 売上(入金)請求書 → 収入に記帳 / 支払・外注請求書 → 支出に記帳。
/// - 種別は1件ごとに切替可能。Gemini の推定値を初期値にする。
/// - 取り込みは「現在のモード（事業/個人）」へ**追加**（既存データは消えない）。
class InvoiceImportScreen extends StatefulWidget {
  const InvoiceImportScreen({super.key});

  @override
  State<InvoiceImportScreen> createState() => _InvoiceImportScreenState();
}

/// プレビュー1行（請求書1枚）の編集状態。
class _Row {
  final String fileName;
  final Uint8List bytes;

  bool busy = true; // 解析中
  String? error; // 解析/記帳エラー
  bool excluded = false; // 記帳から除外
  bool income = false; // 種別: true=収入(売上) / false=支出(支払)

  DateTime? date;
  final amountCtrl = TextEditingController();
  final descCtrl = TextEditingController(); // 取引先 / 摘要
  String? categoryMajor; // 支出時の会計科目
  String paymentMethod = ''; // 支払/受取方法
  String? rawSummary; // Geminiの抽出要約（確認用）

  _Row({required this.fileName, required this.bytes});

  void dispose() {
    amountCtrl.dispose();
    descCtrl.dispose();
  }

  int? get amount {
    final s = amountCtrl.text.replaceAll(RegExp(r'[¥￥,円\s]'), '');
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  bool get valid =>
      !busy &&
      error == null &&
      !excluded &&
      (amount ?? 0) > 0 &&
      descCtrl.text.trim().isNotEmpty;
}

class _InvoiceImportScreenState extends State<InvoiceImportScreen> {
  final List<_Row> _rows = [];
  bool _picking = false;
  bool _importing = false;

  /// 種別の初期値（読み込み時に全行へ適用）。証憑は売上/支払フォルダ別が多いので、
  /// まとめて読み込む請求書の種別を先に決めておける。
  bool _defaultIncome = false;

  // 現在モードの選択肢。
  List<String> _expenseMajors = []; // 支出の会計科目候補
  List<String> _paymentOptions = []; // 支払/受取方法候補

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final cfg = await SettingsRepository().loadCategories();
      final majors = <String>[];
      for (var i = 0; i < cfg.majors.length; i++) {
        final m = cfg.majors[i];
        if (m.inactive) continue;
        majors.add(m.name);
      }
      final payCfg = await SettingsRepository().loadPayments();
      final pays = <String>[
        for (final b in payCfg.bankAccounts)
          if (!b.inactive) b.name,
        for (final c in payCfg.creditCards)
          if (!c.inactive) c.name,
      ];
      if (mounted) {
        setState(() {
          _expenseMajors = majors;
          _paymentOptions = pays;
        });
      }
    } catch (_) {}
  }

  String get _defaultPayment =>
      _paymentOptions.isNotEmpty ? _paymentOptions.first : '銀行振込';

  /// PDFを選択 → 行を追加 → 順次 Gemini 解析。
  Future<void> _pickAndExtract() async {
    setState(() => _picking = true);
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ファイル選択に失敗しました: $e')));
      }
    }
    if (!mounted) return;
    setState(() => _picking = false);
    if (res == null || res.files.isEmpty) return;

    final newRows = <_Row>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      final row = _Row(fileName: f.name, bytes: bytes);
      row.income = _defaultIncome;
      row.paymentMethod = _defaultPayment;
      newRows.add(row);
    }
    if (newRows.isEmpty) return;
    setState(() => _rows.addAll(newRows));

    // 1枚ずつ順次解析（レート上限を踏みにくくする）。
    for (final row in newRows) {
      await _extractRow(row);
    }
  }

  Future<void> _extractRow(_Row row) async {
    try {
      final ex = await InvoiceExtractor.instance.extract(
        row.bytes,
        expenseCategories: _expenseMajors.isEmpty ? null : _expenseMajors,
      );
      if (!mounted) return;
      // 種別: バッチ初期値が既定だが、Geminiの推定が異なれば推定を優先採用。
      row.income = ex.isSalesGuess;
      row.date = ex.date;
      if (ex.total != null) row.amountCtrl.text = ex.total.toString();
      // 取引先: 支出=発行元(請求してきた相手) / 収入=宛先(請求した顧客)。
      final counter = row.income ? (ex.billedTo ?? ex.issuer) : (ex.issuer ?? ex.billedTo);
      final desc = [
        ?counter,
        ?ex.summary,
      ].join(' ').trim();
      row.descCtrl.text = desc;
      // 支出の会計科目: Geminiの候補が一覧にあれば採用、無ければ外注費を既定に。
      if (ex.categoryMajor != null && _expenseMajors.contains(ex.categoryMajor)) {
        row.categoryMajor = ex.categoryMajor;
      } else {
        row.categoryMajor = _expenseMajors.contains('外注費')
            ? '外注費'
            : (_expenseMajors.isNotEmpty ? _expenseMajors.first : null);
      }
      row.rawSummary = ex.summary;
      if (ex.isEmpty) {
        row.error = 'うまく読み取れませんでした（手で入力してください）';
      }
      setState(() => row.busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        row.busy = false;
        row.error = '解析エラー: $e';
      });
    }
  }

  int get _validCount => _rows.where((r) => r.valid).length;
  int get _busyCount => _rows.where((r) => r.busy).length;
  int get _total => _rows.where((r) => r.valid).fold(0, (s, r) => s + r.amount!);

  Future<void> _import() async {
    final valid = _rows.where((r) => r.valid).toList();
    if (valid.isEmpty) return;
    final minDate = AppModeManager.instance.current.minDate;
    setState(() => _importing = true);
    var done = 0;
    var skipped = 0;
    final baseId = DateTime.now().microsecondsSinceEpoch;
    var seq = 0;
    for (final r in valid) {
      final date = r.date ?? DateTime.now();
      if (date.isBefore(minDate)) {
        skipped++;
        continue;
      }
      final desc = r.descCtrl.text.trim();
      final tx = core.Transaction(
        id: '$baseId-${seq++}',
        date: date,
        type: r.income
            ? core.TransactionType.income
            : core.TransactionType.expense,
        category: core.Category(
          // 収入は取引内容(取引先/売上区分)を大カテゴリに（収入源別PL集計に合わせる）。
          major: r.income ? desc : (r.categoryMajor ?? '外注費'),
          sub: '',
        ),
        paymentMethod:
            r.paymentMethod.isEmpty ? _defaultPayment : r.paymentMethod,
        description: desc,
        amount: r.amount!,
        memo: r.rawSummary,
      );
      try {
        await TransactionRepository.instance.add(tx);
        done++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _importing = false);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取り込み完了'),
        content: Text('$done件を追加しました。'
            '${skipped > 0 ? '\n（${minDate.year}年${minDate.month}月より前の$skipped件は対象外でスキップ）' : ''}'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final mode = AppModeManager.instance.current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('請求書PDF 一括取り込み',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Color(0xFF1A237E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '請求書PDF（複数可）を選ぶと、AIが取引先・日付・金額を読み取ります。'
                      '内容を確認・修正して「${mode.label}」モードへまとめて記帳します。',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF1A237E)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 種別の初期値（次に読み込む請求書に適用）。
            Row(
              children: [
                const Text('読み込む請求書の種別: ',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.south_west, size: 15),
                          label: Text('支払/外注')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.north_east, size: 15),
                          label: Text('売上')),
                    ],
                    selected: {_defaultIncome},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _defaultIncome = s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 2),
              child: Text('（読み取り後も1件ごとに種別を切り替えられます）',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _picking ? null : _pickAndExtract,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(_picking ? '選択中…' : 'PDFを選ぶ（複数可）'),
              ),
            ),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('記帳できる $_validCount件',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A237E))),
                  if (_busyCount > 0) ...[
                    const SizedBox(width: 12),
                    Text('解析中 $_busyCount件',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEA580C))),
                  ],
                  const Spacer(),
                  Text('合計 ${formatYen(_total)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in _rows) _previewRow(r),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      (_validCount == 0 || _importing || _busyCount > 0)
                          ? null
                          : _import,
                  icon: const Icon(Icons.download_done, size: 18),
                  label: Text(_importing
                      ? '記帳中…'
                      : (_busyCount > 0
                          ? '解析の完了を待っています…'
                          : '$_validCount件を記帳する')),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewRow(_Row r) {
    if (r.busy) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${r.fileName} を解析中…',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    final hasError = r.error != null;
    return Opacity(
      opacity: r.excluded ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        decoration: BoxDecoration(
          color: hasError ? const Color(0xFFFEF2F2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasError
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ファイル名 + 除外チェック
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 14, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(r.fileName,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Tooltip(
                  message: r.excluded ? '記帳に含める' : '記帳から除外',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(r.excluded
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline),
                    onPressed: () =>
                        setState(() => r.excluded = !r.excluded),
                  ),
                ),
              ],
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(r.error!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFB91C1C))),
              ),
            // 種別トグル
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('支出（支払）')),
                ButtonSegment(value: true, label: Text('収入（売上）')),
              ],
              selected: {r.income},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => r.income = s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle:
                    WidgetStateProperty.all(const TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 8),
            // 取引先 / 摘要
            TextField(
              controller: r.descCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '取引内容（取引先・摘要）',
                labelStyle: TextStyle(fontSize: 12),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 日付
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: r.date ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => r.date = d);
                    },
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(
                      r.date == null
                          ? '日付なし'
                          : '${r.date!.year}/${r.date!.month}/${r.date!.day}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: r.date == null
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 金額
                Expanded(
                  child: TextField(
                    controller: r.amountCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '¥',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 会計科目（支出のみ）
                if (!r.income)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          _expenseMajors.contains(r.categoryMajor)
                              ? r.categoryMajor
                              : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '会計科目',
                        labelStyle: TextStyle(fontSize: 12),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF111827)),
                      items: [
                        for (final m in _expenseMajors)
                          DropdownMenuItem(value: m, child: Text(m)),
                      ],
                      onChanged: (v) => setState(() => r.categoryMajor = v),
                    ),
                  ),
                if (!r.income) const SizedBox(width: 8),
                // 支払/受取方法
                Expanded(
                  child: _paymentOptions.isEmpty
                      ? TextField(
                          controller: TextEditingController(
                              text: r.paymentMethod)
                            ..selection = TextSelection.collapsed(
                                offset: r.paymentMethod.length),
                          onChanged: (v) => r.paymentMethod = v,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: r.income ? '受取方法' : '支払方法',
                            labelStyle: const TextStyle(fontSize: 12),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue:
                              _paymentOptions.contains(r.paymentMethod)
                                  ? r.paymentMethod
                                  : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: r.income ? '受取方法' : '支払方法',
                            labelStyle: const TextStyle(fontSize: 12),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF111827)),
                          items: [
                            for (final p in _paymentOptions)
                              DropdownMenuItem(value: p, child: Text(p)),
                          ],
                          onChanged: (v) =>
                              setState(() => r.paymentMethod = v ?? ''),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
