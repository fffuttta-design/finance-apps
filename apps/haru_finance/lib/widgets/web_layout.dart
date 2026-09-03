import 'package:flutter/material.dart';

/// 広い画面（Web/タブレット横）で、画面本文が横に間延びしないようにするための部品。
///
/// はるファイナンスはスマホ前提で作ってあるので、パソコンのブラウザで開くと
/// 一覧も入力欄も画面幅いっぱいまで引き伸ばされて読みにくい。本文の横幅だけを
/// 抑えて中央に置くことで、狭い画面（スマホ）の見え方は一切変えずに解消する。

/// 画面本文を中央寄せしつつ、**高さは元のまま（画面いっぱい）**保つ。
///
/// 上寄せで高さを緩めてしまうと、中身が `Column`＋`Expanded` や
/// 「左レール＋右内容」のように高さいっぱいを前提にした作りだと崩れる。
/// こちらは横幅だけを [maxWidth] で抑えるので、既存画面にそのまま被せられる
/// （スマホ幅では [maxWidth] に届かないので実質何も起きない）。
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
