import 'package:flutter_test/flutter_test.dart';

import 'package:finance_core/finance_core.dart';

void main() {
  test('AppInfo.greetingがアプリ名とタグラインを含む', () {
    const info = AppInfo(name: 'TestApp', tagline: 'テスト用');
    final greeting = info.greeting();
    expect(greeting, contains('TestApp'));
    expect(greeting, contains('テスト用'));
  });
}
