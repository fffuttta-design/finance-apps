import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:url_launcher/url_launcher.dart';

import '../data/auth_service.dart';
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/push_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/comment_thread.dart';
import 'add_transaction_screen.dart';
import 'receipt_image_screen.dart';

/// 取引（単品）1件の明細＋チャット（たく＆はるの会話）。
/// チャット部分は共通ウィジェット [CommentThread] に委譲し、この画面は
/// 明細ヘッダー（金額・日付・カテゴリ…）と編集/削除だけを持つ。
class TransactionChatScreen extends StatefulWidget {
  final core.Transaction transaction;
  const TransactionChatScreen({super.key, required this.transaction});

  @override
  State<TransactionChatScreen> createState() => _TransactionChatScreenState();
}

class _TransactionChatScreenState extends State<TransactionChatScreen> {
  // 編集で内容が変わったら差し替えるため可変で持つ。
  late core.Transaction _t = widget.transaction;
  // 一覧側に「変更あり」を返すためのフラグ。
  bool _changed = false;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // この取引を開いた＝その部屋の通知はもう用済みなので消す（LINE的）。
    PushService.instance.clearForTx(_t.id);
  }

  Future<void> _editTx() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionScreen(editing: _t)),
    );
    if (changed != true) return;
    _changed = true;
    // 最新の内容を取り直してヘッダーを更新。
    final hid = HouseholdService.instance.householdId;
    if (hid != null) {
      final fresh = await TxRepository.instance.getById(hid, _t.id);
      if (fresh != null && mounted) setState(() => _t = fresh);
    }
  }

  Future<void> _deleteTx() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('この記録を削除しますか？'),
        content: Text(
            '「${_t.description.isEmpty ? _t.category.major : _t.description}」を削除します。\nこの操作は取り消せません。'),
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
    await TxRepository.instance.delete(hid, _t.id, _myUid);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final hid = HouseholdService.instance.householdId;
    final income = t.type == core.TransactionType.income;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('明細')),
        body: CommentThread(
          source: hid == null ? null : TxCommentSource(hid, t.id),
          header: _detailHeader(t, income),
        ),
      ),
    );
  }

  /// 明細の詳細ヘッダー（金額・日付・カテゴリ・支払方法・メモ）＋編集/削除。
  Widget _detailHeader(core.Transaction t, bool income) {
    final amountColor = income ? const Color(0xFF2E9E6B) : AppColors.expense;
    final catLabel = t.category.sub.isNotEmpty
        ? '${t.category.major}＞${t.category.sub}'
        : t.category.major;
    final wd = ['月', '火', '水', '木', '金', '土', '日'][(t.date.weekday - 1) % 7];
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品名（買ったもの）を大きく
          Text(
            t.description.isEmpty ? catLabel : t.description,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          // 金額を大きく
          Text('${income ? '+' : '-'}${formatYen(t.amount)}',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: amountColor)),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF3E1E7)),
          const SizedBox(height: 8),
          _infoRow('日付', '${t.date.year}/${t.date.month}/${t.date.day}（$wd）'),
          _infoRow('カテゴリ', catLabel),
          if (t.paymentMethod.isNotEmpty) _infoRow('支払元', t.paymentMethod),
          if (t.memo != null && t.memo!.trim().isNotEmpty)
            _infoRow('メモ', t.memo!.trim()),
          // 個人の食費わく（食費の支出なら、あとから付け外しできる）。
          _personalFoodSection(t),
          if (t.receiptUrl != null && t.receiptUrl!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openReceipt(t),
                icon: Icon(
                    (t.receiptId ?? '').startsWith('detail_')
                        ? Icons.image_rounded
                        : Icons.receipt_long_rounded,
                    size: 18),
                label: Text((t.receiptId ?? '').startsWith('detail_')
                    ? 'くわしい情報を見る'
                    : 'レシートを見る'),
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
                  onPressed: _editTx,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('編集'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deleteTx,
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

  /// レシート画像／くわしい情報のリンクを開く。
  Future<void> _openReceipt(core.Transaction t) async {
    final raw = t.receiptUrl!.trim();
    // まずアプリ内ビューアで開く（ブラウザ/ログイン不要で確実）。
    final fileId = DriveReceiptService.fileIdFromUrl(raw);
    if (fileId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptImageScreen(fileId: fileId)),
      );
      return;
    }
    // フォールバック: IDが取れないURLはブラウザ/コピー。
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

  /// 個人の食費わくセクション（明細では表示だけ）。
  /// - すでに付いている → タグを表示（読み取り専用）
  /// - 付いていない → 何も出さない
  /// 設定・解除・変更は編集画面で行う（明細からは操作しない）。
  Widget _personalFoodSection(core.Transaction t) {
    if (t.personalFor == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _personalFoodTag(t.personalFor!),
      ],
    );
  }

  /// 「個人の食費わく」を使った記録に付ける目印タグ。
  Widget _personalFoodTag(String uid) {
    final name = HouseholdService.instance.memberNames[uid] ?? '個人';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.pink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.lunch_dining_rounded,
              size: 16, color: AppColors.pinkDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$name の個人の食費わくから',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.pinkDark)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
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
