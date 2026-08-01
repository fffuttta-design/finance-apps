/// 3桁区切りの円表記。
String formatYen(int amount) {
  final neg = amount < 0;
  final s = amount.abs().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return neg ? '-¥$s' : '¥$s';
}

/// 登録日時などを「2026/7/22 14:30」の形で短く表す。
/// 明細に「いつ登録したか」を小さく添えるのに使う。
String formatRegisteredAt(DateTime dt) {
  final d = dt.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.year}/${d.month}/${d.day} $hh:$mm';
}

/// 入力欄のカンマ除去 → int。
int? parseYen(String text) {
  final cleaned = text.trim().replaceAll(',', '').replaceAll('¥', '');
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned);
}
