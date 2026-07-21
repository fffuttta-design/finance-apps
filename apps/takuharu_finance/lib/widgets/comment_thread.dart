import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_service.dart';
import '../data/comment_repository.dart';
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/receipt_comment_repository.dart';
import '../screens/receipt_image_screen.dart';
import '../theme/app_theme.dart';

/// チャットの購読／投稿先を差し替えるための抽象。
/// - 取引（単品）… [TxCommentSource]（transactions/{txId}/comments）
/// - レシート（複数品目まとめ）… [ReceiptCommentSource]（receipts/{rid}/comments）
abstract class CommentSource {
  Stream<List<TxComment>> watch();
  Future<void> add(String uid, String text, {String? imageUrl});
}

/// 取引（単品）1件のチャット。
class TxCommentSource implements CommentSource {
  final String hid;
  final String txId;
  const TxCommentSource(this.hid, this.txId);

  @override
  Stream<List<TxComment>> watch() =>
      CommentRepository.instance.watch(hid, txId);

  @override
  Future<void> add(String uid, String text, {String? imageUrl}) =>
      CommentRepository.instance.add(hid, txId, uid, text, imageUrl: imageUrl);
}

/// レシート（同じ receiptId の複数品目）を1本にまとめたチャット。
class ReceiptCommentSource implements CommentSource {
  final String hid;
  final String receiptId;
  const ReceiptCommentSource(this.hid, this.receiptId);

  @override
  Stream<List<TxComment>> watch() =>
      ReceiptCommentRepository.instance.watch(hid, receiptId);

  @override
  Future<void> add(String uid, String text, {String? imageUrl}) =>
      ReceiptCommentRepository.instance
          .add(hid, receiptId, uid, text, imageUrl: imageUrl);
}

/// 明細／レシートの下に付くチャット欄（たく＆はるの会話）。
///
/// スクロールする本文の先頭に [header]（明細の詳細やレシートの概要）を差し込み、
/// その下にコメントを並べる。入力バーは常に最下段に固定。
/// [source] が null（世帯未参加など）のときは header だけ表示し、入力バーは出さない。
class CommentThread extends StatefulWidget {
  final CommentSource? source;
  final Widget header;

  /// コメントがまだ無いときの案内文。
  final String emptyHint;

  const CommentThread({
    super.key,
    required this.source,
    required this.header,
    this.emptyHint = 'この記録について話そう ♡\n「これ何に使った？」「立て替えありがと！」',
  });

  @override
  State<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<CommentThread> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  // 画像をアップロード中か（送信直後〜コメント反映までのプレースホルダ表示用）。
  bool _uploadingImage = false;
  // 自分が送信した直後、新しいコメントの位置（末尾）まで自動スクロールするフラグ。
  bool _pendingScroll = false;
  int _lastMsgCount = 0;

  Stream<List<TxComment>>? _stream;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _stream = widget.source?.watch();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // 末尾（最新コメント）まで滑らかにスクロール。
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
    // ストリーム反映のタイミングに依存しないよう、時間差のバックストップも入れる。
    Future.delayed(const Duration(milliseconds: 250), _animateToBottom);
    Future.delayed(const Duration(milliseconds: 600), _animateToBottom);
  }

  // ビルド時に呼ぶ。コメントが実際に増えていて送信直後フラグが立っていれば、
  // 描画後に末尾（新しいコメント）まで自動スクロールする。
  void _maybeScrollAfterBuild(int msgCount) {
    final grew = msgCount > _lastMsgCount;
    _lastMsgCount = msgCount;
    if (!_pendingScroll || !grew) return;
    _pendingScroll = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
  }

  Future<void> _send() async {
    final source = widget.source;
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending || source == null) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await source.add(_myUid, text);
      _scrollToBottomSoon();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 画像をギャラリーから選び、Driveに保存してコメントとして送る。
  Future<void> _sendImage() async {
    final source = widget.source;
    if (_sending || source == null) return;
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (x == null) return;
    setState(() {
      _sending = true;
      _uploadingImage = true; // 「アップロード中」プレースホルダを表示
    });
    _scrollToBottomSoon(); // プレースホルダが見えるよう末尾へ
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
      await source.add(_myUid, '', imageUrl: url);
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

  // 同じ画像を何度もDLしないよう fileId 単位でキャッシュ。
  final Map<String, Future<Uint8List?>> _imgCache = {};

  /// コメントの添付画像（Driveから取得して表示・タップで全画面）。
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

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return Column(
      children: [
        Expanded(
          child: source == null
              ? ListView(
                  controller: _scroll,
                  children: [widget.header, _commentHeaderBar()],
                )
              : StreamBuilder<List<TxComment>>(
                  stream: _stream,
                  builder: (context, snap) {
                    final msgs = snap.data ?? const <TxComment>[];
                    _maybeScrollAfterBuild(msgs.length);
                    return ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        widget.header,
                        _commentHeaderBar(),
                        if (msgs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text(widget.emptyHint,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.textSub, fontSize: 13)),
                          )
                        else ...[
                          const SizedBox(height: 12),
                          ...msgs.map((m) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: _bubble(m),
                              )),
                        ],
                        if (_uploadingImage)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                            child: _uploadingBubble(),
                          ),
                      ],
                    );
                  },
                ),
        ),
        if (source != null) _inputBar(),
      ],
    );
  }

  /// コメント欄の見出し（ここから下がチャット）。
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

  /// 変更履歴（kind='log'）。会話の吹き出しではなく、中央のグレー帯で控えめに出す。
  Widget _logChip(TxComment m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFF2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            m.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, height: 1.5, color: AppColors.textSub),
          ),
        ),
      ),
    );
  }

  Widget _bubble(TxComment m) {
    if (m.isLog) return _logChip(m);
    final mine = m.uid == _myUid;
    // 吹き出しの最大幅。長文でも相手側に食い込みすぎないよう画面の約72%で頭打ち。
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.72;
    final names = HouseholdService.instance.memberNames;
    final icons = HouseholdService.instance.memberIcons;
    final name = names[m.uid] ?? 'パートナー';
    final icon = icons[m.uid];
    // createdAt はサーバー時刻。自分の送信直後だけ確定待ちで null になるので、
    // その間は端末の現在時刻で埋めて、送った瞬間から時刻が出るようにする。
    final at = m.createdAt ?? DateTime.now();
    final time = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
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
            // 画像だけのコメントは吹き出し枠なしで画像をそのまま表示する。
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
                      border: mine ? null : Border.all(color: AppColors.divider),
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
                                    color:
                                        mine ? Colors.white : AppColors.text)),
                          ),
                      ],
                    ),
                  ),
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

  // 画像アップロード中の仮バブル（自分側・スピナー＋文言）。
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
                // Enterは改行。送信は右の送信ボタンで行う。
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
