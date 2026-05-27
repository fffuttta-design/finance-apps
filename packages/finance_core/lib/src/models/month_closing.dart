import 'dart:convert';

/// 1ヶ月分の締めステータス。
class MonthClosing {
  /// 'YYYY-MM' キー。
  final String yearMonth;

  /// この月でチェック済みのチェックリスト項目ID一覧。
  final List<String> checkedItemIds;

  /// 締めた日時。null なら未締め。
  final DateTime? closedAt;

  /// 締め時点の支出合計（スナップショット、後で確認用）。
  final int? closedTotalExpense;

  /// 締め時点の収入合計。
  final int? closedTotalIncome;

  const MonthClosing({
    required this.yearMonth,
    this.checkedItemIds = const [],
    this.closedAt,
    this.closedTotalExpense,
    this.closedTotalIncome,
  });

  bool get isClosed => closedAt != null;
  bool isChecked(String itemId) => checkedItemIds.contains(itemId);

  static String monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'yearMonth': yearMonth,
        'checkedItemIds': checkedItemIds,
        'closedAt': closedAt?.toIso8601String(),
        'closedTotalExpense': closedTotalExpense,
        'closedTotalIncome': closedTotalIncome,
      };

  factory MonthClosing.fromJson(Map<String, dynamic> j) => MonthClosing(
        yearMonth: j['yearMonth'] as String,
        checkedItemIds:
            (j['checkedItemIds'] as List?)?.cast<String>() ?? const [],
        closedAt: j['closedAt'] == null
            ? null
            : DateTime.parse(j['closedAt'] as String),
        closedTotalExpense: j['closedTotalExpense'] as int?,
        closedTotalIncome: j['closedTotalIncome'] as int?,
      );

  MonthClosing copyWith({
    List<String>? checkedItemIds,
    DateTime? closedAt,
    bool clearClosedAt = false,
    int? closedTotalExpense,
    int? closedTotalIncome,
  }) =>
      MonthClosing(
        yearMonth: yearMonth,
        checkedItemIds: checkedItemIds ?? this.checkedItemIds,
        closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
        closedTotalExpense: closedTotalExpense ?? this.closedTotalExpense,
        closedTotalIncome: closedTotalIncome ?? this.closedTotalIncome,
      );
}

class MonthClosingConfig {
  final List<MonthClosing> closings;

  const MonthClosingConfig({required this.closings});

  factory MonthClosingConfig.empty() =>
      const MonthClosingConfig(closings: []);

  MonthClosing? forMonth(int year, int month) {
    final key = MonthClosing.monthKey(year, month);
    for (final c in closings) {
      if (c.yearMonth == key) return c;
    }
    return null;
  }

  MonthClosingConfig upsert(MonthClosing c) {
    final list = closings.where((x) => x.yearMonth != c.yearMonth).toList();
    list.add(c);
    list.sort((a, b) => a.yearMonth.compareTo(b.yearMonth));
    return MonthClosingConfig(closings: list);
  }

  String toJsonString() => jsonEncode(
      {'closings': closings.map((c) => c.toJson()).toList()});

  factory MonthClosingConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return MonthClosingConfig(
      closings: (json['closings'] as List)
          .map((c) => MonthClosing.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
