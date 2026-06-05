import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/auth_service.dart';
import '../data/comment_repository.dart';
import '../data/household_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

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

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

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
      await CommentRepository.instance
          .add(hid, widget.transaction.id, _myUid, text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final hid = HouseholdService.instance.householdId;
    final income = t.type == core.TransactionType.income;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.description.isEmpty ? t.category.major : t.description,
                style: const TextStyle(fontSize: 15)),
            Text(
                '${t.date.month}/${t.date.day} ・ '
                '${income ? '+' : '-'}${formatYen(t.amount)}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub)),
          ],
        ),
      ),
      body: Column(
        children: [
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
    );
  }

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
                  hintText: 'メッセージを入力…',
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
