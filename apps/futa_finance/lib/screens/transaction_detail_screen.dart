import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:url_launcher/url_launcher.dart';

import '../data/drive_receipt_service.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../widgets/centered_body.dart';
import 'expense_input_screen.dart';
import 'receipt_image_screen.dart';
import 'transfer_input_screen.dart';

/// 取引の詳細画面（フル画面）。
/// 明細をタップ → ここで内容を確認 → 「編集」「削除」を選べる。
/// 編集保存 or 削除したら Navigator.pop(context, true) を返し、一覧側で再読込する。
class TransactionDetailScreen extends StatefulWidget {
  final core.Transaction transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _busy = false;

  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];

  core.Transaction get _t => widget.transaction;

  Color get _accent {
    switch (_t.type) {
      case core.TransactionType.income:
        return const Color(0xFF059669);
      case core.TransactionType.transfer:
        return const Color(0xFF6B7280);
      case core.TransactionType.expense:
        return const Color(0xFFDC2626);
    }
  }

  String get _signedAmount {
    final y = formatYen(_t.amount);
    switch (_t.type) {
      case core.TransactionType.income:
        return '+$y';
      case core.TransactionType.transfer:
        return y;
      case core.TransactionType.expense:
        return '-$y';
    }
  }

  Future<void> _edit() async {
    bool? changed;
    if (_t.type == core.TransactionType.transfer) {
      // 振替は専用エディタで編集（汎用の支出エディタは振替を扱えない）。
      changed = await showTransferInputModal(context, editing: _t);
    } else if (_t.type == core.TransactionType.expense) {
      changed =
          await showInputSheet<bool>(context, ExpenseInputScreen(editing: _t));
    } else {
      return; // 収入は現状この画面からの編集は未対応。
    }
    if (changed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('この明細を削除しますか？'),
        content: Text(
            '「${_t.description.isEmpty ? _t.category.major : _t.description}」'
            ' / $_signedAmount\nこの操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await TransactionRepository.instance.delete(_t.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final hasReceipt = t.receiptUrl != null && t.receiptUrl!.trim().isNotEmpty;
    // 表示用に先頭の自動番号（"4." など）を取り除く。
    final majorBare =
        t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
    final cat = t.category.sub.isNotEmpty
        ? '$majorBare › ${t.category.sub}'
        : majorBare;
    final wd = _wd[(t.date.weekday - 1) % 7];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('明細')),
      // Web/PC で横いっぱいに広がりすぎないよう中央寄せ＋最大幅。スマホは全幅。
      body: CenteredBody(
        maxWidth: 560,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // 金額カード
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Text(
                  t.description.isEmpty ? cat : t.description,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  _signedAmount,
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: _accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 明細項目
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                _row('日付',
                    '${t.date.year}/${t.date.month}/${t.date.day}（$wd）'),
                _div(),
                _row('カテゴリ', cat),
                _div(),
                _row('支払方法',
                    t.paymentMethod.isEmpty ? '—' : t.paymentMethod),
                if (t.store != null && t.store!.trim().isNotEmpty) ...[
                  _div(),
                  _row('店舗', t.store!.trim()),
                ],
                if (t.memo != null && t.memo!.trim().isNotEmpty) ...[
                  _div(),
                  _row('メモ', t.memo!.trim()),
                ],
              ],
            ),
          ),
          if (hasReceipt) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final raw = t.receiptUrl!.trim();
                  final fileId = DriveReceiptService.fileIdFromUrl(raw);
                  if (fileId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ReceiptImageScreen(fileId: fileId)),
                    );
                    return;
                  }
                  final uri = Uri.tryParse(raw);
                  if (uri != null) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('領収書を見る'),
              ),
            ),
          ],
          const SizedBox(height: 28),
          // アクション
          Row(
            children: [
              if (t.type == core.TransactionType.expense)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('編集'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              if (t.type == core.TransactionType.expense)
                const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_outline, size: 18),
                  label: const Text('削除'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _div() => const Divider(height: 1, color: Color(0xFFEEF0F3));

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
