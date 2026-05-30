import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';

/// v2 のグローバル ThemeData。
/// MaterialApp.theme に渡して、v2 配下の Material widget をまとめて整える。
class V2Theme {
  V2Theme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: V2Colors.accent,
        brightness: Brightness.light,
        primary: V2Colors.accent,
        surface: V2Colors.surface,
        onPrimary: V2Colors.textOnAccent,
        onSurface: V2Colors.textPrimary,
        error: V2Colors.negative,
      ),
      scaffoldBackgroundColor: V2Colors.bg,
      canvasColor: V2Colors.bg,
      dividerColor: V2Colors.divider,
      splashFactory: NoSplash.splashFactory,
      hoverColor: V2Colors.hover,
      focusColor: V2Colors.accentSoft,
      visualDensity: VisualDensity.compact,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: V2Colors.textBody,
        displayColor: V2Colors.textPrimary,
      ),
      iconTheme: const IconThemeData(
        color: V2Colors.textSecondary,
        size: 18,
      ),
      dividerTheme: const DividerThemeData(
        color: V2Colors.divider,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: V2Colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: V2Colors.border),
          borderRadius: BorderRadius.all(
              Radius.circular(V2Spacing.radiusLg)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: V2Colors.surface,
        hoverColor: V2Colors.hover,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
          borderSide: const BorderSide(color: V2Colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
          borderSide: const BorderSide(color: V2Colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
          borderSide: const BorderSide(
              color: V2Colors.focusRing, width: 1.5),
        ),
        labelStyle: const TextStyle(
            fontSize: 12, color: V2Colors.textSecondary),
        hintStyle: const TextStyle(
            fontSize: 13, color: V2Colors.textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: V2Colors.accent,
          foregroundColor: V2Colors.textOnAccent,
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(V2Spacing.radiusSm),
          ),
          textStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: V2Colors.textBody,
          side: const BorderSide(color: V2Colors.border),
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(V2Spacing.radiusSm),
          ),
          textStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: V2Colors.textBody,
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.md, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(V2Spacing.radiusSm),
          ),
          textStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: V2Colors.textPrimary,
          borderRadius:
              BorderRadius.circular(V2Spacing.radiusSm),
        ),
        textStyle: const TextStyle(
            color: V2Colors.textOnAccent, fontSize: 11),
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 4),
        waitDuration: const Duration(milliseconds: 600),
      ),
    );
  }
}
