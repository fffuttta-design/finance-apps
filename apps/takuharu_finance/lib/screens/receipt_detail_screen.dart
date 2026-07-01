import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:url_launcher/url_launcher.dart';

import '../data/auth_service.dart';
import '../data/categories.dart';
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/receipt_comment_repository.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/comment_thread.dart';
import 'receipt_edit_screen.dart';
import 'receipt_image_screen.dart';

/// レシート1枚＝1画面の詳細。
///
/// 上部にレシートの概要（店名・日付・支払者・支払元・合計・レシート画像）、
/// その下に品目の一覧（読み取り専用）、まとめ「編集」「削除」ボタン、
/// さらに下に **1本のコメント欄**（[CommentThread]）を並べる。
///
/// 旧「品目ごと」に付いていたコメントは、この画面を開いたときに
/// レシートの1スレッドへ寄せて統合する（[ReceiptCommentRepository.migrateFromItems]）。
class ReceiptDetailScreen extends StatefulWidget {
  final List<core.Transaction> members;
  const ReceiptDetailScreen({super.key, required this.members});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late List<core.Transaction> _members = List.of(widget.members);
  bool _changed = false;
  CommentSource? _source;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';
  String? get _receiptId => _members.isEmpty ? null : _members.first.receiptId;

  @override
  void initState() {
    super.initState();
    final hid = HouseholdService.instance.householdId;
    final rid = _receiptId;
    if (hid != null && rid != null && rid.isNotEmpty) {
      _source = ReceiptCommentSource(hid, rid);
      // 旧・品目別コメントをレシートの1スレッドへ統合（初回だけ実行・冪等）。
      // ストリームが拾うので await しない（統合が終わり次第、画面に反映される）。
      ReceiptCommentRepository.instance
          .migrateFromItems(hid, rid, _members.map((m) => m.id).toList());
    }
  }

  /// まとめ編集（ReceiptEditScreen）を開き、戻ってきたら品目を取り直す。
  Future<void> _editReceipt() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReceiptEditScreen(members: _members)),
    );
    if (changed != true) return;
    _changed = true;
    final hid = HouseholdService.instance.householdId;
    final rid = _receiptId;
    if (hid == null || rid == null) return;
    final fresh = await TxRepository.instance.listByReceiptId(hid, rid);
    if (!mounted) return;
    if (fresh.isEmpty) {
      // 編集でレシートを丸ごと消した → 一覧へ戻る。
      Navigator.pop(context, true);
      return;
    }
    setState(() => _members = fresh);
  }

  /// レシートを丸ごと削除（品目すべて）。
  Future<void> _deleteReceipt() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('このレシートを削除しますか？'),
        content:
            Text('品目 ${_members.length}件をまとめて削除します。\nこの操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    for (final m in _members) {
      await TxRepository.instance.delete(hid, m.id, _myUid);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('レシート')),
        body: CommentThread(
          source: _source,
          header: _header(),
          emptyHint: 'このレシートについて話そう ♡\n「これ何買った？」「立て替えありがと！」',
        ),
      ),
    );
  }

  Widget _header() {
    final first = _members.first;
    final total = _members.fold<int>(0, (s, t) => s + t.amount);
    final store = _members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');
    final wd =
        ['月', '火', '水', '木', '金', '土', '日'][(first.date.weekday - 1) % 7];
    final names = HouseholdService.instance.memberNames;
    final payerUid = first.paidBy ?? first.recordedBy;
    final payer = (names.length >= 2 && payerUid != null) ? names[payerUid] : null;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 店名
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppColors.pinkSoft,
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.receipt_long_rounded,
                    color: AppColors.pinkDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(store,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 合計
          Text('-${formatYen(total)}',
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: AppColors.expense)),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF3E1E7)),
          const SizedBox(height: 8),
          _infoRow('日付',
              '${first.date.year}/${first.date.month}/${first.date.day}（$wd）'),
          _infoRow('品目', '🧾 ${_members.length}件'),
          if (first.paymentMethod.isNotEmpty)
            _infoRow('支払元', first.paymentMethod),
          if (payer != null) _infoRow('支払った人', payer),
          const SizedBox(height: 12),
          // 品目一覧（読み取り専用。直したいときは下の「編集」から）
          const Text('内訳',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSub)),
          const SizedBox(height: 6),
          ..._members.map(_itemRow),
          if (first.receiptUrl != null &&
              first.receiptUrl!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openReceiptImage(first.receiptUrl!.trim()),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('レシートを見る'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.pinkDark,
                  side: const BorderSide(color: AppColors.pinkSoft, width: 1.4),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editReceipt,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('編集（まとめて）'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deleteReceipt,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('削除'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.expense,
                    side: BorderSide(
                        color: AppColors.expense.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 品目1行（アイコン・品名・カテゴリ・金額）。読み取り専用。
  Widget _itemRow(core.Transaction t) {
    final c = categoryFor(t.category.major, income: false);
    final personal = t.personalFor != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(c.icon, size: 18, color: c.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.description.isEmpty ? t.category.major : t.description,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(t.category.major,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSub)),
                    if (personal) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.lunch_dining_rounded,
                          size: 12, color: AppColors.pinkDark),
                      const SizedBox(width: 2),
                      const Text('個人わく',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.pinkDark)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('-${formatYen(t.amount)}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.expense)),
        ],
      ),
    );
  }

  Future<void> _openReceiptImage(String raw) async {
    final fileId = DriveReceiptService.fileIdFromUrl(raw);
    if (fileId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptImageScreen(fileId: fileId)),
      );
      return;
    }
    final uri = Uri.tryParse(raw);
    var ok = false;
    if (uri != null) {
      for (final m in const [
        LaunchMode.externalApplication,
        LaunchMode.platformDefault,
      ]) {
        try {
          ok = await launchUrl(uri, mode: m);
        } catch (_) {
          ok = false;
        }
        if (ok) break;
      }
    }
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: raw));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('開けなかったのでリンクをコピーしました。ブラウザに貼って開いてね:\n$raw'),
        ),
      );
    }
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textSub)),
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
