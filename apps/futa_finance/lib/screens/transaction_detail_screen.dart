import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../widgets/centered_body.dart';
import 'expense_input_screen.dart';
import 'income_input_screen.dart';
import 'receipt_viewer_screen.dart';
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

  // 画面内で領収書の保管状態を更新できるよう、可変で保持する。
  late core.Transaction _cur = widget.transaction;
  core.Transaction get _t => _cur;

  /// 紙のレシートで保管済み（現物を税理士へ）フラグの切替。
  /// receiptSaved（対応済みチェック）＝紙でもドライブでも共通、種類は receiptType に記録。
  Future<void> _setPaperKept(bool v) async {
    setState(() => _busy = true);
    final updated =
        _cur.copyWith(receiptSaved: v, receiptType: v ? 'paper' : null);
    try {
      await TransactionRepository.instance.update(updated);
      if (mounted) setState(() => _cur = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      // 収入
      changed =
          await showInputSheet<bool>(context, IncomeInputScreen(editing: _t));
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
    // 制作原価(外注費/売上原価)や売上(収入)は「請求書」、それ以外は「領収書」と表記。
    final isInvoice = t.type == core.TransactionType.income ||
        ['外注費', '売上原価', '制作原価'].any((k) => t.category.major.contains(k));
    final receiptWord = isInvoice ? '請求書' : '領収書';
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
          // 領収書/請求書の保管：ドライブ保存なら閲覧ボタン、
          // 紙で保管する分（店頭レシート・ベンチャーサポート等）は「紙で保管済み」トグル。
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      Text(receiptWord,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151))),
                      const Spacer(),
                      Text(
                        hasReceipt
                            ? '📄 ドライブに保管'
                            : (t.receiptSaved ? '🧾 紙で保管済み' : '未保管'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: (hasReceipt || t.receiptSaved)
                                ? const Color(0xFF059669)
                                : const Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ),
                if (hasReceipt)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // 所有者本人の権限(drive.readonly)でDriveから取得し表示。
                        final url = t.receiptUrl;
                        if (url == null || url.trim().isEmpty) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReceiptViewerScreen(
                              driveUrl: url.trim(),
                              title: receiptWord,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text('$receiptWordを見る'),
                    ),
                  )
                else
                  CheckboxListTile(
                    value: t.receiptSaved,
                    onChanged:
                        _busy ? null : (v) => _setPaperKept(v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    title: const Text('紙のレシートで保管済み',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text('現物を保管して税理士へ渡す分（写真は不要）',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // アクション（編集は支出/収入/振替すべてで可能）
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('編集'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
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
