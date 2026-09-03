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

/// 画面本文を中央寄せしつつ、**高さは元のまま（画面いっぱい）**保つ版。
///
/// [WebCenter] は上寄せ＝高さが緩むため、中身が `Column`＋`Expanded` や
/// 「左レール＋右内容」のように高さいっぱいを前提にした作りだと崩れる。
/// こちらは横幅だけを [maxWidth] で抑えるので、既存画面にそのまま被せられる。
class WebCenterFill extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const WebCenterFill({super.key, required this.child, this.maxWidth = 1040});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // Align が高さを緩めるので、ここで元の高さ（画面いっぱい）に戻す。
        child: SizedBox(height: double.infinity, child: child),
      ),
    );
  }
}

/// 中央寄せした本文の「右端」に FAB を置くための配置。
///
/// 既定の endFloat は画面の右端に貼り付くので、広い画面では
/// 中央に寄せた本文からボタンだけが遠く離れてしまう。本文の右端に揃える。
class WebEndFloatFabLocation extends FloatingActionButtonLocation {
  final double maxWidth;
  const WebEndFloatFabLocation({this.maxWidth = 1040});

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    // 本文が maxWidth に収まっているとき、左右に余った余白の片側ぶんだけ内側へ寄せる。
    final gap = (geometry.scaffoldSize.width - maxWidth) / 2;
    return gap <= 0 ? base : Offset(base.dx - gap, base.dy);
  }
}
