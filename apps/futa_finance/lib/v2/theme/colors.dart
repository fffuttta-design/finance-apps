import 'package:flutter/material.dart';

/// v2 デザインシステムのカラーパレット。
/// Linear / Notion / Stripe / freee の良いとこ取り、ライト固定。
///
/// 命名規則: `Vxxx` プレフィックスで v1 のリテラル色と衝突しない。
class V2Colors {
  V2Colors._();

  // ── 背景 / サーフェス ──────────────────────────
  /// アプリ全体の背景（マネフォ寄りに寒色淡め）
  static const bg = Color(0xFFF5F7FA);

  /// カード・パネルの背景
  static const surface = Color(0xFFFFFFFF);

  /// 軽く沈ませたサーフェス（ホバー / 選択前の段違い）
  static const surfaceMuted = Color(0xFFF8FAFC);

  /// サイドバー背景（マネフォクラウド寄り：深いネイビー）
  static const sidebar = Color(0xFF1F3A5F);

  /// サイドバー上のテキスト（白系）
  static const sidebarText = Color(0xFFE5E9EF);

  /// サイドバー上のミュートテキスト
  static const sidebarTextMuted = Color(0xFF8FA3BD);

  /// サイドバーのホバー背景
  static const sidebarHover = Color(0xFF2A4A75);

  /// サイドバーの選択中背景
  static const sidebarSelected = Color(0xFF345C8E);

  /// サイドバー内の区切り線
  static const sidebarDivider = Color(0xFF345C8E);

  /// トップバー背景
  static const topbar = Color(0xFFFFFFFF);

  // ── 境界線 / 区切り ───────────────────────────
  /// 既定の境界線（カード枠など）。マネフォは枠線控えめ → 影で立体感
  static const border = Color(0xFFE8ECF1);

  /// 強めの境界線（選択行など）
  static const borderStrong = Color(0xFFCBD5E1);

  /// 薄い区切り線（テーブル行間など）
  static const divider = Color(0xFFF1F5F9);

  /// カードの薄いソフトシャドウの色（黒の透明度を抑えた色）
  static const shadow = Color(0x14101828);

  // ── テキスト ──────────────────────────────
  /// 最も濃い見出し系テキスト（slate-900 相当）
  static const textPrimary = Color(0xFF0F172A);

  /// 通常テキスト（slate-700 相当）
  static const textBody = Color(0xFF334155);

  /// セカンダリテキスト（slate-500 相当）
  static const textSecondary = Color(0xFF64748B);

  /// ミュートテキスト（slate-400 相当）
  static const textMuted = Color(0xFF94A3B8);

  /// 反転テキスト（ボタンなど）
  static const textOnAccent = Color(0xFFFFFFFF);

  // ── アクセント ────────────────────────────
  /// アクセント（事業モード / 主操作）。マネフォクラウドに近い深い青
  static const accent = Color(0xFF1976D2);

  /// アクセント弱（ホバー / 選択背景）
  static const accentSoft = Color(0xFFE3F2FD);

  /// アクセント枠線（フォーカスリングなど）
  static const accentBorder = Color(0xFF90CAF9);

  /// 個人モードのアクセント（マネフォ寄りはオレンジでも違和感ないが、
  /// 親しみのあるサンセット系に寄せる）
  static const accentPersonal = Color(0xFFEA580C);
  static const accentPersonalSoft = Color(0xFFFFEDD5);

  // ── カテゴリ別バッジ色（KPI アイコン等で使う）──
  /// 資産系（青）
  static const badgeBlue = Color(0xFF3B82F6);
  static const badgeBlueSoft = Color(0xFFDBEAFE);

  /// 収入系（緑）。accent とは別の色（収支表現用）
  static const badgeGreen = Color(0xFF10A37F);
  static const badgeGreenSoft = Color(0xFFE8F8F0);

  /// 支出系（赤）
  static const badgeRed = Color(0xFFEF4444);
  static const badgeRedSoft = Color(0xFFFEE2E2);

  /// 投資・貯蓄系（紫）
  static const badgePurple = Color(0xFF8B5CF6);
  static const badgePurpleSoft = Color(0xFFEDE9FE);

  /// 警告・見込み系（黄）
  static const badgeAmber = Color(0xFFF59E0B);
  static const badgeAmberSoft = Color(0xFFFEF3C7);

  // ── セマンティック（収支） ────────────────
  /// 黒字 / 入金 / 成功（emerald-500）
  static const positive = Color(0xFF10B981);
  static const positiveSoft = Color(0xFFD1FAE5);

  /// 赤字 / 支出 / 危険（red-500）
  static const negative = Color(0xFFEF4444);
  static const negativeSoft = Color(0xFFFEE2E2);

  /// 注意 / 見込み（amber-500）
  static const warning = Color(0xFFF59E0B);
  static const warningSoft = Color(0xFFFEF3C7);

  /// 情報 / リンク（sky-500）
  static const info = Color(0xFF0EA5E9);
  static const infoSoft = Color(0xFFE0F2FE);

  // ── ホバー / フォーカスステート ────────────
  /// 行 / ボタンの hover 背景
  static const hover = Color(0xFFF1F5F9);

  /// 選択中の行背景
  static const selected = Color(0xFFEEF2FF);

  /// フォーカスリング
  static const focusRing = Color(0xFF1976D2);
}
