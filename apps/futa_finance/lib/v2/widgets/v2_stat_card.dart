import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'v2_card.dart';

/// KPI / 統計カード（マネフォ ME 寄り）。
/// 左上に円形のカラーバッジ、その下に label と value、delta を縦並びで。
class V2StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  /// アイコンバッジの色味（資産=青、収入=緑、支出=赤、貯蓄=紫、警告=黄）
  final V2BadgeColor badgeColor;
  final Color? valueColor;
  final String? delta;
  final V2StatDelta? deltaKind;
  final VoidCallback? onTap;

  const V2StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.badgeColor = V2BadgeColor.green,
    this.valueColor,
    this.delta,
    this.deltaKind,
    this.onTap,
  });

  (Color, Color) _badgePalette() {
    switch (badgeColor) {
      case V2BadgeColor.blue:
        return (V2Colors.badgeBlue, V2Colors.badgeBlueSoft);
      case V2BadgeColor.green:
        return (V2Colors.badgeGreen, V2Colors.badgeGreenSoft);
      case V2BadgeColor.red:
        return (V2Colors.badgeRed, V2Colors.badgeRedSoft);
      case V2BadgeColor.purple:
        return (V2Colors.badgePurple, V2Colors.badgePurpleSoft);
      case V2BadgeColor.amber:
        return (V2Colors.badgeAmber, V2Colors.badgeAmberSoft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _badgePalette();
    return V2Card(
      onTap: onTap,
      hoverable: onTap != null,
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius:
                        BorderRadius.circular(V2Spacing.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: fg),
                ),
              if (icon != null) const SizedBox(width: V2Spacing.sm),
              Expanded(
                child: Text(label,
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.md),
          Text(
            value,
            style: V2Typography.kpiValue.copyWith(
                color: valueColor ?? V2Colors.textPrimary),
          ),
          if (delta != null) ...[
            const SizedBox(height: V2Spacing.sm),
            _DeltaPill(text: delta!, kind: deltaKind ?? V2StatDelta.neutral),
          ],
        ],
      ),
    );
  }
}

/// アイコンバッジの色味
enum V2BadgeColor { blue, green, red, purple, amber }

/// delta（前期比）の色分け
enum V2StatDelta { positive, negative, neutral }

class _DeltaPill extends StatelessWidget {
  final String text;
  final V2StatDelta kind;
  const _DeltaPill({required this.text, required this.kind});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (kind) {
      V2StatDelta.positive => (V2Colors.positive, V2Colors.positiveSoft),
      V2StatDelta.negative => (V2Colors.negative, V2Colors.negativeSoft),
      V2StatDelta.neutral => (V2Colors.textSecondary, V2Colors.surfaceMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
      ),
      child: Text(text,
          style: V2Typography.micro.copyWith(color: fg)),
    );
  }
}
