import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// セクション見出し。h1 + 任意の右側アクション。
/// メインコンテンツの各ブロック上部に使う。
class V2SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const V2SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: V2Typography.h1),
                if (subtitle != null) ...[
                  const SizedBox(height: V2Spacing.xs),
                  Text(
                    subtitle!,
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: V2Spacing.sm),
                  actions[i],
                ],
              ],
            ),
        ],
      ),
    );
  }
}
