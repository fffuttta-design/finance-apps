import 'package:flutter/material.dart';

import '../../data/app_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// サイドバー上部に置く、事業 / 個人モードの 2 ボタン segmented control。
class V2ModeSwitcher extends StatelessWidget {
  const V2ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModeManager.instance,
      builder: (_, _) {
        final current = AppModeManager.instance.current;
        return Container(
          decoration: BoxDecoration(
            color: V2Colors.surfaceMuted,
            borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            border: Border.all(color: V2Colors.border),
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
            border: isSelected
                ? Border.all(color: V2Colors.border)
                : null,
          ),
          child: Text(
            label,
            style: V2Typography.caption.copyWith(
              color: isSelected ? accent : V2Colors.textSecondary,
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
