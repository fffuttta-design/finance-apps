import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../widgets/v2_sidebar.dart';
import '../widgets/v2_topbar.dart';

/// v2 のメインシェル。
///
/// レイアウト:
/// ┌──────────────┬─────────────────────────┐
/// │ Sidebar      │ TopBar                  │
/// │              ├─────────────────────────┤
/// │ ナビ         │                         │
/// │              │ Content                 │
/// │              │                         │
/// │              │                         │
/// │ Footer       │                         │
/// └──────────────┴─────────────────────────┘
///
/// AppBar / Bottom Navigation / FAB は使わない（モバイル要素は排除）。
class V2Shell extends StatelessWidget {
  /// 左サイドバー
  final V2Sidebar sidebar;

  /// 上部のトップバー
  final V2TopBar topBar;

  /// メインコンテンツ
  final Widget content;

  const V2Shell({
    super.key,
    required this.sidebar,
    required this.topBar,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sidebar,
            Expanded(
              child: Column(
                children: [
                  topBar,
                  Expanded(
                    child: Container(
                      color: V2Colors.bg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: V2Spacing.contentPaddingH,
                          vertical: V2Spacing.contentPaddingV),
                      child: content,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
