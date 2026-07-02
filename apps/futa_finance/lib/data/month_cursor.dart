import 'package:flutter/foundation.dart';

/// タブ横断で共有する「表示中の月」。
///
/// ホーム/支出/収入/業績/資産の各タブで共有する。初期値にこのカーソルを使い、
/// 月を変えたら書き戻す。さらに [ChangeNotifier] として変更を通知するので、
/// keep-alive で生かされたままのタブ（下タブ/PageView）でも、購読していれば
/// 月変更に追従できる（6月を見ている状態で別タブへ行っても6月のまま維持）。
class MonthCursor extends ChangeNotifier {
  MonthCursor._();
  static final MonthCursor instance = MonthCursor._();

  DateTime _month = _thisMonth();

  static DateTime _thisMonth() {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  /// 現在の共有月（day は常に 1）。
  DateTime get month => _month;

  /// 月をセット（年月だけ保持）。変化があれば購読者へ通知。
  set month(DateTime m) {
    final nm = DateTime(m.year, m.month);
    if (nm == _month) return;
    _month = nm;
    notifyListeners();
  }
}
