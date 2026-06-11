import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/auth_service.dart';
import '../data/comment_repository.dart';
import '../data/drive_receipt_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';
import 'receipt_image_screen.dart';

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
  // 画像をアップロード中か（送信直後〜コメント反映までのプレースホルダ表示用）。
  bool _uploadingImage = false;
  // 自分が送信した直後、新しいコメントの位置（末尾）まで自動スクロールするフラグ。
  bool _pendingScroll = false;
  int _lastMsgCount = 0;

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
      _scrollToBottomSoon();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 画像をギャラリーから選び、Driveに保存してコメントとして送る。
  Future<void> _sendImage() async {
    if (_sending) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
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
      await CommentRepository.instance
          .add(hid, _t.id, _myUid, '', imageUrl: url);
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
  Widget _commentImage(String url, bool mine) {
    final fileId = DriveReceiptService.fileIdFromUrl(url);
    if (fileId == null) return const SizedBox.shrink();
    final future = _imgCache.putIfAbsent(
        fileId, () => DriveReceiptService.instance.downloadFile(fileId));
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReceiptImageScreen(fileId: fileId)),
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
          Expanded(
            child: hid == null
                ? ListView(
                    controller: _scroll,
                    children: [_detailHeader(t, income), _commentHeaderBar()],
                  )
                : StreamBuilder<List<TxComment>>(
                    stream: CommentRepository.instance.watch(hid, t.id),
                    builder: (context, snap) {
                      final msgs = snap.data ?? const <TxComment>[];
                      _maybeScrollAfterBuild(msgs.length);
                      return ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          // 詳細ヘッダーとコメント見出しはスクロールで流れる
                          _detailHeader(t, income),
                          _commentHeaderBar(),
                          if (msgs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Text(
                                  'この記録について話そう ♡\n「これ何に使った？」「立て替えありがと！」',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.textSub, fontSize: 13)),
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
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
          // 個人の食費わくを使った記録は、その旨をはっきり表示。
          if (t.personalFor != null) ...[
            const SizedBox(height: 10),
            _personalFoodTag(t.personalFor!),
          ],
          if (t.receiptUrl != null && t.receiptUrl!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final raw = t.receiptUrl!.trim();
                  // まずアプリ内ビューアで開く（ブラウザ/ログイン不要で確実）。
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
                  // フォールバック: IDが取れないURLはブラウザ/コピー。
                  final uri = Uri.tryParse(raw);
                  var ok = false;
                  if (uri != null) {
                    // 外部ブラウザ→ダメなら既定モードの順で開く。
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
                    // 開けないときはリンクをコピーしてURLを表示（無反応を防ぐ）。
                    await Clipboard.setData(ClipboardData(text: raw));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 10),
                        content: Text(
                            '開けなかったのでリンクをコピーしました。ブラウザに貼って開いてね:\n$raw'),
                      ),
                    );
                  }
                },
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
    // 吹き出しの最大幅。長文でも相手側に食い込みすぎないよう画面の約72%で頭打ち。
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
            // 画像だけのコメントは吹き出し枠なしで画像をそのまま表示する。
            child: (m.imageUrl != null &&
                    m.imageUrl!.isNotEmpty &&
                    m.text.isEmpty)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _commentImage(m.imageUrl!, mine),
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
                          _commentImage(m.imageUrl!, mine),
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
