import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';
import '../widgets/v2_section_header.dart';
import '../widgets/v2_stat_card.dart';

/// Phase 0 のホーム placeholder。骨格の確認用。
/// KPI カード 4 枚はデザイン確認用にダミー値で配置。
/// 実データ連携 / フロー / 残高内訳は Phase 1 で実装。
class V2HomeScreen extends StatelessWidget {
  const V2HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const V2SectionHeader(
            title: 'ホーム',
            subtitle:
                'Phase 0 (β): KPI のみダミー値。Phase 1 で実データ連携・フロー・残高内訳を実装します。',
          ),
          const SizedBox(height: V2Spacing.lg),
          // ── KPI カード 4 枚（デザイン確認用） ──
          LayoutBuilder(builder: (ctx, c) {
            // 幅で 4 列 / 2 列を切替
            final cols = c.maxWidth >= 880 ? 4 : 2;
            final gap = V2Spacing.md;
            final cellW =
                (c.maxWidth - gap * (cols - 1)) / cols;
            const items = <_KpiSample>[
              _KpiSample(
                  label: '総資産',
                  value: '¥4,721,207',
                  icon: Icons.account_balance_wallet_outlined,
                  badge: V2BadgeColor.blue),
              _KpiSample(
                  label: '当月収入',
                  value: '+¥225',
                  icon: Icons.trending_up,
                  badge: V2BadgeColor.green),
              _KpiSample(
                  label: '当月支出',
                  value: '-¥490,858',
                  icon: Icons.trending_down,
                  badge: V2BadgeColor.red),
              _KpiSample(
                  label: '差引（黒赤字）',
                  value: '-¥490,633',
                  icon: Icons.swap_vert,
                  badge: V2BadgeColor.amber),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final it in items)
                  SizedBox(
                    width: cellW,
                    child: V2StatCard(
                      label: it.label,
                      value: it.value,
                      icon: it.icon,
                      badgeColor: it.badge,
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: V2Spacing.xl),
          // ── Phase 1 で本実装する領域のプレースホルダ ──
          V2Card(
            child: SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timeline,
                        size: 36, color: V2Colors.textMuted),
                    const SizedBox(height: V2Spacing.sm),
                    Text(
                      '月次フロー / 残高内訳',
                      style: V2Typography.h2.copyWith(
                          color: V2Colors.textSecondary),
                    ),
                    const SizedBox(height: V2Spacing.xs),
                    Text('Phase 1 で実装予定',
                        style: V2Typography.caption),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiSample {
  final String label;
  final String value;
  final IconData icon;
  final V2BadgeColor badge;
  const _KpiSample({
    required this.label,
    required this.value,
    required this.icon,
    required this.badge,
  });
}
