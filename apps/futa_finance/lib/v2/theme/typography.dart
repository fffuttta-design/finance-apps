import 'package:flutter/material.dart';

import 'colors.dart';

/// v2 のタイポグラフィ定義。
/// - フォントファミリは指定せず（Flutter 既定の system-ui + Noto Sans CJK）
/// - 数字を等幅に揃えたい箇所では `fontFeatures: tabularNums` を使う
/// - スケールは Linear / Stripe 風: 11 / 12 / 13 / 14 / 16 / 20 / 28
class V2Typography {
  V2Typography._();

  /// 数字を等幅で表示するための FontFeature リスト。
  /// （`fontFamily: 'monospace'` の代替。プロポーショナルでも桁が揃う）
  static const List<FontFeature> tabularNums = [
    FontFeature.tabularFigures(),
  ];

  // ── スケール ──
  /// 巨大見出し（KPI 数値、画面タイトルの主役）
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: V2Colors.textPrimary,
    height: 1.2,
    letterSpacing: -0.4,
  );

  /// 大見出し（セクションタイトル）
  static const TextStyle h1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: V2Colors.textPrimary,
    height: 1.3,
    letterSpacing: -0.2,
  );

  /// 中見出し（カード内タイトルなど）
  static const TextStyle h2 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: V2Colors.textPrimary,
    height: 1.4,
  );

  /// 強調された本文 / リスト見出し
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: V2Colors.textPrimary,
    height: 1.5,
  );

  /// 通常本文（行・テーブルセル）
  static const TextStyle body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: V2Colors.textBody,
    height: 1.5,
  );

  /// 補助テキスト / メタ情報
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: V2Colors.textSecondary,
    height: 1.4,
  );

  /// 極小（バッジ・タグ）
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: V2Colors.textMuted,
    height: 1.3,
    letterSpacing: 0.2,
  );

  /// ボタン用ラベル
  static const TextStyle button = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0.1,
  );

  /// 大きな数値（KPI カードの値）。マネフォ寄りに少し大きく、強い対比
  static const TextStyle kpiValue = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: V2Colors.textPrimary,
    height: 1.15,
    letterSpacing: -0.5,
    fontFeatures: tabularNums,
  );

  /// テーブル内の数値セル
  static const TextStyle numericCell = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: V2Colors.textBody,
    height: 1.5,
    fontFeatures: tabularNums,
  );

  /// テーブルヘッダー
  static const TextStyle tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: V2Colors.textSecondary,
    height: 1.0,
    letterSpacing: 0.4,
  );
}
