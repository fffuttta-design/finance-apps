import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../widgets/v2_top_header.dart';
import '../widgets/v2_top_nav.dart';

/// マネフォ ME 風の v2.1 シェル。
///
/// レイアウト:
/// ┌────────────────────────────────┐
/// │ TopHeader (ロゴ + モード + 記録)        │
/// ├────────────────────────────────┤
/// │ TopNav (タブ：ホーム/支出/収入/...)       │
/// ├────────────────────────────────┤
/// │                                          │
/// │            Content (中央寄せ)             │
/// │            最大幅 1200px                  │
/// │                                          │
/// └────────────────────────────────┘
class V2TopNavShell extends StatelessWidget {
  final V2TopHeader header;
  final V2TopNav topNav;
  final Widget content;

  /// 中央コンテンツの最大幅。マネフォ ME はだいたい 1040px 前後
  final double maxContentWidth;

  /// モバイル（狭い画面）でナビを下部に置くときの下部ナビ。
  /// [navAtBottom] が true のとき、上タブの代わりにこれを画面下に表示する。
  final Widget? bottomNav;

  /// true のとき、タブを上ではなく下（[bottomNav]）に配置する（たくはる風）。
  final bool navAtBottom;

  const V2TopNavShell({
    super.key,
    required this.header,
    required this.topNav,
    required this.content,
    this.maxContentWidth = 1040,
    this.bottomNav,
    this.navAtBottom = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      // モバイルはタブを下部に（たくはる風）。
      bottomNavigationBar: navAtBottom ? bottomNav : null,
      body: SafeArea(
        // 下部ナビを出すときは下端の SafeArea を bottomNav 側に任せる。
        bottom: !navAtBottom,
        child: Column(
          children: [
            header,
            // 上配置のときだけ上タブを出す。
            // タブ列は V2TopNav 内部で maxWidth に対して中央寄せ + 端まで均等配置
            if (!navAtBottom) topNav,
            // スクロールは各画面側に任せる（v1 画面は ListView を持ち、
            // v2.1 ネイティブ画面は内部で SingleChildScrollView を持つ）。
            Expanded(
              // 横は中央寄せ・縦は上揃え。Center だと内容が少ないタブ（収入など）が
              // 上下中央に寄ってしまい他タブと位置がズレるため topCenter にする。
              child: LayoutBuilder(
                builder: (context, c) {
                  // 広い画面（PC）でコンテンツ列の左右に余白があるときだけ、
                  // 「ここまでが表示エリア」が分かる縦の区切り線を入れる。
                  final showRails = c.maxWidth > maxContentWidth + 1;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: maxContentWidth),
                      child: showRails
                          ? DecoratedBox(
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                      color: V2Colors.border),
                                  right: BorderSide(
                                      color: V2Colors.border),
                                ),
                              ),
                              child: content,
                            )
                          : content,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
