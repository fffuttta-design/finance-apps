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

  const V2TopNavShell({
    super.key,
    required this.header,
    required this.topNav,
    required this.content,
    this.maxContentWidth = 1040,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            header,
            // タブ列は V2TopNav 内部で maxWidth に対して中央寄せ + 端まで均等配置
            // （ホームタブの左端 = 左カラムの左端、最終タブの右端 = 右カラムの右端）
            topNav,
            // スクロールは各画面側に任せる（v1 画面は ListView を持ち、
            // v2.1 ネイティブ画面は内部で SingleChildScrollView を持つ）。
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: maxContentWidth),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
