import 'package:flutter/material.dart';

/// 入力系画面（支出/収入/振替の記録・編集）を、全画面ではなく
/// 画面手前に浮くモーダルシート（ポップアップ風）で表示する。
///
/// [screen] は Scaffold を持つ画面でもよい（角丸でクリップして表示）。
/// 画面内の Navigator.pop(context, value) はこのシートを閉じ、その値を返す。
Future<T?> showInputSheet<T>(BuildContext context, Widget screen) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // 広い画面（web/PC）では中央寄せの幅に収める。
    constraints: const BoxConstraints(maxWidth: 680),
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
