import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

/// カテゴリの手動指定色の中央キャッシュ＆リゾルバ。
///
/// ユーザーが大カテゴリに色を指定（[core.MajorCategory.colorValue]）すると、
/// 支出明細・内訳など各所の色がそれに従う。未指定なら各画面の自動生成色。
/// [update] は CategoryConfig 読み込み時に呼ばれ（SettingsRepository）、
/// [resolve] は色を出す各所から参照される。
class CategoryColors {
  CategoryColors._();

  /// 選べる10色（カテゴリ色プリセット）。
  static const palette = <int>[
    0xFF6366F1, // インディゴ
    0xFF3B82F6, // ブルー
    0xFF06B6D4, // シアン
    0xFF10B981, // エメラルド
    0xFF84CC16, // ライム
    0xFFF59E0B, // アンバー
    0xFFF97316, // オレンジ
    0xFFEF4444, // レッド
    0xFFEC4899, // ピンク
    0xFF8B5CF6, // バイオレット
  ];

  // 数字プレフィックス無しの大カテゴリ名 → 色(ARGB int)。
  static final Map<String, int> _byMajor = {};

  /// "12.通信費" → "通信費"（先頭の "数字." を除く）。
  static String bareMajor(String major) =>
      major.replaceFirst(RegExp(r'^\d+\.'), '').trim();

  /// CategoryConfig からキャッシュを作り直す。
  static void update(core.CategoryConfig config) {
    _byMajor.clear();
    for (final m in config.majors) {
      if (m.colorValue != null) _byMajor[m.name.trim()] = m.colorValue!;
    }
  }

  /// 指定の大カテゴリ名（プレフィックス有/無どちらでも可）の手動色。無ければ null。
  static Color? resolve(String major) {
    final v = _byMajor[bareMajor(major)] ?? _byMajor[major.trim()];
    return v == null ? null : Color(v);
  }
}
