import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 表計算からコピーした明細（タブ区切り）を貼り付けて、取引を**追記**する画面。
///
/// 対応フォーマット（1行=1取引、タブ区切り）:
///   日付(MM/DD)  [曜日]  大カテゴリ  小カテゴリ  内容  支払方法  金額
/// - 曜日列(月〜日)は任意。あっても無くてもよい。
/// - 小カテゴリ・金額は空でも可（金額空は 0 で取り込み）。
/// - 取り込みは「現在のモード（事業/個人）」へ**追加**（既存データは消えない）。
class PasteImportScreen extends StatefulWidget {
  const PasteImportScreen({super.key});

  @override
  State<PasteImportScreen> createState() => _PasteImportScreenState();
}

class _ParsedRow {
  final core.Transaction? tx;
  final String raw;
  final String? error; // 取り込めない致命的エラー
  final String? warn; // 取り込むが注意（金額0など）
  const _ParsedRow({this.tx, required this.raw, this.error, this.warn});
}

class _PasteImportScreenState extends State<PasteImportScreen> {
  final _textCtrl = TextEditingController();
  int _year = DateTime.now().year;
  List<_ParsedRow> _rows = [];
  bool _parsed = false;
  bool _importing = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  static final _weekday = RegExp(r'^[月火水木金土日]$');

  void _parse() {
    final lines = _textCtrl.text.split('\n');
    final out = <_ParsedRow>[];
    var seq = 0;
    for (final line in lines) {
      final raw = line.trim();
      if (raw.isEmpty) continue;
      final parts = line.split('\t').map((e) => e.trim()).toList();
      if (parts.length < 4) {
        out.add(_ParsedRow(raw: raw, error: '列が足りません（タブ区切り？）'));
        continue;
      }
      var i = 0;
      final dateStr = parts[i++];
      // 曜日列は任意。
      if (i < parts.length && _weekday.hasMatch(parts[i])) i++;
      String at(int o) => (i + o) < parts.length ? parts[i + o] : '';
      final major = at(0);
      final sub = at(1);
      final desc = at(2);
      final payment = at(3);
      final amountStr = at(4);

      // 日付
      final dm = RegExp(r'^(\d{1,2})[/\-](\d{1,2})$').firstMatch(dateStr);
      if (dm == null) {
        out.add(_ParsedRow(raw: raw, error: '日付が不正: "$dateStr"'));
        continue;
      }
      final month = int.parse(dm.group(1)!);
      final day = int.parse(dm.group(2)!);
      if (month < 1 || month > 12 || day < 1 || day > 31) {
        out.add(_ParsedRow(raw: raw, error: '日付が不正: "$dateStr"'));
        continue;
      }

      // 金額
      final cleaned =
          amountStr.replaceAll(RegExp(r'[¥,円\s]'), '');
      final amount = cleaned.isEmpty ? 0 : int.tryParse(cleaned);
      if (amount == null) {
        out.add(_ParsedRow(raw: raw, error: '金額が不正: "$amountStr"'));
        continue;
      }

      if (major.isEmpty || desc.isEmpty) {
        out.add(_ParsedRow(
            raw: raw, error: '大カテゴリ／内容が空です'));
        continue;
      }

      final tx = core.Transaction(
        id: '${DateTime.now().microsecondsSinceEpoch}-${seq++}',
        date: DateTime(_year, month, day),
        type: core.TransactionType.expense,
        category: core.Category(major: major, sub: sub),
        paymentMethod: payment,
        description: desc,
        amount: amount,
      );
      out.add(_ParsedRow(
        raw: raw,
        tx: tx,
        warn: amount == 0 ? '金額が0です（後で編集できます）' : null,
      ));
    }
    setState(() {
      _rows = out;
      _parsed = true;
    });
  }

  int get _validCount => _rows.where((r) => r.tx != null).length;
  int get _errorCount => _rows.where((r) => r.error != null).length;
  int get _total =>
      _rows.where((r) => r.tx != null).fold(0, (s, r) => s + r.tx!.amount);

  Future<void> _import() async {
    final valid = _rows.where((r) => r.tx != null).toList();
    if (valid.isEmpty) return;
    setState(() => _importing = true);
    var done = 0;
    for (final r in valid) {
      try {
        await TransactionRepository.instance.add(r.tx!);
        done++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _importing = false);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取り込み完了'),
        content: Text('$done件を追加しました。'),
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
        title: const Text('データ貼り付け取り込み',
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
                      '現在の「${mode.label}」モードに追加します（既存データは消えません）。',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF1A237E)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('年: ',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _year--),
                ),
                Text('$_year',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _year++),
                ),
                const Spacer(),
                const Text('（日付に年が無いため指定）',
                    style:
                        TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textCtrl,
              maxLines: 10,
              minLines: 6,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText:
                    '表計算からコピーしてここに貼り付け\n例: 01/01\t木\t0.固定費\tソフトウェア料金\tChatGPT\tライフカード\t3,582円',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _textCtrl.text.trim().isEmpty ? null : _parse,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('解析してプレビュー'),
              ),
            ),
            if (_parsed) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('取り込み可能 $_validCount件',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A237E))),
                  const SizedBox(width: 12),
                  if (_errorCount > 0)
                    Text('エラー $_errorCount件',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFDC2626))),
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
                      (_validCount == 0 || _importing) ? null : _import,
                  icon: const Icon(Icons.download_done, size: 18),
                  label: Text(_importing
                      ? '取り込み中…'
                      : '$_validCount件を取り込む'),
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

  Widget _previewRow(_ParsedRow r) {
    final err = r.error != null;
    final warn = r.warn != null;
    final tx = r.tx;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: err ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: err
                ? const Color(0xFFFECACA)
                : const Color(0xFFE5E7EB)),
      ),
      child: err
          ? Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 15, color: Color(0xFFDC2626)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${r.error}　/　${r.raw}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFB91C1C)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('${tx!.date.month}/${tx.date.day}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF6B7280))),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.description,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${tx.category.major}${tx.category.sub.isNotEmpty ? ' › ${tx.category.sub}' : ''}　${tx.paymentMethod}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (warn)
                        Text(r.warn!,
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFFEA580C))),
                    ],
                  ),
                ),
                Text('-${formatYen(tx.amount)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626))),
              ],
            ),
    );
  }
}
