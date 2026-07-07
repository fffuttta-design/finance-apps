import 'package:flutter/material.dart';

/// ページ内検索（Ctrl+F／🔍）の共通部品。
///
/// - [HiliteText]：一致した文字列を黄色マーカーで強調する Text 代替。
/// - [FindScope]：検索語を配下へ配る InheritedWidget（HiliteText が参照）。
/// - [FindController]：開閉・検索語・現在位置（n/m）を保持。
/// - [FindBar]：Chrome ライクな検索バー（入力＋件数＋前後ジャンプ＋閉じる）。
///
/// 「現在の1件」の強調＆ジャンプは各画面側で行う（一致行をオレンジ枠で囲み、
/// `Scrollable.ensureVisible` でその行までスクロール）。表の実装（Column/Table/
/// カード）に依存せず動かすため、ハイライト（黄）と現在位置（枠＋スクロール）を
/// 分けている。

/// 黄色マーカー色。
const Color kFindHighlight = Color(0xFFFFE082);

/// 「現在の1件」を囲むオレンジ枠色。
const Color kFindCurrent = Color(0xFFFB8C00);

// 半角カナ(0xFF66..0xFF9D)→全角カナ（index が対応。濁点は畳まない）。
const String _fwKata =
    'ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

/// 1文字→1文字の正規化（長さを保つ＝ハイライト位置が元文字列と一致する）。
/// 小文字化 / 全角英数→半角 / ひらがな→カタカナ / 半角カナ→全角カナ。
int _normUnit(int c) {
  if (c >= 0x41 && c <= 0x5A) return c + 0x20; // A-Z → a-z
  if (c >= 0xFF21 && c <= 0xFF3A) return c - 0xFF21 + 0x61; // 全角A-Z → a-z
  if (c >= 0xFF41 && c <= 0xFF5A) return c - 0xFF41 + 0x61; // 全角a-z → a-z
  if (c >= 0xFF10 && c <= 0xFF19) return c - 0xFF10 + 0x30; // 全角0-9 → 0-9
  if (c >= 0x3041 && c <= 0x3096) return c + 0x60; // ひらがな → カタカナ
  if (c >= 0xFF66 && c <= 0xFF9D) {
    return _fwKata.codeUnitAt(c - 0xFF66); // 半角カナ → 全角カナ
  }
  return c;
}

/// 表記ゆれを吸収した正規化文字列（元文字列と同じ長さ）。
String findNormalize(String s) {
  final u = s.codeUnits;
  final out = List<int>.filled(u.length, 0);
  for (var i = 0; i < u.length; i++) {
    out[i] = _normUnit(u[i]);
  }
  return String.fromCharCodes(out);
}

/// 正規化済みの検索語が全て数字か（金額検索の判定用）。
bool needleIsAllDigits(String needleNorm) =>
    needleNorm.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(needleNorm);

/// [original] 内で [needleNorm]（正規化済み）に一致する開始位置の一覧。
/// 返す index は元文字列に対するもの（1:1正規化なのでそのまま使える）。
List<int> findMatchStarts(String original, String needleNorm) {
  if (needleNorm.isEmpty || original.isEmpty) return const [];
  final hay = findNormalize(original);
  final starts = <int>[];
  var i = hay.indexOf(needleNorm);
  while (i >= 0) {
    starts.add(i);
    i = hay.indexOf(needleNorm, i + needleNorm.length);
  }
  return starts;
}

/// テキストの数字だけを抜き出した文字列（金額「¥1,304」→「1304」照合用）。
String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// 金額セル用：数字だけを見て [needleDigits] を含むか。
bool amountMatches(String amountText, String needleDigits) {
  if (needleDigits.isEmpty) return false;
  return digitsOnly(amountText).contains(needleDigits);
}

/// 配下の HiliteText に検索語を配る。
class FindScope extends InheritedWidget {
  const FindScope({
    super.key,
    required this.needleNorm,
    required super.child,
  });

