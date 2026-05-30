import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'v2_card.dart';

/// KPI / 統計カード（Stripe Dashboard / Linear 風）。
/// label / value を中心に、delta（前期比）と icon を補助で表示。
class V2StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final String? delta;
  final V2StatDelta? deltaKind;
  final VoidCallback? onTap;

  const V2StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.delta,
    this.deltaKind,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return V2Card(
      onTap: onTap,
      hoverable: onTap != null,
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.lg, vertical: V2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14, color: V2Colors.textSecondary),
                const SizedBox(width: V2Spacing.xs),
              ],
              Expanded(
                child: Text(label,
                    style: V2Typography.micro.copyWith(
                        color: V2Colors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.sm),
          Text(
            value,
            style: V2Typography.kpiValue.copyWith(
                color: valueColor ?? V2Colors.textPrimary),
          ),
          if (delta != null) ...[
            const SizedBox(height: V2Spacing.xs),
            _DeltaPill(text: delta!, kind: deltaKind ?? V2StatDelta.neutral),
          ],
        ],
      ),
    );
  }
}

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
