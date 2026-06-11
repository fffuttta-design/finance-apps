import 'dart:ui' show Color;

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

/// 「M/D(曜)」表記。明細の日付列で使う。
String monthDayWeekday(DateTime d) =>
    '${d.month}/${d.day}(${weekdayKanji(d)})';

/// 「M/D」表記（曜日なし）。日付部分だけ通常色で出したいとき用。
String monthDayOnly(DateTime d) => '${d.month}/${d.day}';

/// 「(曜)」表記。曜日だけ色付けしたいとき用。
String weekdayParen(DateTime d) => '(${weekdayKanji(d)})';

/// 曜日に応じた色：土曜=青 / 日曜=赤 / 平日=null（既定色のまま）。
Color? weekendColor(DateTime d) {
  if (d.weekday == DateTime.saturday) return const Color(0xFF2563EB);
  if (d.weekday == DateTime.sunday) return const Color(0xFFDC2626);
  return null;
}
