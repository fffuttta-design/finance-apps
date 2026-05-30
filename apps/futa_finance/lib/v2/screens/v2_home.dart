import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';
import '../widgets/v2_section_header.dart';

/// Phase 0 のホーム placeholder。骨格の確認用。
/// 中身（KPI / フロー / 残高内訳）は Phase 1 で実装する。
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
            subtitle: 'Phase 0: 骨格のみ。Phase 1 で KPI / 残高 / フローを実装します。',
          ),
          const SizedBox(height: V2Spacing.lg),
          V2Card(
            child: SizedBox(
              height: 280,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dashboard_customize_outlined,
                        size: 48, color: V2Colors.textMuted),
                    const SizedBox(height: V2Spacing.md),
                    Text(
                      'v2 ホーム画面（実装予定）',
                      style: V2Typography.h2.copyWith(
                          color: V2Colors.textSecondary),
                    ),
                    const SizedBox(height: V2Spacing.sm),
                    Text(
                      'KPI カード／月次フロー／残高内訳をここに配置',
                      style: V2Typography.caption,
                    ),
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
