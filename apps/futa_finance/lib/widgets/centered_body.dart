import 'package:flutter/material.dart';

/// 広い画面（Web/Desktop）で中央寄せ + 最大幅を強制する共通ラッパー。
/// モバイル（狭い画面）では何もせず子をそのまま返す。
///
/// 用途: 設定系の編集画面（カテゴリ/ウォレット/カード/収入マスタ/固定費/
/// チェックリスト等）で、Web で横に広がりすぎないようにする。
class CenteredBody extends StatelessWidget {
  const CenteredBody({
    super.key,
    required this.child,
    this.maxWidth = 1000,
    this.breakpoint = 900,
  });

  final Widget child;
  final double maxWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.maxWidth < breakpoint) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}
