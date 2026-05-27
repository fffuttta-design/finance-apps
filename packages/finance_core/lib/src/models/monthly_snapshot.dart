import 'dart:convert';

/// 月の1日時点で記録した残高スナップショット。
///
/// 推定残高 = initialBalance + (当月収入) - (当月支出) を算出するための基準値。
/// 月末/月初にリマインドして実測値で更新する運用想定。
class MonthlySnapshot {
  /// 'YYYY-MM' 形式の月キー。
  final String yearMonth;

  /// その月の1日時点の銀行/現金/電子マネー合算残高（円）。
  final int initialBalance;

  /// 記録日時。
  final DateTime recordedAt;

  const MonthlySnapshot({
    required this.yearMonth,
    required this.initialBalance,
    required this.recordedAt,
  });

  /// (year, month) → 'YYYY-MM' キー。
  static String monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'yearMonth': yearMonth,
        'initialBalance': initialBalance,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory MonthlySnapshot.fromJson(Map<String, dynamic> j) =>
      MonthlySnapshot(
        yearMonth: j['yearMonth'] as String,
        initialBalance: j['initialBalance'] as int,
        recordedAt: DateTime.parse(j['recordedAt'] as String),
      );

  MonthlySnapshot copyWith({int? initialBalance}) => MonthlySnapshot(
        yearMonth: yearMonth,
        initialBalance: initialBalance ?? this.initialBalance,
        recordedAt: recordedAt,
      );
}

/// スナップショットの一覧（永続化用）。
class MonthlySnapshotConfig {
  final List<MonthlySnapshot> snapshots;

  const MonthlySnapshotConfig({required this.snapshots});

  factory MonthlySnapshotConfig.empty() =>
      const MonthlySnapshotConfig(snapshots: []);

  /// 指定月のスナップショットを返す（無ければ null）。
  MonthlySnapshot? forMonth(int year, int month) {
    final key = MonthlySnapshot.monthKey(year, month);
    for (final s in snapshots) {
      if (s.yearMonth == key) return s;
    }
    return null;
  }

  /// upsert: 同じ yearMonth があれば置換、なければ追加。
  MonthlySnapshotConfig upsert(MonthlySnapshot s) {
    final list =
        snapshots.where((x) => x.yearMonth != s.yearMonth).toList();
    list.add(s);
    list.sort((a, b) => a.yearMonth.compareTo(b.yearMonth));
    return MonthlySnapshotConfig(snapshots: list);
  }

  String toJsonString() =>
      jsonEncode({'snapshots': snapshots.map((s) => s.toJson()).toList()});

  factory MonthlySnapshotConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return MonthlySnapshotConfig(
      snapshots: (json['snapshots'] as List)
          .map((s) => MonthlySnapshot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
