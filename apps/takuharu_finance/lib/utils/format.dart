/// 3桁区切りの円表記。
String formatYen(int amount) {
  final neg = amount < 0;
  final s = amount.abs().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return neg ? '-¥$s' : '¥$s';
}

/// 入力欄のカンマ除去 → int。
int? parseYen(String text) {
  final cleaned = text.trim().replaceAll(',', '').replaceAll('¥', '');
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned);
}
