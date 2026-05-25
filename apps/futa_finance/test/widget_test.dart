import 'package:flutter_test/flutter_test.dart';

import 'package:futa_finance/main.dart';

void main() {
  testWidgets('FutaFinance起動時にアプリ名が表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const FutaFinanceApp());
    expect(find.text('FutaFinance'), findsWidgets);
  });
}
