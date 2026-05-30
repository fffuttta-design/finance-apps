import 'package:flutter/material.dart';

import '../../data/app_mode.dart';
import 'colors.dart';

/// 現在のアプリモード（事業/個人）に応じたアクセント色を返すヘルパー。
/// - 事業: マネフォクラウド準拠の青 (V2Colors.accent)
/// - 個人: マネフォ ME 準拠のオレンジ (V2Colors.accentPersonal)
class V2ModeAccent {
  V2ModeAccent._();

  /// メインアクセント。
  static Color of(AppMode mode) => mode == AppMode.business
      ? V2Colors.accent
      : V2Colors.accentPersonal;

  /// アクセントの淡い版（背景）
  static Color softOf(AppMode mode) => mode == AppMode.business
      ? V2Colors.accentSoft
      : V2Colors.accentPersonalSoft;
}