  /// 正規化済みの検索語（空＝検索なし）。
  final String needleNorm;

  static String needleOf(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<FindScope>();
    return s?.needleNorm ?? '';
  }

  @override
  bool updateShouldNotify(FindScope old) => old.needleNorm != needleNorm;
}

/// 一致部分を黄色マーカーで強調する Text 代替。
/// [FindScope] が無い／検索語が空のときは素の Text と同じ。
class HiliteText extends StatelessWidget {
  const HiliteText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.start,
    this.amount = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;

  /// 金額セル（数字だけで照合し、一致したらセル全体を黄色に）。
  final bool amount;

  @override
  Widget build(BuildContext context) {
    final needle = FindScope.needleOf(context);
    if (needle.isEmpty) return _plain();

    if (amount) {
      if (needleIsAllDigits(needle) && amountMatches(text, needle)) {
        return Text(
          text,
          style: (style ?? const TextStyle())
              .copyWith(backgroundColor: kFindHighlight),
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
        );
      }
      return _plain();
    }

    final starts = findMatchStarts(text, needle);
    if (starts.isEmpty) return _plain();

    final len = needle.length;
    final spans = <TextSpan>[];
    var idx = 0;
    for (final s in starts) {
      if (s > idx) spans.add(TextSpan(text: text.substring(idx, s)));
      spans.add(TextSpan(
        text: text.substring(s, s + len),
        style: const TextStyle(
          backgroundColor: kFindHighlight,
          color: Color(0xFF111827),
          fontWeight: FontWeight.w700,
        ),
      ));
      idx = s + len;
    }
    if (idx < text.length) spans.add(TextSpan(text: text.substring(idx)));

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  Widget _plain() => Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
}

/// ページ内検索の状態（開閉・検索語・現在位置）。
class FindController extends ChangeNotifier {
  bool _open = false;
  String _query = '';

  /// 総ヒット数（各画面が毎ビルドで更新する。通知はしない）。
  int total = 0;

  /// 現在の位置（0始まり）。
  int index = 0;

  bool get isOpen => _open;
  String get query => _query;

  /// 正規化済みの検索語。
  String get needleNorm => findNormalize(_query);

  void open() {
    if (!_open) {
      _open = true;
      notifyListeners();
    }
  }

  void toggle() {
    _open = !_open;
    if (!_open) {
      _query = '';
      index = 0;
    }
    notifyListeners();
  }

  void close() {
    if (_open) {
      _open = false;
      _query = '';
      index = 0;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    _query = q;
    index = 0;
    notifyListeners();
  }

  void next() {
    if (total > 0) {
      index = (index + 1) % total;
      notifyListeners();
    }
  }

  void prev() {
    if (total > 0) {
      index = (index - 1 + total) % total;
      notifyListeners();
    }
  }
}

/// Chrome ライクな検索バー（入力＋「n/m」＋前後ジャンプ＋閉じる）。
/// 右上などに Positioned で浮かせて使う想定。
class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.controller,
    this.accent = const Color(0xFF1A237E),
    this.hint = 'ページ内を検索',
  });

  final FindController controller;
  final Color accent;
  final String hint;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _textCtrl.text = widget.controller.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final has = c.query.isNotEmpty;
    final countText = !has
        ? ''
        : (c.total == 0 ? '0 件' : '${c.index + 1} / ${c.total}');
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 18, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _textCtrl,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: c.setQuery,
                onSubmitted: (_) => c.next(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 64,
              child: Text(
                countText,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    color: c.total == 0 && has
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF6B7280)),
              ),
            ),
            _iconBtn(Icons.keyboard_arrow_up, '前へ',
                c.total > 0 ? c.prev : null),
            _iconBtn(Icons.keyboard_arrow_down, '次へ',
                c.total > 0 ? c.next : null),
            _iconBtn(Icons.close, '閉じる', c.close),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        color: const Color(0xFF374151),
      );
}
