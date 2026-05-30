import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
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

  /// 中央コンテンツの最大幅。マネフォ ME はだいたい 1100px 前後
  final double maxContentWidth;

  const V2TopNavShell({
    super.key,
    required this.header,
    required this.topNav,
    required this.content,
    this.maxContentWidth = 1200,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            header,
            topNav,
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: maxContentWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: V2Spacing.xl,
                          vertical: V2Spacing.xl),
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
