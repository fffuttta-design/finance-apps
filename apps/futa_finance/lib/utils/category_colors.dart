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

  /// 手動指定があればそれ、無ければ名前から推測した「それっぽい」既定色。
  /// 色を必ず1つ返すので、画面側でフォールバックを書かなくてよい。
  static Color effective(String major) => resolve(major) ?? autoColor(major);

  // 大カテゴリ名のキーワード → 既定色。上から順に最初に一致したものを採用。
  // （例：食費=オレンジ、交通=ブルー…のように意味に沿った色を自動で割り当てる）
  static const _semantic = <(List<String>, int)>[
    // 住居・固定費・水光熱・通信
    (['固定費', '家賃', '住居', '住宅', '水道', '光熱', '電気', 'ガス', '通信', 'ソフト', 'サブスク'], 0xFF6366F1), // インディゴ
    // 交際・娯楽・趣味
    (['交際', '接待', '会食', '飲み会', '娯楽', '趣味', 'レジャー', 'エンタメ', '遊'], 0xFF8B5CF6), // バイオレット
    // 食費
    (['食費', '食料', '食材', '飲食', 'グルメ', 'ランチ', '外食', 'スーパー', '食'], 0xFFF97316), // オレンジ
    // 美容・衣服
    (['美容', '衣服', '衣類', 'ファッション', '化粧', 'コスメ', '理容', '美'], 0xFFEC4899), // ピンク
    // 医療・健康・保険
    (['病院', '薬', '医療', '健康', 'ヘルス', '診', '保険', '介護'], 0xFF10B981), // エメラルド
    // 交通・旅費・車
    (['交通', '旅費', 'タクシー', '電車', 'バス', '新幹線', 'ガソリン', '車', '移動', '旅行'], 0xFF3B82F6), // ブルー
    // 自己投資・教育・書籍
    (['自己投資', '教育', '学習', '勉強', '書', '新聞', '図書', 'セミナー', '研修', '会費'], 0xFF84CC16), // ライム
    // 生活・日用品・消耗品・雑費
    (['生活', '日用', '消耗', '雑貨', '雑費', '備品', '事務'], 0xFFF59E0B), // アンバー
    // 仕事・経費・事業
    (['経費', '事業', '外注', '仕入', '広告', '会議', '報酬', '手数料', '租税', '公課'], 0xFF06B6D4), // シアン
    // 特別・大物・税・貯蓄
    (['特別', '冠婚', '税金', '貯蓄', '投資', '寄付'], 0xFFEF4444), // レッド
  ];

  /// 名前から「それっぽい」既定色を決める（手動色が無いカテゴリ用）。
  /// キーワードに当てはまればその色、当てはまらなければ名前ハッシュで安定色。
  static Color autoColor(String major) {
    final n = bareMajor(major);
    if (n.isEmpty) return const Color(0xFF9CA3AF);
    for (final e in _semantic) {
      for (final kw in e.$1) {
        if (n.contains(kw)) return Color(e.$2);
      }
    }
    // どのキーワードにも当てはまらない → 名前ハッシュでパレットから安定的に選ぶ。
    var h = 0;
    for (final c in n.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return Color(palette[h % palette.length]);
  }
}
