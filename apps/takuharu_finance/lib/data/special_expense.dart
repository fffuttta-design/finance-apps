import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 特別支出の種類。
/// 旅行・引っ越しのように「日をまたいで1つの出来事にぶら下がる出費」を束ねる箱の分類。
class SpecialExpenseKind {
  final String name;
  final IconData icon;
  final Color color;
  const SpecialExpenseKind(this.name, this.icon, this.color);
}

/// 選べる種類（先頭が既定）。増やすときはここに1行足すだけでよい。
const specialExpenseKinds = <SpecialExpenseKind>[
  SpecialExpenseKind('旅行', Icons.flight_takeoff_rounded, Color(0xFF8ECAE6)),
  SpecialExpenseKind('おでかけ', Icons.directions_walk_rounded, Color(0xFFA0E7B4)),
  SpecialExpenseKind('ライブ・イベント', Icons.celebration_rounded, Color(0xFFFFB3C6)),
  SpecialExpenseKind('引っ越し', Icons.local_shipping_rounded, Color(0xFFFFD166)),
  SpecialExpenseKind('家電・家具', Icons.chair_rounded, Color(0xFFB8C0FF)),
  SpecialExpenseKind('冠婚葬祭', Icons.card_giftcard_rounded, Color(0xFFD0A6F0)),
  SpecialExpenseKind('医療', Icons.medical_services_rounded, Color(0xFF9FE2D0)),
  SpecialExpenseKind('その他', Icons.more_horiz_rounded, Color(0xFFC4B5BD)),
];

/// [name] の種類を返す。知らない名前でも落とさず「その他」相当で返す。
SpecialExpenseKind kindOf(String name) {
  for (final k in specialExpenseKinds) {
    if (k.name == name) return k;
  }
  return SpecialExpenseKind(name, Icons.more_horiz_rounded, AppColors.pink);
}

/// 特別支出（旅行・引っ越しなど、まとまった1つの出費）。
///
/// これ自体は金額を持たない。金額は取引側の `specialExpenseId` でぶら下がる。
/// 月をまたいでも1つの箱として合計・精算できるようにするための入れ物。
class SpecialExpense {
  final String id;

  /// 表示名（例「仙台・松島旅行」）。
  final String name;

  /// 種類（[specialExpenseKinds] の name）。
  final String kind;

  /// 期間。終わりが未定なら [end] は null。
  /// 取引を登録するとき、この期間に入っていれば自動で候補に出す。
  final DateTime start;
  final DateTime? end;

  /// 精算を済ませたか。true にすると一覧では「済んだもの」に落ちる。
  final bool settled;

  final String? memo;
  final DateTime? createdAt;

  const SpecialExpense({
    required this.id,
    required this.name,
    required this.kind,
    required this.start,
    this.end,
    this.settled = false,
    this.memo,
    this.createdAt,
  });

  /// 期間の終わり（未指定なら開始日と同じ日とみなす）。
  DateTime get endOrStart => end ?? start;

  /// [d] がこの特別支出の期間に入っているか（日付だけで判定）。
  bool covers(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(endOrStart.year, endOrStart.month, endOrStart.day);
    return !day.isBefore(s) && !day.isAfter(e);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'settled': settled,
        'memo': memo,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory SpecialExpense.fromJson(Map<String, dynamic> j) => SpecialExpense(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        kind: j['kind'] as String? ?? specialExpenseKinds.first.name,
        start: DateTime.parse(j['start'] as String),
        end: j['end'] != null ? DateTime.tryParse(j['end'] as String) : null,
        settled: j['settled'] as bool? ?? false,
        memo: j['memo'] as String?,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
      );

  SpecialExpense copyWith({
    String? name,
    String? kind,
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    bool? settled,
    String? memo,
  }) =>
      SpecialExpense(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        settled: settled ?? this.settled,
        memo: memo ?? this.memo,
        createdAt: createdAt,
      );
}
