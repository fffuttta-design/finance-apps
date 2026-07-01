/// 日本の祝日カレンダー（2020年以降の令和の祝日に対応）。
///
/// カード引き落とし日が土日祝のとき翌営業日に送るために使う。
/// 固定祝日＋ハッピーマンデー＋春分/秋分（近似式）＋振替休日＋国民の休日を算出する。
/// ※2020年以降を想定（天皇誕生日=2/23、山の日=8/11）。日付が1日ズレても影響は
///   「引落日が1日ずれる」程度で金額には影響しない。
class JpHolidays {
  JpHolidays._();

  static final Map<int, Set<String>> _cache = {};

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// 春分の日（1980〜2099に有効な近似式）。
  static int _springDay(int y) =>
      (20.8431 + 0.242194 * (y - 1980) - ((y - 1980) ~/ 4)).floor();

  /// 秋分の日（1980〜2099に有効な近似式）。
  static int _autumnDay(int y) =>
      (23.2488 + 0.242194 * (y - 1980) - ((y - 1980) ~/ 4)).floor();

  /// その月の第[nth]月曜日。
  static DateTime _nthMonday(int y, int m, int nth) {
    var d = DateTime(y, m, 1);
    while (d.weekday != DateTime.monday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(Duration(days: 7 * (nth - 1)));
  }

  static Set<String> _forYear(int y) {
    final cached = _cache[y];
    if (cached != null) return cached;

    final days = <DateTime>{
      DateTime(y, 1, 1), // 元日
      DateTime(y, 2, 11), // 建国記念の日
      DateTime(y, 2, 23), // 天皇誕生日（2020〜）
      DateTime(y, 4, 29), // 昭和の日
      DateTime(y, 5, 3), // 憲法記念日
      DateTime(y, 5, 4), // みどりの日
      DateTime(y, 5, 5), // こどもの日
      DateTime(y, 8, 11), // 山の日
      DateTime(y, 11, 3), // 文化の日
      DateTime(y, 11, 23), // 勤労感謝の日
      _nthMonday(y, 1, 2), // 成人の日
      _nthMonday(y, 7, 3), // 海の日
      _nthMonday(y, 9, 3), // 敬老の日
      _nthMonday(y, 10, 2), // スポーツの日
      DateTime(y, 3, _springDay(y)), // 春分の日
      DateTime(y, 9, _autumnDay(y)), // 秋分の日
    };

    // 国民の休日：祝日に挟まれた平日（日曜以外）。主に敬老の日〜秋分の日の谷。
    final between = <DateTime>{};
    for (final h in days) {
      final mid = h.add(const Duration(days: 1));
      final after = h.add(const Duration(days: 2));
      if (days.contains(after) &&
          !days.contains(mid) &&
          mid.weekday != DateTime.sunday) {
        between.add(mid);
      }
    }
    days.addAll(between);

    // 振替休日：日曜と重なった祝日は、次の（祝日でない）日を休日にする。
    final subs = <DateTime>{};
    for (final h in {...days}) {
      if (h.weekday == DateTime.sunday) {
        var n = h.add(const Duration(days: 1));
        while (days.contains(n) || subs.contains(n)) {
          n = n.add(const Duration(days: 1));
        }
        subs.add(n);
      }
    }
    days.addAll(subs);

    final set = days.map(_key).toSet();
    _cache[y] = set;
    return set;
  }

  /// [d] が祝日か。
  static bool isHoliday(DateTime d) =>
      _forYear(d.year).contains(_key(DateTime(d.year, d.month, d.day)));

  /// [d] が営業日（土日でも祝日でもない）か。
  static bool isBusinessDay(DateTime d) =>
      d.weekday != DateTime.saturday &&
      d.weekday != DateTime.sunday &&
      !isHoliday(d);

  /// [d] が営業日ならそのまま、土日祝なら次の営業日を返す（時刻は切り捨て）。
  static DateTime nextBusinessDay(DateTime d) {
    var x = DateTime(d.year, d.month, d.day);
    while (!isBusinessDay(x)) {
      x = x.add(const Duration(days: 1));
    }
    return x;
  }
}
