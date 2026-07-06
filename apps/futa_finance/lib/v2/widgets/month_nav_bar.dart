import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/typography.dart';

/// 月（または年度）の切替バー。資産タブと同じシンプルな「‹ 2026年7月 ›」。
///
/// 全タブ（ホーム/支出/収入/業績/資産）で共通利用し、月切替の見た目を統一する。
/// [center] が true なら横いっぱいに広げて中央寄せ（資産タブと同じ配置）、
/// false なら最小幅（見出し横などに置く用）。
class MonthNavBar extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool center;
  const MonthNavBar({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: center ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left,
              size: 26, color: V2Colors.textSecondary),
          onPressed: onPrev,
        ),
        // 月は重要情報なので大きく見せる（全タブ共通）。
        Text(label,
            style: V2Typography.bodyStrong.copyWith(
                color: V2Colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right,
              size: 26, color: V2Colors.textSecondary),
          onPressed: onNext,
        ),
      ],
    );
  }
}
