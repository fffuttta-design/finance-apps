import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// v2 トップバー。AppBar の代替（モバイル的な凸感を排除）。
/// 左にパンくず / 画面タイトル、右にプライマリ操作（記録ボタンなど）。
class V2TopBar extends StatelessWidget {
  /// 画面タイトル（パンくず最終要素として表示）
  final String title;

  /// パンくずの祖先要素（"ホーム > 設定" の "ホーム" 部分）
  final List<String> breadcrumbs;

  /// 右側に並べるアクション群
  final List<Widget> actions;

  const V2TopBar({
    super.key,
    required this.title,
    this.breadcrumbs = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: V2Spacing.topbarHeight,
      decoration: const BoxDecoration(
        color: V2Colors.topbar,
        border: Border(
          bottom: BorderSide(color: V2Colors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.xl, vertical: V2Spacing.sm),
      child: Row(
        children: [
          Expanded(child: _breadcrumb()),
          if (actions.isNotEmpty) ...[
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: V2Spacing.sm),
              actions[i],
            ],
          ],
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    final parts = [...breadcrumbs, title];
    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      children.add(Text(
        parts[i],
        style: isLast
            ? V2Typography.bodyStrong.copyWith(
                color: V2Colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )
            : V2Typography.caption.copyWith(
                color: V2Colors.textSecondary),
      ));
      if (!isLast) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: V2Spacing.sm),
          child: Icon(Icons.chevron_right,
              size: 14, color: V2Colors.textMuted),
        ));
      }
    }
    return Row(children: children);
  }
}
