import 'package:flutter_test/flutter_test.dart';

import 'package:takuharu_finance/main.dart';

void main() {
  testWidgets('たくはるファイナンス起動時にアプリ名が表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const TakuharuFinanceApp());
    expect(find.text('たくはるファイナンス'), findsWidgets);
  });
}
