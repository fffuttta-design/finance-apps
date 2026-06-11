import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 備考欄の共通入力。全画面でこれに統一する。
/// - 基本は1行。内容に応じて伸びる（最大は [maxLines]、null=無制限）。
/// - **Enter は改行しない**（誤爆防止）。**Shift+Enter のときだけ改行**して枠が伸びる。
class MemoField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;

  /// 伸びる上限。null=無制限。
  final int? maxLines;

  const MemoField({
    super.key,
    required this.controller,
    this.label = '備考（任意）',
    this.hint,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter;
        if (event is KeyDownEvent && isEnter) {
          // Shift+Enter のときだけ改行を通す。ただの Enter は改行させない。
          return HardwareKeyboard.instance.isShiftPressed
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
