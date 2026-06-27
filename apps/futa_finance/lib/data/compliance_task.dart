import 'dart:convert';

/// 手続き・届出の分類。
enum ComplianceCategory { tax, socialInsurance, laborInsurance, corporate, other }

extension ComplianceCategoryX on ComplianceCategory {
  String get label {
    switch (this) {
      case ComplianceCategory.tax:
        return '税務';
      case ComplianceCategory.socialInsurance:
        return '社会保険';
      case ComplianceCategory.laborInsurance:
        return '労働保険';
      case ComplianceCategory.corporate:
        return '登記・会社';
      case ComplianceCategory.other:
        return 'その他';
    }
  }

  String get emoji {
    switch (this) {
      case ComplianceCategory.tax:
        return '🧾';
      case ComplianceCategory.socialInsurance:
        return '🏥';
      case ComplianceCategory.laborInsurance:
        return '👷';
      case ComplianceCategory.corporate:
        return '🏢';
      case ComplianceCategory.other:
        return '📌';
    }
  }
}

/// 手続きの繰り返し方。
enum ComplianceRecurrence { yearly, monthly, asNeeded }

extension ComplianceRecurrenceX on ComplianceRecurrence {
  String get label {
    switch (this) {
      case ComplianceRecurrence.yearly:
        return '毎年';
      case ComplianceRecurrence.monthly:
        return '毎月';
      case ComplianceRecurrence.asNeeded:
        return '随時';
    }
  }
}

/// 会社の手続き・届出1件（算定基礎届・年度更新・申告期限など）。
///
/// お金（税金・保険マスタ＝BudgetItem）とは別で、「いつ・何をやるか」の
/// 締切・TODOを管理する。資金には影響しない。
class ComplianceTask {
  final String id;
  final String name;
  final ComplianceCategory category;
  final ComplianceRecurrence recurrence;

  /// 毎年：期限の月(1-12)。毎月/随時では未使用。
  final int? month;

  /// 期限日(1-31)。毎月は毎月この日、随時では未使用。
  final int? day;

  final String? note;

  /// 参考URL（任意）。
  final String? url;

  /// 完了済みの年（毎年タスク用。チェックすると次回が翌年送りになる）。
  final List<int> doneYears;

  const ComplianceTask({
    required this.id,
    required this.name,
    required this.category,
    required this.recurrence,
    this.month,
    this.day,
    this.note,
    this.url,
    this.doneYears = const [],
  });

  /// 今日基準の次回期限日。随時は null。
  DateTime? nextDueFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (recurrence) {
      case ComplianceRecurrence.asNeeded:
        return null;
      case ComplianceRecurrence.monthly:
        final d = day ?? lastDayOfMonth(now.year, now.month);
        var date = DateTime(now.year, now.month, _clampDay(now.year, now.month, d));
        if (date.isBefore(today)) {
          final ny = now.month == 12 ? now.year + 1 : now.year;
          final nm = now.month == 12 ? 1 : now.month + 1;
          date = DateTime(ny, nm, _clampDay(ny, nm, d));
        }
        return date;
      case ComplianceRecurrence.yearly:
        final m = month ?? 1;
        final d = day ?? lastDayOfMonth(now.year, m);
        var y = now.year;
        // 今年分が完了済みなら翌年へ。
        if (doneYears.contains(y)) y = now.year + 1;
        var date = DateTime(y, m, _clampDay(y, m, d));
        if (date.isBefore(today) && !doneYears.contains(y)) {
          y += 1;
          date = DateTime(y, m, _clampDay(y, m, d));
        }
        return date;
    }
  }

  static int lastDayOfMonth(int y, int m) => DateTime(y, m + 1, 0).day;
  static int _clampDay(int y, int m, int d) {
    final last = lastDayOfMonth(y, m);
    return d > last ? last : d;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'recurrence': recurrence.name,
        'month': month,
        'day': day,
        'note': note,
        'url': url,
        'doneYears': doneYears,
      };

  factory ComplianceTask.fromJson(Map<String, dynamic> j) => ComplianceTask(
        id: j['id'] as String,
        name: j['name'] as String,
        category: ComplianceCategory.values.firstWhere(
          (c) => c.name == (j['category'] as String? ?? 'other'),
          orElse: () => ComplianceCategory.other,
        ),
        recurrence: ComplianceRecurrence.values.firstWhere(
          (r) => r.name == (j['recurrence'] as String? ?? 'yearly'),
          orElse: () => ComplianceRecurrence.yearly,
        ),
        month: j['month'] as int?,
        day: j['day'] as int?,
        note: j['note'] as String?,
        url: j['url'] as String?,
        doneYears:
            (j['doneYears'] as List?)?.map((e) => e as int).toList() ?? const [],
      );

  ComplianceTask copyWith({
    String? name,
    ComplianceCategory? category,
    ComplianceRecurrence? recurrence,
    int? month,
    int? day,
    String? note,
    String? url,
    List<int>? doneYears,
    bool clearNote = false,
    bool clearUrl = false,
    bool clearMonth = false,
    bool clearDay = false,
  }) =>
      ComplianceTask(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        recurrence: recurrence ?? this.recurrence,
        month: clearMonth ? null : (month ?? this.month),
        day: clearDay ? null : (day ?? this.day),
        note: clearNote ? null : (note ?? this.note),
        url: clearUrl ? null : (url ?? this.url),
        doneYears: doneYears ?? this.doneYears,
      );
}

/// ComplianceTask の集合。永続化単位。
class ComplianceTasksConfig {
  final List<ComplianceTask> tasks;

  const ComplianceTasksConfig({required this.tasks});

  factory ComplianceTasksConfig.empty() =>
      const ComplianceTasksConfig(tasks: []);

  String toJsonString() =>
      jsonEncode({'tasks': tasks.map((t) => t.toJson()).toList()});

  factory ComplianceTasksConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return ComplianceTasksConfig(
      tasks: (json['tasks'] as List)
          .map((t) => ComplianceTask.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}
