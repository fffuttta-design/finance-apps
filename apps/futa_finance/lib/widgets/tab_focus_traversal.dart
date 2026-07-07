import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 子ツリー内で Tab / Shift+Tab を「次 / 前のフォーカス可能な入力欄へ移動」に
/// 明示的に配線するラッパー。
///
/// RawAutocomplete（入力予測つきの欄）にフォーカスがあると、Tab がフィールド外へ
/// 伝播せず次の欄へ移らないことがある。これで包むと、Tab で確実に次の入力欄へ、
/// Shift+Tab で前の入力欄へフォーカスが移る。
class TabFocusTraversal extends StatelessWidget {
  const TabFocusTraversal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.tab): () =>
            FocusScope.of(context).nextFocus(),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            FocusScope.of(context).previousFocus(),
      },
      child: child,
    );
  }
}
