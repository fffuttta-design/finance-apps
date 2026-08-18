import 'package:flutter/material.dart';

/// この幅以上を「広い画面（Web/タブレット横）」とみなし、
/// サイドナビ＋中央最大幅のレイアウトに切り替える。
const double kWebBreakpoint = 900.0;

/// 現在の画面が広い（Webレイアウトを使う）かどうか。
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWebBreakpoint;

/// 画面本文を中央寄せし、広い画面でも横に間延びしないよう最大幅で抑える。
/// 幅が [maxWidth] より狭いスマホでは実質そのまま（何も変わらない）。
class WebCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const WebCenter({super.key, required this.child, this.maxWidth = 1040});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
