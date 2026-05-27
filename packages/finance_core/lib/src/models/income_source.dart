import 'dart:convert';

/// 収入の発生サイクル。
enum IncomeCycle {
  /// 都度（不定期）。
  oneTime,

  /// 毎月。
  monthly,

  /// 四半期ごと。
  quarterly,

  /// 半年ごと。
  semiAnnually,

  /// 毎年。
  annually,
}

/// 収入マスタ。継続/単発の収入源を登録しておき、入金時に呼び出して使う。
class IncomeSource {
  final String id;

  /// 収入源の名称（例: "Aクライアント月額顧問", "B社SEO代行"）。
  final String name;

  /// 取引先（例: "株式会社A"）。
  final String? clientName;

  /// 想定金額（円）。記録時はこの値を初期表示する。
  final int? expectedAmount;

  /// 発生サイクル。
  final IncomeCycle cycle;

  /// 入金予定日（cycle が monthly の場合の "毎月X日" など）。
  /// 1〜31 の整数で月内日付を表す。null なら不定。
  final int? dayOfMonth;

  /// 備考。
  final String? memo;

  /// アーカイブ済みフラグ。
  /// true の場合は通常一覧に出さない（「もう取引しない収入源」を非表示にする運用）。
  /// 過去取引との紐付けは残るため、データは削除されない。
  final bool archived;

  const IncomeSource({
    required this.id,
    required this.name,
    this.clientName,
    this.expectedAmount,
    this.cycle = IncomeCycle.monthly,
    this.dayOfMonth,
    this.memo,
    this.archived = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'clientName': clientName,
        'expectedAmount': expectedAmount,
        'cycle': cycle.name,
        'dayOfMonth': dayOfMonth,
        'memo': memo,
        'archived': archived,
      };

  factory IncomeSource.fromJson(Map<String, dynamic> j) => IncomeSource(
        id: j['id'] as String,
        name: j['name'] as String,
        clientName: j['clientName'] as String?,
        expectedAmount: j['expectedAmount'] as int?,
        cycle: IncomeCycle.values.firstWhere(
          (c) => c.name == (j['cycle'] as String? ?? 'monthly'),
          orElse: () => IncomeCycle.monthly,
        ),
        dayOfMonth: j['dayOfMonth'] as int?,
        memo: j['memo'] as String?,
        archived: j['archived'] as bool? ?? false,
      );

  IncomeSource copyWith({
    String? name,
    String? clientName,
    int? expectedAmount,
    IncomeCycle? cycle,
    int? dayOfMonth,
    String? memo,
    bool? archived,
  }) =>
      IncomeSource(
        id: id,
        name: name ?? this.name,
        clientName: clientName ?? this.clientName,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        cycle: cycle ?? this.cycle,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        memo: memo ?? this.memo,
        archived: archived ?? this.archived,
      );

  String get cycleLabel {
    switch (cycle) {
      case IncomeCycle.oneTime:
        return '都度';
      case IncomeCycle.monthly:
        return '毎月';
      case IncomeCycle.quarterly:
        return '四半期';
      case IncomeCycle.semiAnnually:
        return '半年';
      case IncomeCycle.annually:
        return '毎年';
    }
  }
}

/// 収入マスタの集合（永続化用）。
class IncomeSourceConfig {
  final List<IncomeSource> sources;

  const IncomeSourceConfig({required this.sources});

  factory IncomeSourceConfig.empty() => const IncomeSourceConfig(sources: []);

  String toJsonString() => jsonEncode({
        'sources': sources.map((s) => s.toJson()).toList(),
      });

  factory IncomeSourceConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return IncomeSourceConfig(
      sources: (json['sources'] as List)
          .map((s) => IncomeSource.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  IncomeSourceConfig copyWith({List<IncomeSource>? sources}) =>
      IncomeSourceConfig(sources: sources ?? this.sources);
}
