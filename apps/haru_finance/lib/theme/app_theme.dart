import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// はるファイナンスの配色（水色ベース）。
///
/// たくはる由来のフィールド名（pink / pinkDark / pinkSoft）はそのまま残して
/// いるが、値はすべて水色系に置き換えてある（＝アプリ全体のアクセントは水色）。
/// 名前は互換のための別名だと思ってよい。
class AppColors {
  static const pink = Color(0xFF4FC4F0); // メイン（明るい水色）
  static const pinkDark = Color(0xFF1E9FD9); // 濃いめの水色（アイコン・強調）
  static const pinkSoft = Color(0xFFDDF3FD); // 淡い水色（チップ背景等）
  static const bg = Color(0xFFF2FBFF); // 画面背景
  static const card = Colors.white;
  static const text = Color(0xFF34505A); // 見出し（やわらかいスレート）
  static const textSub = Color(0xFF7FA0AB); // サブ
  static const income = Color(0xFF35C2A0); // 収入（ミントグリーン）
  static const expense = Color(0xFFF4796B); // 支出（コーラル）
  // 支出タブ専用のピンク（はるの希望で支出タブだけピンクにする）。
  static const expensePink = Color(0xFFFF6B8A); // メイン
  static const expensePinkLight = Color(0xFFFF8FA8); // グラデ開始
  static const expensePinkDeep = Color(0xFFF2547B); // グラデ終了
  static const expensePinkSoft = Color(0xFFFFE4EC); // 淡いピンク（バー背景等）
  static const divider = Color(0xFFD6EEF8);
}

/// アプリ全体のテーマ。フォントは Zen Maru Gothic（丸ゴシック）。
ThemeData buildHaruTheme() {
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
      hintStyle: const TextStyle(color: Color(0xFFAFC7D0)),
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
