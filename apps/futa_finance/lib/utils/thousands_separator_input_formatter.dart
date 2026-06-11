import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 入力中の「変換中（composing）」下線を描かない TextEditingController。
///
/// 金額欄などで、IME（特に Web）が入力途中の文字に付ける下線が
/// 「無駄なアンダーバー」として見えるのを防ぐ。挙動は通常の
/// TextEditingController と同じで、composing の下線描画だけ止める。
class NoComposingUnderlineController extends TextEditingController {
  NoComposingUnderlineController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // withComposing を常に false にして composing 下線を出さない。
    return super.buildTextSpan(
        context: context, style: style, withComposing: false);
  }
}

/// 全角数字（０-９）を半角（0-9）へ自動変換しつつ、数字以外を取り除く
/// TextInputFormatter。`FilteringTextInputFormatter.digitsOnly` の置き換え用。
///
/// digitsOnly は全角数字を「数字でない」と判定して消してしまうため、
/// うっかり全角で入力すると何も入らない。これを使うと全角で打っても
/// 自動的に半角数字になる。桁区切りと併用する場合は、必ずこのフォーマッタを
/// 先に置く（`[HalfWidthDigitsFormatter(), ThousandsSeparatorInputFormatter()]`）。
class HalfWidthDigitsFormatter extends TextInputFormatter {
  const HalfWidthDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final buf = StringBuffer();
    for (final r in newValue.text.runes) {
      if (r >= 0xFF10 && r <= 0xFF19) {
        buf.writeCharCode(r - 0xFF10 + 0x30); // 全角0-9 → 半角0-9
      } else if (r >= 0x30 && r <= 0x39) {
        buf.writeCharCode(r); // 半角数字はそのまま
      }
      // それ以外（記号・空白・全角記号など）は除去
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// 金額入力欄用の TextInputFormatter。
/// 入力中にリアルタイムで 3桁区切りの `,` を自動挿入する。
///
/// 使い方:
/// ```dart
/// TextFormField(
///   inputFormatters: [ThousandsSeparatorInputFormatter()],
///   ...
/// )
/// ```
///
/// 保存時はテキストをそのまま `int.tryParse` できないため、
/// 必ず `text.replaceAll(',', '')` してからパースする。
/// このため [parseAmount] ヘルパーを併用すると安全。
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  /// マイナス値の入力を許可するか。デフォルト false（金額は通常正の値）。
  final bool allowNegative;

  /// 桁数の上限（区切りカンマを除く実数字）。これを超える入力は弾く。
  /// 連打/貼り付け等で天文学的な桁数に膨れる暴走を防ぐ安全弁。
  /// 12桁＝最大 999,999,999,999（約1兆円）あれば実用上十分。
  final int maxDigits;

  const ThousandsSeparatorInputFormatter({
    this.allowNegative = false,
    this.maxDigits = 12,
  });

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final input = newValue.text;
    if (input.isEmpty) return newValue;

    final negative = allowNegative && input.startsWith('-');
    // 数字以外を除去
    final digitsOnly = input.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) {
      return TextEditingValue(
        text: negative ? '-' : '',
        selection:
            TextSelection.collapsed(offset: negative ? 1 : 0),
      );
    }

    // 桁数上限を超える入力は受け付けない（暴走・誤連打のガード）。
    if (digitsOnly.length > maxDigits) return oldValue;

    // 先頭のゼロを 1桁になるよう削る（"007" → "7" など）
    final trimmed = digitsOnly.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    // 3桁区切り
    final formatted = trimmed.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );

    final result = negative ? '-$formatted' : formatted;
    return TextEditingValue(
      text: result,
      // カーソルは末尾固定（金額入力はほぼ常に末尾編集なので実用上OK）
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

/// カンマ区切り文字列を int に変換する。
/// `"1,234,567"` → `1234567`、空文字や不正値は null。
int? parseAmount(String text) {
  final cleaned = text.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned);
}

/// int を 3桁カンマ区切り文字列に変換する（マイナス値対応）。
/// プログラマティックに `Controller.text = ...` するときに使う。
/// `1234567` → `"1,234,567"`、`-50000` → `"-50,000"`
String formatAmount(int value) {
  final negative = value < 0;
  final abs = value.abs().toString();
  final formatted = abs.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return negative ? '-$formatted' : formatted;
}
