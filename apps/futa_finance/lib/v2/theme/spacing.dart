/// v2 のスペーシング / サイズ定数。
/// 4 / 8 / 12 / 16 / 24 / 32 のグリッドで統一。
class V2Spacing {
  V2Spacing._();

  // ── 余白スケール ──
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  // ── 角丸（マネフォクラウド寄り：シャープめ）──
  /// 小要素（バッジ・タグ・ピル）
  static const radiusXs = 3.0;
  /// ボタン・チップ
  static const radiusSm = 4.0;
  /// 入力欄・小カード
  static const radiusMd = 6.0;
  /// セクションカード
  static const radiusLg = 8.0;
  /// モーダル・大型ダイアログ
  static const radiusXl = 12.0;

  // ── レイアウト寸法 ──
  /// サイドバー幅
  static const sidebarWidth = 240.0;
  /// 折りたたみ時のサイドバー幅（アイコンのみ）
  static const sidebarCollapsedWidth = 64.0;
  /// トップバー高さ
  static const topbarHeight = 56.0;
  /// メインコンテンツの左右パディング
  static const contentPaddingH = 32.0;
  /// メインコンテンツの上下パディング
  static const contentPaddingV = 24.0;

  // ── テーブル ──
  /// テーブル行の高さ（密度高め）
  static const tableRowHeight = 36.0;
  /// テーブルヘッダーの高さ
  static const tableHeaderHeight = 34.0;
  /// テーブルセルの横パディング
  static const tableCellPaddingH = 12.0;
}
