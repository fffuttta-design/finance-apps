/// プランニングの種類（リスト）。
enum PlanKind { todo, place, shop }

extension PlanKindX on PlanKind {
  /// リスト見出し。
  String get label {
    switch (this) {
      case PlanKind.todo:
        return 'やりたいこと';
      case PlanKind.place:
        return '行きたい場所';
      case PlanKind.shop:
        return '行きたいお店';
    }
  }

  /// チェック済みの呼び方。
  String get doneLabel {
    switch (this) {
      case PlanKind.todo:
        return '完了';
      case PlanKind.place:
      case PlanKind.shop:
        return '訪問済み';
    }
  }

  String get storageKey => name;

  static PlanKind fromKey(String? k) {
    return PlanKind.values.firstWhere(
      (e) => e.name == k,
      orElse: () => PlanKind.todo,
    );
  }
}

/// プランニングの1項目（世帯で共有）。
class PlanItem {
  final String id;
  final PlanKind kind;
  final String name;
  final String? memo;

  /// 完了/訪問済みフラグ。
  final bool done;

  /// 同じ kind 内での並び順（小さいほど上）。
  final int order;

  const PlanItem({
    required this.id,
    required this.kind,
    required this.name,
    this.memo,
    this.done = false,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'memo': memo,
        'done': done,
        'order': order,
      };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        id: j['id'] as String,
        kind: PlanKindX.fromKey(j['kind'] as String?),
        name: (j['name'] as String?) ?? '',
        memo: j['memo'] as String?,
        done: j['done'] as bool? ?? false,
        order: (j['order'] as num?)?.toInt() ?? 0,
      );

  PlanItem copyWith({
    String? name,
    String? memo,
    bool? done,
    int? order,
  }) =>
      PlanItem(
        id: id,
        kind: kind,
        name: name ?? this.name,
        memo: memo ?? this.memo,
        done: done ?? this.done,
        order: order ?? this.order,
      );
}
