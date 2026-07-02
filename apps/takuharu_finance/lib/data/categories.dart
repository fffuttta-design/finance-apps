import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// シンプル家計簿用のカテゴリ（大分類フラット）。
class TxCategory {
  final String name;
  final IconData icon;
  final Color color;
  const TxCategory(this.name, this.icon, this.color);
}

/// 支出カテゴリ（可愛い丸アイコン＋パステル）。
const expenseCategories = <TxCategory>[
  TxCategory('食費', Icons.restaurant_rounded, Color(0xFFFF8FA3)),
  TxCategory('外食', Icons.ramen_dining_rounded, Color(0xFFFFB088)),
  TxCategory('日用品', Icons.shopping_basket_rounded, Color(0xFFB8C0FF)),
  TxCategory('デート', Icons.favorite_rounded, Color(0xFFFF6B8A)),
  TxCategory('住居', Icons.home_rounded, Color(0xFF9CD9C5)),
  TxCategory('光熱費', Icons.bolt_rounded, Color(0xFFFFD166)),
  TxCategory('通信', Icons.wifi_rounded, Color(0xFF8ECAE6)),
  TxCategory('交通', Icons.directions_bus_rounded, Color(0xFFA0E7B4)),
  TxCategory('趣味・娯楽', Icons.sports_esports_rounded, Color(0xFFC8A2E0)),
  TxCategory('衣服・美容', Icons.checkroom_rounded, Color(0xFFF7A6C4)),
  TxCategory('医療・健康', Icons.medical_services_rounded, Color(0xFF9FE2D0)),
  TxCategory('交際費', Icons.celebration_rounded, Color(0xFFFFB3C6)),
  TxCategory('特別費', Icons.card_giftcard_rounded, Color(0xFFD0A6F0)),
  TxCategory('その他', Icons.more_horiz_rounded, Color(0xFFC4B5BD)),
];

/// 収入カテゴリ。
const incomeCategories = <TxCategory>[
  TxCategory('給与', Icons.payments_rounded, Color(0xFF34C2A0)),
  TxCategory('賞与', Icons.savings_rounded, Color(0xFF5BC8AF)),
  TxCategory('副収入', Icons.work_rounded, Color(0xFF7FD0B8)),
  TxCategory('お小遣い', Icons.volunteer_activism_rounded, Color(0xFF8FD9C4)),
  TxCategory('その他', Icons.more_horiz_rounded, Color(0xFFA7D9CB)),
];

/// 「個人の食費わく」の対象にできる支出カテゴリ。
/// 食費に加え、レジ袋など食費まわりで一緒に買うことがある日用品も対象にする。
const personalFoodCategories = <String>{'食費', '日用品'};

/// [major] が「個人の食費わく」の対象カテゴリか。
bool isPersonalFoodCategory(String major) =>
    personalFoodCategories.contains(major);

/// カテゴリ名 → 表示用（アイコン/色）。
/// 既定カテゴリに無い名前（ユーザー追加のカスタム）は、名前から安定したパステル色を付ける。
TxCategory categoryFor(String name, {required bool income}) {
  final list = income ? incomeCategories : expenseCategories;
  for (final c in list) {
    if (c.name == name) return c;
  }
  if (name.isEmpty) {
    return const TxCategory('その他', Icons.more_horiz_rounded, AppColors.textSub);
  }
  return TxCategory(name, Icons.label_rounded, _hashColor(name));
}

/// カテゴリ名から安定したパステル色を作る（カスタムカテゴリ用）。
Color _hashColor(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.72).toColor();
}
