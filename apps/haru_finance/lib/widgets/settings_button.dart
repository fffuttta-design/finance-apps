import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';

/// どのタブの AppBar 右上にも置ける共通の設定ボタン。
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_rounded, color: AppColors.pink),
      tooltip: '設定',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
