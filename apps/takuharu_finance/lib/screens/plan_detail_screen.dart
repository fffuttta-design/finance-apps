import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_service.dart';
import '../data/comment_repository.dart' show TxComment;
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/plan_comment_repository.dart';
import '../data/plan_item.dart';
import '../data/plan_repository.dart';
import '../theme/app_theme.dart';
import 'receipt_image_screen.dart';

/// プランニング項目の詳細＋コメント（たく＆はるの会話）。
class PlanDetailScreen extends StatefulWidget {
  final PlanItem item;
  const PlanDetailScreen({super.key, required this.item});

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _uploadingImage = false;
  bool _pendingScroll = false;
  int _lastMsgCount = 0;

  late PlanItem _item = widget.item;
  bool _changed = false;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';
  String? get _hid => HouseholdService.instance.householdId;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _animateToBottom() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottomSoon() {
    _pendingScroll = true;
    Future.delayed(const Duration(milliseconds: 250), _animateToBottom);
    Future.delayed(const Duration(milliseconds: 600), _animateToBottom);
  }

  void _maybeScrollAfterBuild(int msgCount) {
    final grew = msgCount > _lastMsgCount;
    _lastMsgCount = msgCount;
    if (!_pendingScroll || !grew) return;
    _pendingScroll = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final hid = _hid;
    if (hid == null) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await PlanCommentRepository.instance.add(hid, _item.id, _myUid, text);
      _scrollToBottomSoon();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final hid = _hid;
    if (hid == null) return;
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (x == null) return;
    setState(() {
      _sending = true;
      _uploadingImage = true;
    });
    _scrollToBottomSoon();
    try {
      final bytes = await x.readAsBytes();
      final url = await DriveReceiptService.instance
          .uploadReceiptImage(bytes: bytes, date: DateTime.now());
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '画像の保存に失敗しました: ${DriveReceiptService.instance.lastError ?? ''}')));
        }
        return;
      }
      await PlanCommentRepository.instance
          .add(hid, _item.id, _myUid, '', imageUrl: url);
      _scrollToBottomSoon();
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadingImage = false;
        });
      }
    }
  }

  Future<void> _toggleDone() async {
    final hid = _hid;
    if (hid == null) return;
    final updated = _item.copyWith(done: !_item.done);
    setState(() {
      _item = updated;
      _changed = true;
    });
    await PlanRepository.instance.save(hid, updated, _myUid);
  }

  Future<void> _edit() async {
    final result = await showDialog<_PlanEditResult>(
      context: context,
      builder: (_) => _PlanEditDialog(item: _item),
    );
    if (result == null) return;
    final hid = _hid;
    if (hid == null) return;
    final updated =
        _item.copyWith(name: result.name, memo: result.detail ?? '');
    setState(() {
      _item = updated;
      _changed = true;
    });
    await PlanRepository.instance.save(hid, updated, _myUid);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('この項目を削除しますか？'),
        content: Text('「${_item.name}」を削除します。\nこの操作は取り消せません。'),
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
    final hid = _hid;
    if (hid == null) return;
    await PlanRepository.instance.delete(hid, _item.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final hid = _hid;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_item.kind.label),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '編集',
              onPressed: _edit,
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
              tooltip: '削除',
              onPressed: _delete,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: hid == null
                  ? ListView(
                      controller: _scroll,
                      children: [_header(), _commentHeaderBar()],
                    )
                  : StreamBuilder<List<TxComment>>(
                      stream:
                          PlanCommentRepository.instance.watch(hid, _item.id),
                      builder: (context, snap) {
                        final msgs = snap.data ?? const <TxComment>[];
                        _maybeScrollAfterBuild(msgs.length);
                        return ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: 12),
                          children: [
                            _header(),
                            _commentHeaderBar(),
                            if (msgs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(40),
                                child: Text(
                                    'この項目について話そう ♡\n「いつ行く？」「ここ気になってた！」',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.textSub,
                                        fontSize: 13)),
                              )
                            else ...[
                              const SizedBox(height: 12),
                              ...msgs.map((m) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: _bubble(m),
                                  )),
                            ],
                            if (_uploadingImage)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                child: _uploadingBubble(),
                              ),
                          ],
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

  Widget _header() {
    final hasDetail = _item.memo != null && _item.memo!.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _item.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _item.done ? AppColors.textSub : AppColors.text,
                    decoration:
                        _item.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 完了/訪問済みトグル
          GestureDetector(
            onTap: _toggleDone,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _item.done
                    ? AppColors.pink.withValues(alpha: 0.14)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _item.done ? AppColors.pink : AppColors.divider,
                  width: _item.done ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _item.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: AppColors.pinkDark,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _item.done ? _item.kind.doneLabel : '${_item.kind.doneLabel}にする',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 詳細（メモ）
          const Text('詳細',
              style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 4),
          if (hasDetail)
            Text(_item.memo!.trim(),
                style: const TextStyle(
                    fontSize: 14, color: AppColors.text, height: 1.5))
          else
            GestureDetector(
              onTap: _edit,
              child: const Text('（まだ詳細はありません。タップして記入）',
                  style: TextStyle(fontSize: 13, color: AppColors.textSub)),
            ),
        ],
      ),
    );
  }

  Widget _commentHeaderBar() => Container(
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
      );

  // 同じ画像を何度もDLしないよう fileId 単位でキャッシュ。
  final Map<String, Future<Uint8List?>> _imgCache = {};

  Widget _commentImage(String url) {
    final fileId = DriveReceiptService.fileIdFromUrl(url);
    if (fileId == null) return const SizedBox.shrink();
    final future = _imgCache.putIfAbsent(
        fileId, () => DriveReceiptService.instance.downloadFile(fileId));
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptImageScreen(fileId: fileId)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 180,
          child: FutureBuilder<Uint8List?>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Container(
                  height: 120,
                  color: AppColors.pinkSoft.withValues(alpha: 0.4),
                  alignment: Alignment.center,
                  child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final bytes = snap.data;
              if (bytes == null) {
                return Container(
                  height: 120,
                  color: AppColors.pinkSoft.withValues(alpha: 0.4),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: AppColors.textSub),
                );
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
        ),
      ),
    );
  }

  Widget _bubble(TxComment m) {
    final mine = m.uid == _myUid;
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.72;
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
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: (m.imageUrl != null &&
                    m.imageUrl!.isNotEmpty &&
                    m.text.isEmpty)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _commentImage(m.imageUrl!),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? AppColors.pink : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border:
                          mine ? null : Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.imageUrl != null && m.imageUrl!.isNotEmpty)
                          _commentImage(m.imageUrl!),
                        if (m.text.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                                top: (m.imageUrl != null &&
                                        m.imageUrl!.isNotEmpty)
                                    ? 6
                                    : 0),
                            child: Text(m.text,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: mine
                                        ? Colors.white
                                        : AppColors.text)),
                          ),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(time,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.textSub)),
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

  Widget _uploadingBubble() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.pink,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white)),
              ),
              SizedBox(width: 8),
              Text('画像をアップロード中…',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
      ],
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
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined,
                  color: AppColors.pinkDark),
              tooltip: '画像を送る',
              onPressed: _sending ? null : _sendImage,
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'コメントを入力',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.pinkSoft.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: AppColors.pink),
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanEditResult {
  final String name;
  final String? detail;
  const _PlanEditResult(this.name, this.detail);
}

class _PlanEditDialog extends StatefulWidget {
  final PlanItem item;
  const _PlanEditDialog({required this.item});

  @override
  State<_PlanEditDialog> createState() => _PlanEditDialogState();
}

class _PlanEditDialogState extends State<_PlanEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.item.name);
  late final TextEditingController _detail =
      TextEditingController(text: widget.item.memo ?? '');

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.item.kind.label}を編集'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名前（必須）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detail,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '詳細（任意）',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            final n = _name.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(
                context,
                _PlanEditResult(
                    n, _detail.text.trim().isEmpty ? null : _detail.text.trim()));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
