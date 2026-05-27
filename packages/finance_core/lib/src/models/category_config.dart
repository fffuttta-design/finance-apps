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

  /// 事業モード = FutaFinance(現在のスプシ準拠)のデフォルト。
  /// 旧名 futaDefaults() のエイリアス。
  factory CategoryConfig.businessDefaults() => CategoryConfig.futaDefaults();

  /// 個人モードのデフォルト（プライベート家計簿用）。
  factory CategoryConfig.personalDefaults() =>
      const CategoryConfig(majors: [
        MajorCategory(
          name: '固定費',
          iconKey: '🏠',
          subs: ['家賃', '自己投資', '経費', '娯楽'],
        ),
        MajorCategory(
          name: '食費',
          iconKey: '🍔',
          subs: [
            'UberEats・外食',
            '飲み物',
            '健康投資',
            '筋トレ投資',
            'おやつ',
            '自販機'
          ],
        ),
        MajorCategory(
          name: '生活維持費',
          iconKey: '🧴',
          subs: ['生活必需品', '生活便利品'],
        ),
        MajorCategory(
          name: '交際費',
          iconKey: '🎉',
          subs: ['食事', '寄り'],
        ),
        MajorCategory(
          name: '美容・衣服',
          iconKey: '👗',
          subs: [
            'スキンケア',
            '美容院',
            'その他美容品',
            'トップス系',
            'ボトムス系',
            'カバン系',
            'アクセ系',
            '靴系',
            '下着・靴下系'
          ],
        ),
        MajorCategory(
          name: '病院・薬',
          iconKey: '💊',
          subs: ['歯医者', '内科'],
        ),
        MajorCategory(
          name: '交通費',
          iconKey: '🚗',
          subs: ['Suicaチャージ', 'タクシー', '新幹線'],
        ),
        MajorCategory(
          name: '自己投資・経費',
          iconKey: '📚',
          subs: ['書籍', '雑費', '筋トレ', '外見改善', 'アプリ', 'その他'],
        ),
        MajorCategory(
          name: '趣味',
          iconKey: '🎮',
          subs: ['その他'],
        ),
        MajorCategory(
          name: '特別出費',
          iconKey: '⭐',
          subs: ['R活動経費', '裁判費用', '高額投資'],
        ),
      ]);

  /// FutaFinance のデフォルト（スプシ準拠の8大カテゴリ + 絵文字）。
  factory CategoryConfig.futaDefaults() => const CategoryConfig(majors: [
        MajorCategory(
            name: '固定費(定額)',
            iconKey: '📅',
            subs: [
              '通信費',
              'ソフトウェア料金',
              'ライセンス料金',
              '顧問経費',
              '賃料',
              'コンサル・研修費',
            ]),
        MajorCategory(
            name: '固定費(変動)',
            iconKey: '💸',
            subs: [
              '通信費',
              'ソフトウェア料金',
              'ライセンス料金',
              '顧問経費',
              '賃料',
              'コンサル・研修費',
            ]),
        MajorCategory(
            name: '消耗品費',
            iconKey: '📦',
            subs: ['機材', '資材', '装飾品', 'ソフトウェア']),
        MajorCategory(
            name: '旅費交通費',
            iconKey: '🚗',
            subs: ['タクシー', '新幹線']),
        MajorCategory(
            name: '交際費', iconKey: '🍴', subs: ['会食']),
        MajorCategory(
            name: '研修費', iconKey: '🎓', subs: ['セミナー', 'コンサル']),
        MajorCategory(
            name: '会議費',
            iconKey: '💼',
            subs: ['セルフカフェ', 'コワーキングスペース', '軽食', '会食']),
        MajorCategory(
            name: '雑費', iconKey: '🏷️', subs: ['営業用等', '新聞図書費']),
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

  /// アイコンキー（絵文字 / 画像URL / Material アイコン名のいずれか）。
  /// - "🏠" などの絵文字
  /// - "https://..." の画像URL
  /// - "home" などの Material アイコン名（kCategoryIconsキー）
  final String? iconKey;

  /// 小カテゴリ名 → アイコンキーのマップ（任意）。
  /// 小カテゴリのアイコンは `subs` 配列と分離して持つことで、
  /// `subs: List<String>` の後方互換を維持する。
  final Map<String, String>? subIcons;

  const MajorCategory({
    required this.name,
    required this.subs,
    this.iconKey,
    this.subIcons,
  });

  /// インデックス付きの表示名（例: "0.固定費(定額)"）。
  String displayName(int index) => '$index.$name';

  /// 指定の小カテゴリ名に紐づくアイコンキーを返す（未設定なら null）。
  String? iconForSub(String subName) => subIcons?[subName];

  Map<String, dynamic> toJson() => {
        'name': name,
        'subs': subs,
        'iconKey': iconKey,
        'subIcons': subIcons,
      };

  factory MajorCategory.fromJson(Map<String, dynamic> json) => MajorCategory(
        name: json['name'] as String,
        subs: (json['subs'] as List).cast<String>(),
        iconKey: json['iconKey'] as String?,
        subIcons: (json['subIcons'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
      );

  MajorCategory copyWith({
    String? name,
    List<String>? subs,
    String? iconKey,
    Map<String, String>? subIcons,
  }) =>
      MajorCategory(
        name: name ?? this.name,
        subs: subs ?? this.subs,
        iconKey: iconKey ?? this.iconKey,
        subIcons: subIcons ?? this.subIcons,
      );
}
