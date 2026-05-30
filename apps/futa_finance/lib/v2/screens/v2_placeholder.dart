import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';
import '../widgets/v2_section_header.dart';

/// Phase 1〜6 で実装する画面の placeholder。
/// 「機能は v1 と同等」を明示し、利用者には移行中であることを伝える。
class V2PlaceholderScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String phaseLabel;

  const V2PlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.phaseLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V2SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: V2Spacing.lg),
          V2Card(
            child: SizedBox(
              height: 240,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 40, color: V2Colors.textMuted),
                    const SizedBox(height: V2Spacing.md),
                    Text(
                      '$title（v2 実装予定）',
                      style: V2Typography.h2.copyWith(
                          color: V2Colors.textSecondary),
                    ),
                    const SizedBox(height: V2Spacing.xs),
                    Text(phaseLabel, style: V2Typography.caption),
                    const SizedBox(height: V2Spacing.md),
                    Text(
                      '機能は v1 と完全に同等。\n'
                      'デスクトップに最適化したマスター/ディテール構成で再実装します。',
                      textAlign: TextAlign.center,
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
