import 'package:flutter/material.dart';

import '../widgets/brand_logo.dart';
import 'category_icons.dart';

/// カテゴリで使える絵文字パレット（カテゴリ向けに厳選）。
const List<String> kEmojiPalette = [
  // 住居・建物
  '🏠', '🏢', '🏥', '🏪', '🏫', '🏦', '🏛️', '🏗️',
  // 食事
  '🍔', '🍕', '🍣', '🍜', '🍱', '🍰', '🍩', '🍫',
  '🥗', '🥩', '🍷', '🍺', '☕', '🍵', '🧃', '🍶',
  // 交通
  '🚗', '🚕', '🚌', '🚂', '🚃', '✈️', '🚲', '🛵', '⛽', '🅿️',
  // 衣服・美容
  '👔', '👗', '👞', '👠', '👜', '👓', '💍', '💄', '🧴', '💅',
  // 健康・医療
  '💊', '🩺', '🦷', '💉', '🏃', '💪', '🧘', '⛑️',
  // 教育・書籍
  '📚', '📖', '✏️', '🎓', '📝', '📓', '📰',
  // 仕事・金
  '💼', '📊', '💰', '💳', '🪙', '💸', '🧾', '🏷️',
  // 娯楽・趣味
  '🎮', '🎬', '🎵', '🎤', '📷', '🎨', '🖌️', '🎲',
  '⚽', '🏀', '🎾', '🎿', '🎣',
  // 公共料金・設備
  '⚡', '💧', '🔥', '📱', '📞', '📡', '📺', '💡',
  // 贈り物・イベント
  '🎁', '🎂', '🌹', '💝', '🎉', '🎊', '🎀',
  // ペット・自然
  '🐶', '🐱', '🐰', '🐦', '🐠', '🌸', '🌳', '🌊',
  // 旅行
  '🏖️', '⛰️', '🗻', '🏝️', '🧳', '🗺️',
  // 家族・人
  '👶', '👨‍👩‍👧', '👫', '🧑‍🤝‍🧑',
  // 重要・特別
  '⭐', '✨', '🔔', '❤️', '🔥', '⚠️', '🆘', '📌',
  // その他
  '🪑', '🛌', '🛁', '🧹', '🧺', '🧴', '🧼',
  '🛒', '📦', '🎯', '🏆', '🪞', '🪥', '🔑', '📿',
];

/// 表示用ウィジェット。iconKey が:
/// - http(s):// から始まる文字列 → 画像URL扱い（BrandLogoで表示・キャッシュ対応）
/// - kCategoryIcons に登録された Material アイコン名 → Icon
/// - 絵文字（または不明文字列）→ Text として表示
/// - null → デフォルトの Icon(category)
Widget categoryIconWidget(
  String? iconKey, {
  double size = 18,
  Color? color,
}) {
  if (iconKey == null || iconKey.isEmpty) {
    return Icon(Icons.category, size: size, color: color);
  }
  // 画像URL（http/httpsで始まる場合）
  if (iconKey.startsWith('http://') || iconKey.startsWith('https://')) {
    return BrandLogo(
      iconUrl: iconKey,
      size: size,
      borderRadius: 4,
      // 画像読込前/失敗時のフォールバックは Icons.category
      fallbackIcon: Icons.category,
      fallbackBgColor: const Color(0xFFF3F4F6),
      fallbackFgColor: color ?? const Color(0xFF6B7280),
    );
  }
  if (kCategoryIcons.containsKey(iconKey)) {
    return Icon(kCategoryIcons[iconKey]!, size: size, color: color);
  }
  // 絵文字想定（Material Iconに一致しない場合）
  return Text(
    iconKey,
    style: TextStyle(fontSize: size, height: 1),
  );
}
