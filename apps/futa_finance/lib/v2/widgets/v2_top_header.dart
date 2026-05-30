import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// マネフォ ME 風の上部ヘッダー。
/// 左にロゴ、右にモード切替（事業/個人）＋アクション群。
class V2TopHeader extends StatelessWidget {
  /// アクセント色（事業=青、個人=オレンジ）
  final Color accent;

  /// 右側のアクション群
  final List<Widget> actions;

  /// モード切替 widget（segmented control）
  final Widget? modeSwitcher;

  const V2TopHeader({
    super.key,
    required this.accent,
    this.actions = const [],
    this.modeSwitcher,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: V2Colors.surface,
        border: Border(
          bottom: BorderSide(color: V2Colors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.xl, vertical: V2Spacing.sm),
      child: Row(
        children: [
          // ロゴ + アプリ名
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            ),
            alignment: Alignment.center,
            child: const Text('財',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
          const SizedBox(width: V2Spacing.sm),
          Text(
            'FutaFinance',
            style: V2Typography.h2.copyWith(
                color: V2Colors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2),
          ),
          const Spacer(),
          if (modeSwitcher != null) ...[
            SizedBox(width: 240, child: modeSwitcher!),
            const SizedBox(width: V2Spacing.md),
          ],
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: V2Spacing.sm),
            actions[i],
          ],
        ],
      ),
    );
  }
}
