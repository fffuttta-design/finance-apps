import 'package:flutter/foundation.dart';

/// 全タブ共通の「表示中の月」。
/// どのタブで月を切り替えても、他のタブ（ホーム/支出/収入/資産）にも同じ月が反映される。
class MonthScope {
  MonthScope._();
  static final MonthScope instance = MonthScope._();

  /// 表示中の月（その月の1日）。変更を各タブが listen して再描画する。
  final ValueNotifier<DateTime> notifier =
      ValueNotifier(DateTime(DateTime.now().year, DateTime.now().month));

  DateTime get month => notifier.value;

  /// 月を d か月ぶんずらす（前/次ボタン用）。
  void shift(int d) {
    final m = notifier.value;
    notifier.value = DateTime(m.year, m.month + d);
  }
}
