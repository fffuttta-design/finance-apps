import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Future<void> add(String uid, String text,
      {String? imageUrl, ReplyRef? replyTo});
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
  Future<void> add(String uid, String text,
          {String? imageUrl, ReplyRef? replyTo}) =>
      CommentRepository.instance
          .add(hid, txId, uid, text, imageUrl: imageUrl, replyTo: replyTo);
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
  Future<void> add(String uid, String text,
          {String? imageUrl, ReplyRef? replyTo}) =>
      ReceiptCommentRepository.instance.add(hid, receiptId, uid, text,
          imageUrl: imageUrl, replyTo: replyTo);
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

class _CommentThreadState extends State<CommentThread>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _sending = false;
  // 画像をアップロード中か（送信直後〜コメント反映までのプレースホルダ表示用）。
  bool _uploadingImage = false;
  // 自分が送信した直後、新しいコメントの位置（末尾）まで自動スクロールするフラグ。
  bool _pendingScroll = false;
  int _lastMsgCount = 0;

  // リプライ（LINE風）の返信対象。null なら通常投稿。
  TxComment? _replyTarget;
  // 引用タップで元メッセージへ飛んだとき、一瞬光らせる対象の id。
  String? _highlightId;
  // 各メッセージの表示位置（引用タップで ensureVisible するためのキー）。
  final Map<String, GlobalKey> _msgKeys = {};

  Stream<List<TxComment>>? _stream;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _stream = widget.source?.watch();
    // キーボードの開閉（viewInsets 変化）を拾うために監視を登録する。
    WidgetsBinding.instance.addObserver(this);
    // 入力欄にフォーカスが入った瞬間も、最新コメントまで寄せる。
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// キーボードが出た／入力欄にフォーカスした瞬間に、最新コメントを
  /// 入力バーの真上へ寄せる（LINE風の押し上げ）。押し上げ自体は Scaffold の
  /// resizeToAvoidBottomInset（既定 true）が body を縮めて担うので、ここでは
  /// 縮んだ表示域の末尾＝最新コメントが隠れないようスクロール位置だけ追従させる。
  void _keepBottomVisibleForKeyboard() {
    if (!_focus.hasFocus) return;
    // レイアウトが縮んだ後の maxScrollExtent へ寄せる。キーボードは数フレーム
    // かけてせり上がるので、確定後にもう一度寄せて取りこぼしを防ぐ。
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
    Future.delayed(const Duration(milliseconds: 300), _animateToBottom);
  }

  void _onFocusChange() => _keepBottomVisibleForKeyboard();

  // キーボードの高さ（viewInsets.bottom）が変わるたびに呼ばれる。
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _keepBottomVisibleForKeyboard();
  }

  /// メッセージ本文を引用用の1行スニペットにする（改行は空白へ・長すぎは省略）。
  /// 画像のみのコメントは「写真」と表す。
  String _snippetOf(TxComment m) {
    final t = m.text.trim().replaceAll('\n', ' ');
    if (t.isNotEmpty) return t.length > 40 ? '${t.substring(0, 40)}…' : t;
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) return '写真';
    return '';
  }

  /// 返信対象コメントから、Firestoreに保存するリプライ参照を作る。
  ReplyRef? _replyRefFor(TxComment? m) {
    if (m == null) return null;
    return ReplyRef(
      id: m.id,
      uid: m.uid,
      text: _snippetOf(m),
      imageUrl: (m.imageUrl != null && m.imageUrl!.isNotEmpty) ? m.imageUrl : null,
    );
  }

  /// このコメントに返信する状態に入る（入力欄の上に引用プレビューを出す）。
  void _startReply(TxComment m) {
    setState(() => _replyTarget = m);
    _focus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTarget = null);

  /// 吹き出し長押しメニュー（リプライ／コピー）。
  /// log（変更履歴）は会話ではないのでメニューを出さない。
  Future<void> _showBubbleMenu(TxComment m) async {
    if (m.isLog) return;
    final hasText = m.text.trim().isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: AppColors.pinkDark),
              title: const Text('リプライ'),
              onTap: () => Navigator.pop(sheet, 'reply'),
            ),
            if (hasText)
              ListTile(
                leading:
                    const Icon(Icons.copy_rounded, color: AppColors.pinkDark),
                title: const Text('コピー'),
                onTap: () => Navigator.pop(sheet, 'copy'),
              ),
          ],
        ),
      ),
    );
    if (action == 'reply') {
      _startReply(m);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('コピーしました')),
        );
      }
    }
  }

  /// 引用をタップ → 元メッセージまでスクロールして一瞬ハイライト。
  /// 元が見つからない（統合前・削除済みなど）ときは軽く知らせるだけ。
  Future<void> _jumpToOriginal(String id) async {
    final key = _msgKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('元のメッセージが見つかりませんでした')),
        );
      }
      return;
    }
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.3,
    );
    if (!mounted) return;
    setState(() => _highlightId = id);
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
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
    final replyTo = _replyRefFor(_replyTarget);
    setState(() {
      _sending = true;
      _replyTarget = null; // 送ったらリプライ状態を解除
    });
    _ctrl.clear();
    try {
      await source.add(_myUid, text, replyTo: replyTo);
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
    final replyTo = _replyRefFor(_replyTarget);
    setState(() {
      _sending = true;
      _uploadingImage = true; // 「アップロード中」プレースホルダを表示
      _replyTarget = null; // 送ったらリプライ状態を解除
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
      await source.add(_myUid, '', imageUrl: url, replyTo: replyTo);
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

  /// リプライの引用ブロック（吹き出しの上に出す小さな枠）。タップで元へジャンプ。
  Widget _quoteBlock(TxComment m, {required bool mine, required double maxW}) {
    final names = HouseholdService.instance.memberNames;
    final who = names[m.replyToUid] ?? 'パートナー';
    final hasImg = m.replyToImageUrl != null && m.replyToImageUrl!.isNotEmpty;
    final snippet = (m.replyToText != null && m.replyToText!.isNotEmpty)
        ? m.replyToText!
        : (hasImg ? '写真' : '(メッセージ)');
    return GestureDetector(
      onTap: () => _jumpToOriginal(m.replyToId!),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF3E1E7).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: AppColors.pink),
                Flexible(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(who,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.pinkDark)),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (hasImg) ...[
                            const Icon(Icons.photo_rounded,
                                size: 12, color: AppColors.textSub),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(snippet,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textSub)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
          // リプライなら、吹き出しの上に引用ブロックを出す。
          if (m.hasReply)
            _quoteBlock(m, mine: mine, maxW: maxBubbleWidth),
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
    final key = _msgKeys.putIfAbsent(m.id, () => GlobalKey());
    final highlighted = _highlightId == m.id;
    return GestureDetector(
      key: key,
      onLongPress: () => _showBubbleMenu(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.pink.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: mine
              ? [bubble, const SizedBox(width: 8), avatar]
              : [avatar, const SizedBox(width: 8), bubble],
        ),
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

  /// 返信中に入力欄の上へ出す引用プレビュー（だれの何に返信するか＋解除✕）。
  Widget _replyPreview(TxComment m) {
    final names = HouseholdService.instance.memberNames;
    final who = names[m.uid] ?? 'パートナー';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.pinkSoft.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.pink,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$who に返信',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pinkDark)),
                Text(_snippetOf(m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSub),
            tooltip: '返信をやめる',
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final reply = _replyTarget;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reply != null) _replyPreview(reply),
            Row(
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
                focusNode: _focus,
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
          ],
        ),
      ),
    );
  }
}
