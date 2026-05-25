/// 円表記フォーマッタ（カンマ区切り、￥プレフィックス）。
String formatYen(int amount, {bool withSign = false}) {
  final isNegative = amount < 0;
  final abs = amount.abs();
  final str = abs.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  if (withSign) {
    return isNegative ? '-¥$str' : '+¥$str';
  }
  return '¥$str';
}

/// 月日（mm/dd）。
String formatMonthDay(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// 曜日（漢字1文字）。
String weekdayKanji(DateTime d) {
  const week = ['月', '火', '水', '木', '金', '土', '日'];
  return week[d.weekday - 1];
}
