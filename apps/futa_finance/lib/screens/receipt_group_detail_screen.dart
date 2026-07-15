import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../widgets/centered_body.dart';
import 'receipt_split_screen.dart';
import 'receipt_viewer_screen.dart';
import 'transaction_detail_screen.dart';

/// 同じレシート/まとめの複数品目を1画面で見る「まとめ明細」詳細。
///
/// ホームや一覧で「○件まとめ」の行をタップしたとき、月全体の一覧ではなく
/// そのまとまりの内訳（各品目）だけを表示する。各品目をタップすると個別の
/// 明細詳細へ。領収書があれば閲覧ボタンも出す。
class ReceiptGroupDetailScreen extends StatelessWidget {
  final List<core.Transaction> members;
  const ReceiptGroupDetailScreen({super.key, required this.members});

  /// 先頭の自動番号（"4." 等）を除いた表示用カテゴリ。
  String _catLabel(core.Category c) {
    final sub = c.sub.trim();
    if (sub.isNotEmpty) return sub;
    return c.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final first = members.first;
    final total = members.fold<int>(0, (s, t) => s + t.amount);
    final isIncome = first.type == core.TransactionType.income;
    final sign = isIncome ? '+' : '-';
    final accent =
        isIncome ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final title = store.isNotEmpty ? store : 'まとめ記録';
    final receiptUrl = members
        .map((t) => t.receiptUrl?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('明細（まとめ）')),
      body: CenteredBody(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // 合計カード
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('$sign${formatYen(total)}',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: accent)),
                  const SizedBox(height: 6),
                  Text(
                    '${members.length}件まとめ　・　'
                    '${first.date.year}/${first.date.month}/${first.date.day}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 内訳（各品目）。タップで個別明細へ。
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < members.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: Color(0xFFEEF0F3)),
                    _itemRow(context, members[i]),
                  ],
                ],
              ),
            ),
            if (receiptUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openReceipt(context, receiptUrl),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('領収書を見る'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 普通の明細と同じく、まとめ単位での編集・削除。
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editGroup(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('編集'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _deleteGroup(context),
                    icon: const Icon(Icons.delete_outline, size: 18),
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

  /// まとめを編集（品目をまとめて編集し、保存で束ね直す）。
  Future<void> _editGroup(BuildContext context) async {
    final first = members.first;
    final receiptUrl = members
        .map((t) => t.receiptUrl?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final changed = await showInputSheet<bool>(
      context,
      ReceiptSplitScreen(
        editingMembers: members,
        date: first.date,
        storeName: first.store,
        receiptId: first.receiptId,
        receiptUrl: receiptUrl.isEmpty ? null : receiptUrl,
        initialCategoryMajor: first.category.major,
        initialCategorySub: first.category.sub,
      ),
    );
    if (changed == true && context.mounted) Navigator.pop(context, true);
  }

  /// まとめ全件を削除。
  Future<void> _deleteGroup(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('このまとめを削除しますか？'),
        content: Text('${members.length}件すべてを削除します。\nこの操作は取り消せません。'),
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
    for (final m in members) {
      await TransactionRepository.instance.delete(m.id);
    }
    if (context.mounted) Navigator.pop(context, true);
  }

  Widget _itemRow(BuildContext context, core.Transaction t) {
    final isIncome = t.type == core.TransactionType.income;
    final sign = isIncome ? '+' : '-';
    final color =
        isIncome ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return InkWell(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transaction: t)),
        );
        // 編集/削除されたらまとめ内容が変わるので、上位で再読込させる。
        if (changed == true && context.mounted) {
          Navigator.pop(context, true);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_catLabel(t.category),
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.description.trim().isEmpty ? '—' : t.description.trim(),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text('$sign${formatYen(t.amount)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFamily: 'monospace')),
            const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  /// 領収書を開く。明細詳細（`transaction_detail_screen`）と同じ `ReceiptViewerScreen`
  /// を使う。⚠ 以前は `ReceiptImageScreen`（`Image.memory` の画像専用）だったため、
  /// **PDFの領収書（ネット注文の明細など）はここから開けなかった**。
  /// `ReceiptViewerScreen` は PDF/画像を判定し、失敗時はDriveで開くところまで面倒を見る。
  Future<void> _openReceipt(BuildContext context, String raw) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ReceiptViewerScreen(driveUrl: raw, title: '領収書')),
    );
  }
}
