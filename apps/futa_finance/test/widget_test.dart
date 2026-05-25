import 'package:flutter_test/flutter_test.dart';

import 'package:futa_finance/utils/formatters.dart';

void main() {
  group('formatYen', () {
    test('カンマ区切りで円表記される', () {
      expect(formatYen(96060), '¥96,060');
      expect(formatYen(10652701), '¥10,652,701');
    });

    test('符号付きフォーマットができる', () {
      expect(formatYen(-96060, withSign: true), '-¥96,060');
      expect(formatYen(85000, withSign: true), '+¥85,000');
    });
  });

  group('formatMonthDay', () {
    test('mm/dd形式で表示される', () {
      expect(formatMonthDay(DateTime(2026, 5, 7)), '05/07');
      expect(formatMonthDay(DateTime(2026, 12, 31)), '12/31');
    });
  });
}
