import 'package:flutter/material.dart';

import '../utils/emoji_palette.dart';
import 'brand_logo.dart';

/// アイコン選択ダイアログ。
/// - 絵文字パレット
/// - 自由入力（絵文字 / 画像URL / ドメイン）
/// - ドメイン→favicon URL 変換ボタン
/// - リアルタイムプレビュー
///
/// 返り値: 選択された値（絵文字 or 画像URL）。キャンセル時は null。
Future<String?> showEmojiPickerDialog(
  BuildContext context, {
  String? currentEmoji,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EmojiPickerDialog(currentEmoji: currentEmoji),
  );
}

class _EmojiPickerDialog extends StatefulWidget {
  final String? currentEmoji;
  const _EmojiPickerDialog({this.currentEmoji});

  @override
  State<_EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<_EmojiPickerDialog> {
  late final TextEditingController _ctrl;

  /// 絵文字パレットの展開フラグ。初期表示はパレットを描画せず軽量化。
  /// 100個超の Text widget を一気にビルドすると初回が重いため、
  /// ユーザーが「パレットを開く」を押した時だけ描画する。
  bool _showPalette = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentEmoji ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _value => _ctrl.text.trim();

  bool get _isUrl =>
      _value.startsWith('http://') || _value.startsWith('https://');

  /// 入力欄の文字列がドメイン風（"foo.com" など）なら、favicon URL に変換する。
  void _convertDomain() {
    final input = _value;
    if (input.isEmpty) return;
    // すでに http/https / 画像拡張子なら無視
    if (_isUrl ||
        RegExp(r'\.(png|jpg|jpeg|svg|gif|webp|ico)(\?|$)',
                caseSensitive: false)
            .hasMatch(input)) {
      return;
    }
    final url = domainToFaviconUrl(input);
    if (url != null) {
      setState(() => _ctrl.text = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_emotions,
                    color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                const Text('アイコンを選択',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('絵文字 ${kEmojiPalette.length}+ / 画像URL対応',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
            const SizedBox(height: 12),
            // プレビュー（入力中の値をリアルタイムに表示）
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFFC7D2FE), width: 1),
                ),
                alignment: Alignment.center,
                child: categoryIconWidget(
                  _value.isEmpty ? null : _value,
                  size: 40,
                  color: const Color(0xFF1A237E),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLength: 256, // URL 想定で長めに
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '絵文字 / 画像URL / ドメイン',
                hintText: '🏠 / https://example.com/logo.png / example.com',
                helperText: _value.isEmpty
                    ? null
                    : (_isUrl
                        ? '画像URLとして読み込みます'
                        : '絵文字 / アイコン名として表示します'),
                counterText: '',
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.travel_explore, size: 20),
                  tooltip: 'ドメインを favicon URL に変換',
                  onPressed: _convertDomain,
                ),
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            // 絵文字パレット（折りたたみ式）
            InkWell(
              onTap: () =>
                  setState(() => _showPalette = !_showPalette),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.grid_view,
                        size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    Text(
                      _showPalette
                          ? '絵文字パレットを閉じる'
                          : '絵文字パレットから選ぶ',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text('${kEmojiPalette.length}個',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF))),
                    Icon(
                      _showPalette
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: const Color(0xFF6B7280),
                    ),
                  ],
                ),
              ),
            ),
            if (_showPalette) ...[
              const SizedBox(height: 8),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  // キャッシュ範囲を制限してスクロール外を早めに破棄
                  cacheExtent: 200,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: kEmojiPalette.length,
                  itemBuilder: (context, i) {
                    final emoji = kEmojiPalette[i];
                    final selected = emoji == _value;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() => _ctrl.text = emoji);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE0E7FF)
                              : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF1A237E)
                                : const Color(0xFFE5E7EB),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(emoji,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_value.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _ctrl.clear()),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('クリア'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                        context, _value.isEmpty ? null : _value);
                  },
                  child: const Text('決定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
