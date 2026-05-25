import 'dart:convert';

/// ユーザーが編集可能なカテゴリ設定。
///
/// 8大カテゴリの順序とそれぞれの小カテゴリリストを保持する。
class CategoryConfig {
  /// 大カテゴリのリスト（表示順）。
  final List<MajorCategory> majors;

  const CategoryConfig({required this.majors});

  /// JSONエンコード（shared_preferences等への永続化用）。
  String toJsonString() => jsonEncode({
        'majors': majors.map((m) => m.toJson()).toList(),
      });

  /// JSONからデコード。
  factory CategoryConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final list = (json['majors'] as List)
        .map((m) => MajorCategory.fromJson(m as Map<String, dynamic>))
        .toList();
    return CategoryConfig(majors: list);
  }

  /// FutaFinance のデフォルト（スプシ準拠の8大カテゴリ）。
  factory CategoryConfig.futaDefaults() => const CategoryConfig(majors: [
        MajorCategory(name: '固定費(定額)', subs: [
          '通信費',
          'ソフトウェア料金',
          'ライセンス料金',
          '顧問経費',
          '賃料',
          'コンサル・研修費',
        ]),
        MajorCategory(name: '固定費(変動)', subs: [
          '通信費',
          'ソフトウェア料金',
          'ライセンス料金',
          '顧問経費',
          '賃料',
          'コンサル・研修費',
        ]),
        MajorCategory(
            name: '消耗品費', subs: ['機材', '資材', '装飾品', 'ソフトウェア']),
        MajorCategory(name: '旅費交通費', subs: ['タクシー', '新幹線']),
        MajorCategory(name: '交際費', subs: ['会食']),
        MajorCategory(name: '研修費', subs: ['セミナー', 'コンサル']),
        MajorCategory(
            name: '会議費', subs: ['セルフカフェ', 'コワーキングスペース', '軽食', '会食']),
        MajorCategory(name: '雑費', subs: ['営業用等', '新聞図書費']),
      ]);

  CategoryConfig copyWith({List<MajorCategory>? majors}) =>
      CategoryConfig(majors: majors ?? this.majors);
}

/// 大カテゴリと、それに紐づく小カテゴリ群。
class MajorCategory {
  /// 表示名（数字プレフィックス無し。例: "固定費(定額)"）。
  final String name;

  /// 小カテゴリの名前リスト。
  final List<String> subs;

  const MajorCategory({required this.name, required this.subs});

  /// インデックス付きの表示名（例: "0.固定費(定額)"）。
  String displayName(int index) => '$index.$name';

  Map<String, dynamic> toJson() => {'name': name, 'subs': subs};

  factory MajorCategory.fromJson(Map<String, dynamic> json) => MajorCategory(
        name: json['name'] as String,
        subs: (json['subs'] as List).cast<String>(),
      );

  MajorCategory copyWith({String? name, List<String>? subs}) =>
      MajorCategory(name: name ?? this.name, subs: subs ?? this.subs);
}
