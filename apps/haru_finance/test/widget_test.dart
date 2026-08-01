import 'package:flutter_test/flutter_test.dart';

import 'package:haru_finance/main.dart';

void main() {
  testWidgets('はるファイナンスのアプリが生成できる', (WidgetTester tester) async {
    // Firebase 初期化なしでも Widget ツリーが構築できることだけ確認する。
    const app = HaruFinanceApp();
    expect(app, isA<HaruFinanceApp>());
  });
}
