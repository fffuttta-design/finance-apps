/// タブ横断で共有する「表示中の月」。
///
/// ホーム/支出/収入/業績/資産の各タブは切替のたびに作り直されるため、
/// 各画面が個別に「今月」で初期化すると、タブを移動するたびに月がリセットされる。
/// この共有カーソルを初期値に使い、月を変えたら書き戻すことで、
/// 6月を見ている状態で別タブへ行っても6月のまま維持される。
class MonthCursor {
  MonthCursor._();
  static final MonthCursor instance = MonthCursor._();

  DateTime _month = _thisMonth();

  static DateTime _thisMonth() {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  /// 現在の共有月（day は常に 1）。
  DateTime get month => _month;

  /// 月をセット（年月だけ保持）。
  set month(DateTime m) => _month = DateTime(m.year, m.month);
}
