import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 貼り付け取込：TSV（日付 タブ カテゴリ タブ 内容 タブ 金額）を貼って一括登録。
class PasteImportScreen extends StatefulWidget {
  const PasteImportScreen({super.key});

  @override
  State<PasteImportScreen> createState() => _PasteImportScreenState();
}

class _Row {
  final String raw;
  final core.Transaction? tx;
  final String? error;
  const _Row({required this.raw, this.tx, this.error});
}

class _PasteImportScreenState extends State<PasteImportScreen> {
  final _ctrl = TextEditingController();
  final _yearCtrl =
      TextEditingController(text: DateTime.now().year.toString());
  core.TransactionType _type = core.TransactionType.expense;
  List<_Row> _rows = [];
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _parse() {
    final year = int.tryParse(_yearCtrl.text) ?? DateTime.now().year;
    final out = <_Row>[];
    final lines = _ctrl.text.split('\n');
    var seq = 0;
    for (final line in lines) {
      final raw = line.trimRight();
      if (raw.trim().isEmpty) continue;
      // タブ優先、無ければ2つ以上の空白で分割
      final parts = raw.contains('\t')
          ? raw.split('\t')
          : raw.split(RegExp(r'\s{2,}|\t'));
      if (parts.length < 4) {
        out.add(_Row(raw: raw, error: '列が足りません（日付/カテゴリ/内容/金額）'));
        continue;
      }
      final dateStr = parts[0].trim();
      final category = parts[1].trim();
      final desc = parts[2].trim();
      final amountStr = parts.sublist(3).join(' ').trim();

      DateTime? date;
      final ymd =
          RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})$').firstMatch(dateStr);
      final md = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})$').firstMatch(dateStr);
      if (ymd != null) {
        date = DateTime(int.parse(ymd.group(1)!), int.parse(ymd.group(2)!),
            int.parse(ymd.group(3)!));
      } else if (md != null) {
        date = DateTime(year, int.parse(md.group(1)!), int.parse(md.group(2)!));
      } else {
        out.add(_Row(raw: raw, error: '日付が不正: "$dateStr"'));
        continue;
      }

      final amount =
          int.tryParse(amountStr.replaceAll(RegExp(r'[^0-9]'), ''));
      if (amount == null || amount <= 0) {
        out.add(_Row(raw: raw, error: '金額が不正: "$amountStr"'));
        continue;
      }
      if (desc.isEmpty) {
        out.add(_Row(raw: raw, error: '内容が空です'));
        continue;
      }
      out.add(_Row(
        raw: raw,
        tx: core.Transaction(
          id: '${DateTime.now().microsecondsSinceEpoch}-${seq++}',
          date: date,
          type: _type,
          category: core.Category(
              major: category.isEmpty ? 'その他' : category, sub: ''),
          paymentMethod: '',
          description: desc,
          amount: amount,
        ),
      ));
    }
    setState(() => _rows = out);
  }

  Future<void> _import() async {
    final ok = _rows.where((r) => r.tx != null).map((r) => r.tx!).toList();
    if (ok.isEmpty) return;
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return;
    setState(() => _saving = true);
    try {
      await TxRepository.instance.addAll(hid, ok, uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ok.length}件を取り込みました')),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('取り込みに失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final okCount = _rows.where((r) => r.tx != null).length;
    final errCount = _rows.length - okCount;
    return Scaffold(
      appBar: AppBar(title: const Text('貼り付けで取り込み')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '1行 = 「日付（タブ）カテゴリ（タブ）内容（タブ）金額」で貼り付け。\n'
              '日付は 2026/6/5 または 6/5（年は下で指定）。',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('支出'),
                  selected: _type == core.TransactionType.expense,
                  onSelected: (_) =>
                      setState(() => _type = core.TransactionType.expense),
                  selectedColor: AppColors.pinkSoft,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('収入'),
                  selected: _type == core.TransactionType.income,
                  onSelected: (_) =>
                      setState(() => _type = core.TransactionType.income),
                  selectedColor: AppColors.pinkSoft,
                ),
                const Spacer(),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '年', isDense: true, suffixText: '年'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '例:\n6/5\t食費\tスーパー\t1280\n6/5\t外食\tカフェ\t680',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _parse,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('解析する'),
            ),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('OK $okCount件',
                      style: const TextStyle(
                          color: AppColors.income,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  if (errCount > 0)
                    Text('エラー $errCount件',
                        style: const TextStyle(
                            color: AppColors.expense,
                            fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in _rows) _rowTile(r),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (_saving || okCount == 0) ? null : _import,
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.pink),
                child: Text(_saving ? '取り込み中…' : '$okCount件を取り込む ♡'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowTile(_Row r) {
    if (r.tx != null) {
      final t = r.tx!;
      return Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          leading: Text('${t.date.month}/${t.date.day}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSub)),
          title: Text(t.description,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(t.category.major,
              style: const TextStyle(fontSize: 11)),
          trailing: Text(formatYen(t.amount),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.expense)),
        ),
      );
    }
    return Card(
      color: const Color(0xFFFFF0F3),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.error_outline_rounded,
            color: AppColors.expense, size: 18),
        title: Text(r.raw,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(r.error ?? '',
            style: const TextStyle(fontSize: 11, color: AppColors.expense)),
      ),
    );
  }
}
