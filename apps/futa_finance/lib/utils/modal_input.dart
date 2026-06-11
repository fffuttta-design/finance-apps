import 'package:flutter/material.dart';

/// 入力系画面（支出/収入/振替の記録・編集）を、全画面ではなく
/// 画面手前に浮くポップアップで表示する。
///
/// - ノートPC/Web（幅が広い画面）: 画面中央に浮く**コンパクトなダイアログ**。
///   画面を覆わず、ノートPCでも見やすいサイズに収める（これが基本指針）。
/// - スマホ（幅の狭い画面）: 従来どおり下から出るボトムシート。
///
/// [screen] は Scaffold を持つ画面でもよい（角丸でクリップして表示）。
/// 画面内の Navigator.pop(context, value) はこのポップアップを閉じ、値を返す。
Future<T?> showInputSheet<T>(BuildContext context, Widget screen) {
  final size = MediaQuery.of(context).size;
  // ノートPC/Web/タブレット横向き。スマホ縦（〜600px）と区別する。
  final isWide = size.width >= 700;

  if (isWide) {
    // 中央に浮くコンパクトダイアログ。高さは画面に対して控えめに上限を設ける
    // （ノートPCで画面いっぱいに広がって「でかい」とならないように）。
    final maxH =
        (size.height * 0.86).clamp(420.0, 720.0).toDouble();
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: maxH),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: screen,
            ),
          ),
        ),
      ),
    );
  }

  // スマホ: 下から出るシート。
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      // キーボード分を避ける。
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          child: screen,
        ),
      ),
    ),
  );
}
