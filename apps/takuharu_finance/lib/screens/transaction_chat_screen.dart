import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/comment_repository.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';

/// 取引ごとのチャット（たく＆はるの会話）。
class TransactionChatScreen extends StatefulWidget {
  final core.Transaction transaction;
  const TransactionChatScreen({super.key, required this.transaction});

  @override
  State<TransactionChatScreen> createState() => _TransactionChatScreenState();
}

class _TransactionChatScreenState extends State<TransactionChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  // 編集で内容が変わったら差し替えるため可変で持つ。
  late core.Transaction _t = widget.transaction;
  // 一覧側に「変更あり」を返すためのフラグ。
  bool _changed = false;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

  Future<void> _editTx() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AddTransactionScreen(editing: _t)),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    await TxRepository.instance.delete(hid, _t.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await CommentRepository.instance.add(hid, _t.id, _myUid, text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      body: Column(
        children: [
          _detailHeader(t, income),
          // コメント欄の見出し（ここから下がチャット）
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF1F4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 14, color: AppColors.pinkDark),
                SizedBox(width: 6),
                Text('コメント',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pinkDark)),
              ],
            ),
          ),
          Expanded(
            child: hid == null
                ? const SizedBox()
                : StreamBuilder<List<TxComment>>(
                    stream: CommentRepository.instance.watch(hid, t.id),
                    builder: (context, snap) {
                      final msgs = snap.data ?? const <TxComment>[];
                      if (msgs.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text(
                                'この記録について話そう ♡\n「これ何に使った？」「立て替えありがと！」',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.textSub, fontSize: 13)),
                          ),
                        );
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scroll.hasClients) {
                          _scroll.jumpTo(_scroll.position.maxScrollExtent);
                        }
                      });
                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) => _bubble(msgs[i]),
                      );
                    },
                  ),
          ),
          _inputBar(),
        ],
      ),
      ),
    );
  }

  /// 明細の詳細ヘッダー（金額・日付・カテゴリ・支払方法・メモ）＋編集/削除。
  Widget _detailHeader(core.Transaction t, bool income) {
    final amountColor =
        income ? const Color(0xFF2E9E6B) : AppColors.expense;
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
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800),
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
                child: FilledButton.icon(
                  onPressed: _deleteTx,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('削除'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.expense),
                ),
              ),
            ],
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
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSub)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _bubble(TxComment m) {
    final mine = m.uid == _myUid;
    final names = HouseholdService.instance.memberNames;
    final icons = HouseholdService.instance.memberIcons;
    final name = names[m.uid] ?? 'パートナー';
    final icon = icons[m.uid];
    final time = m.createdAt != null
        ? '${m.createdAt!.hour.toString().padLeft(2, '0')}:'
            '${m.createdAt!.minute.toString().padLeft(2, '0')}'
        : '';
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.pinkSoft,
      child: (icon != null && icon.isNotEmpty)
          ? Text(icon, style: const TextStyle(fontSize: 16))
          : const Icon(Icons.person_rounded,
              size: 18, color: AppColors.pinkDark),
    );
    final bubble = Flexible(
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(name,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? AppColors.pink : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: mine ? null : Border.all(color: AppColors.divider),
            ),
            child: Text(m.text,
                style: TextStyle(
                    fontSize: 14,
                    color: mine ? Colors.white : AppColors.text)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(time,
                style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: mine
            ? [bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'コメントを入力',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.pinkSoft.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppColors.pink),
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
