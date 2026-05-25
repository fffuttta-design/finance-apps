import 'package:flutter/material.dart';

/// カテゴリで選べるアイコン一覧。
///
/// 動的IconData作成だとtree-shakingで消える可能性があるため、明示的なMapで定義。
/// キー名(String)を MajorCategory.iconKey に保存する。
const Map<String, IconData> kCategoryIcons = {
  // 一般
  'category': Icons.category,
  'label': Icons.label,
  'folder': Icons.folder,
  'star': Icons.star,
  'favorite': Icons.favorite,
  'flag': Icons.flag,
  'bookmark': Icons.bookmark,

  // お金・支払い
  'savings': Icons.savings,
  'subscriptions': Icons.subscriptions,
  'payments': Icons.payments,
  'event_repeat': Icons.event_repeat,
  'receipt': Icons.receipt,
  'receipt_long': Icons.receipt_long,
  'credit_card': Icons.credit_card,
  'attach_money': Icons.attach_money,
  'currency_yen': Icons.currency_yen,
  'account_balance': Icons.account_balance,
  'account_balance_wallet': Icons.account_balance_wallet,
  'price_check': Icons.price_check,
  'sell': Icons.sell,
  'redeem': Icons.redeem,
  'card_giftcard': Icons.card_giftcard,

  // 仕事・学習
  'work': Icons.work,
  'business': Icons.business,
  'business_center': Icons.business_center,
  'meeting_room': Icons.meeting_room,
  'school': Icons.school,
  'menu_book': Icons.menu_book,
  'book': Icons.book,
  'psychology': Icons.psychology,
  'engineering': Icons.engineering,
  'description': Icons.description,
  'newspaper': Icons.newspaper,

  // 通信・PC
  'wifi': Icons.wifi,
  'phone_iphone': Icons.phone_iphone,
  'phone_android': Icons.phone_android,
  'computer': Icons.computer,
  'laptop_mac': Icons.laptop_mac,
  'desktop_windows': Icons.desktop_windows,
  'cloud': Icons.cloud,
  'storage': Icons.storage,
  'router': Icons.router,
  'memory': Icons.memory,

  // 食事・飲み物
  'restaurant': Icons.restaurant,
  'fastfood': Icons.fastfood,
  'local_pizza': Icons.local_pizza,
  'local_bar': Icons.local_bar,
  'coffee': Icons.coffee,
  'wine_bar': Icons.wine_bar,
  'cake': Icons.cake,
  'icecream': Icons.icecream,
  'ramen_dining': Icons.ramen_dining,
  'lunch_dining': Icons.lunch_dining,
  'dinner_dining': Icons.dinner_dining,
  'bakery_dining': Icons.bakery_dining,

  // 交通
  'directions_car': Icons.directions_car,
  'directions_bus': Icons.directions_bus,
  'train': Icons.train,
  'tram': Icons.tram,
  'subway': Icons.subway,
  'flight': Icons.flight,
  'local_taxi': Icons.local_taxi,
  'directions_walk': Icons.directions_walk,
  'directions_bike': Icons.directions_bike,
  'two_wheeler': Icons.two_wheeler,
  'sailing': Icons.sailing,
  'local_gas_station': Icons.local_gas_station,
  'local_parking': Icons.local_parking,

  // 健康・美容
  'fitness_center': Icons.fitness_center,
  'sports_gymnastics': Icons.sports_gymnastics,
  'spa': Icons.spa,
  'healing': Icons.healing,
  'medical_services': Icons.medical_services,
  'local_hospital': Icons.local_hospital,
  'local_pharmacy': Icons.local_pharmacy,
  'self_improvement': Icons.self_improvement,

  // 家・住居・家具
  'home': Icons.home,
  'apartment': Icons.apartment,
  'house': Icons.house,
  'cottage': Icons.cottage,
  'bed': Icons.bed,
  'shower': Icons.shower,
  'chair': Icons.chair,
  'kitchen': Icons.kitchen,
  'light': Icons.light,
  'cleaning_services': Icons.cleaning_services,

  // 買い物
  'shopping_cart': Icons.shopping_cart,
  'shopping_bag': Icons.shopping_bag,
  'inventory_2': Icons.inventory_2,
  'storefront': Icons.storefront,
  'store': Icons.store,
  'local_grocery_store': Icons.local_grocery_store,
  'local_florist': Icons.local_florist,
  'checkroom': Icons.checkroom,
  'watch': Icons.watch,

  // 趣味・娯楽
  'sports_esports': Icons.sports_esports,
  'movie': Icons.movie,
  'theaters': Icons.theaters,
  'music_note': Icons.music_note,
  'headphones': Icons.headphones,
  'mic': Icons.mic,
  'camera_alt': Icons.camera_alt,
  'palette': Icons.palette,
  'brush': Icons.brush,
  'sports_basketball': Icons.sports_basketball,
  'sports_soccer': Icons.sports_soccer,
  'sports_tennis': Icons.sports_tennis,
  'sports_baseball': Icons.sports_baseball,
  'pool': Icons.pool,
  'casino': Icons.casino,
  'extension': Icons.extension,
  'toys': Icons.toys,

  // 旅行・自然
  'beach_access': Icons.beach_access,
  'park': Icons.park,
  'forest': Icons.forest,
  'landscape': Icons.landscape,
  'luggage': Icons.luggage,
  'hotel': Icons.hotel,
  'map': Icons.map,
  'place': Icons.place,
  'public': Icons.public,

  // 動物・家族
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'family_restroom': Icons.family_restroom,
  'people': Icons.people,
  'group': Icons.group,
  'celebration': Icons.celebration,
  'cake_outlined': Icons.cake_outlined,

  // その他
  'lightbulb': Icons.lightbulb,
  'help_outline': Icons.help_outline,
  'more_horiz': Icons.more_horiz,
  'volunteer_activism': Icons.volunteer_activism,
  'campaign': Icons.campaign,
  'event': Icons.event,
  'gavel': Icons.gavel,
  'umbrella': Icons.umbrella,
  'security': Icons.security,
  'shield': Icons.shield,
};

/// keyに対応するIconDataを返す。null/不明なら default の category アイコン。
IconData iconForKey(String? key) {
  if (key == null) return Icons.category;
  return kCategoryIcons[key] ?? Icons.category;
}
