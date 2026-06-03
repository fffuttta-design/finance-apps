import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// たくはるファイナンスの配色（可愛い系・ピンク基調）。
class AppColors {
  static const pink = Color(0xFFFF6B8A); // メイン
  static const pinkDark = Color(0xFFE85A7A);
  static const pinkSoft = Color(0xFFFFE4EC); // 淡ピンク（チップ背景等）
  static const bg = Color(0xFFFFF5F7); // 画面背景
  static const card = Colors.white;
  static const text = Color(0xFF6B4452); // 見出し（やさしいブラウン）
  static const textSub = Color(0xFFA98592); // サブ
  static const income = Color(0xFF34C2A0); // 収入（ミントグリーン）
  static const expense = Color(0xFFFF6B8A); // 支出（ピンク）
  static const divider = Color(0xFFF3E1E7);
}

/// アプリ全体のテーマ。フォントは Zen Maru Gothic（丸ゴシック）。
ThemeData buildTakuharuTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.pink,
      brightness: Brightness.light,
      primary: AppColors.pink,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );

  return base.copyWith(
    textTheme: GoogleFonts.zenMaruGothicTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.zenMaruGothic(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      iconTheme: const IconThemeData(color: AppColors.pinkDark),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.pink,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.zenMaruGothic(
            fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.pinkDark,
        side: const BorderSide(color: AppColors.pink),
        textStyle: GoogleFonts.zenMaruGothic(
            fontWeight: FontWeight.w700, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFFCBB5BE)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.pink, width: 2),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.pink,
      foregroundColor: Colors.white,
    ),
    dividerColor: AppColors.divider,
  );
}
