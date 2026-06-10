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

  const ThousandsSeparatorInputFormatter({this.allowNegative = false});

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
