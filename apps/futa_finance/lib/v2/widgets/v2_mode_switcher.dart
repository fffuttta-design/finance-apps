import 'package:flutter/material.dart';

import '../../data/app_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 事業 / 個人モードの 2 ボタン segmented control。
///
/// [onDark] = true でダーク背景上に乗せる用の配色になる。
/// 既定は明るい背景用（白ヘッダー上）。
class V2ModeSwitcher extends StatelessWidget {
  final bool onDark;
  const V2ModeSwitcher({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModeManager.instance,
      builder: (_, _) {
        final current = AppModeManager.instance.current;
        // ダーク背景時は中間ネイビーの帯、明るい背景時は薄いグレーの帯
        final trackBg = onDark
            ? V2Colors.sidebarHover
            : V2Colors.surfaceMuted;
        return Container(
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            border: onDark
                ? null
                : Border.all(color: V2Colors.border),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              Expanded(
                  child: _segment(
                      label: '事業',
                      mode: AppMode.business,
                      isSelected: current == AppMode.business,
                      accent: V2Colors.accent)),
              Expanded(
                  child: _segment(
                      label: '個人',
                      mode: AppMode.personal,
                      isSelected: current == AppMode.personal,
                      accent: V2Colors.accentPersonal)),
            ],
          ),
        );
      },
    );
  }

  Widget _segment({
    required String label,
    required AppMode mode,
    required bool isSelected,
    required Color accent,
  }) {
    // 未選択テキスト: ダーク背景なら白系、明るい背景ならセカンダリグレー
    final unselectedFg =
        onDark ? V2Colors.sidebarText : V2Colors.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => AppModeManager.instance.setMode(mode),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? V2Colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
          ),
          child: Text(
            label,
            style: V2Typography.caption.copyWith(
              color: isSelected ? accent : unselectedFg,
              fontWeight: isSelected
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
