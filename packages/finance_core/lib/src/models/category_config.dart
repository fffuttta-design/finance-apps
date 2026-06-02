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

  /// FutaFinance 事業用デフォルト（PL科目＋セクション。即PL化用）。
  /// 既存カテゴリ（資材/会食/セルフカフェ等）は対応科目のサブに紐づけ済み。
  factory CategoryConfig.futaDefaults() => const CategoryConfig(majors: [
        // ── 売上原価 ──
        MajorCategory(
            name: '外注費', iconKey: '🤝', section: '売上原価', subs: []),
        MajorCategory(
            name: '仕入', iconKey: '📥', section: '売上原価', subs: []),
        // ── 人件費 ──
        MajorCategory(
            name: '役員報酬', iconKey: '👔', section: '人件費', subs: []),
        MajorCategory(
            name: '給与', iconKey: '💴', section: '人件費', subs: []),
        MajorCategory(
            name: '雑給与', iconKey: '🧾', section: '人件費', subs: []),
        MajorCategory(
            name: '賞与・退職金', iconKey: '🎁', section: '人件費', subs: []),
        MajorCategory(
            name: '法定福利費', iconKey: '🏥', section: '人件費', subs: []),
        // ── 販管費 ──
        MajorCategory(
            name: '福利厚生費', iconKey: '☕', section: '販管費', subs: []),
        MajorCategory(
            name: '広告宣伝費', iconKey: '📣', section: '販管費', subs: []),
        MajorCategory(
            name: '交際費', iconKey: '🍴', section: '販管費', subs: ['会食']),
        MajorCategory(
            name: '会議費',
            iconKey: '💼',
            section: '販管費',
            subs: ['セルフカフェ', 'コワーキングスペース', '軽食']),
        MajorCategory(
            name: '旅費交通費',
            iconKey: '🚗',
            section: '販管費',
            subs: ['タクシー', '新幹線']),
        MajorCategory(
            name: '通信費',
            iconKey: '📶',
            section: '販管費',
            subs: ['ソフトウェア', 'ソフトウェア料金', 'ライセンス料金']),
        MajorCategory(
            name: '消耗品費',
            iconKey: '📦',
            section: '販管費',
            subs: ['機材', '資材', '装飾品']),
        MajorCategory(
            name: '修繕費', iconKey: '🔧', section: '販管費', subs: []),
        MajorCategory(
            name: '水道光熱費', iconKey: '💡', section: '販管費', subs: []),
        MajorCategory(
            name: '新聞図書費', iconKey: '📚', section: '販管費', subs: []),
        MajorCategory(
            name: '諸会費', iconKey: '🎫', section: '販管費', subs: ['セミナー']),
        MajorCategory(
            name: '支払手数料', iconKey: '🏧', section: '販管費', subs: []),
        MajorCategory(
            name: '賃借料', iconKey: '🏢', section: '販管費', subs: ['賃料']),
        MajorCategory(
            name: '保険料', iconKey: '🛡️', section: '販管費', subs: []),
        MajorCategory(
            name: '租税公課', iconKey: '🧾', section: '販管費', subs: []),
        MajorCategory(
            name: '支払報酬',
            iconKey: '📝',
            section: '販管費',
            subs: ['コンサル', 'コンサル・研修費', '顧問経費']),
        // ── その他費用 ──
        MajorCategory(
            name: '減価償却費', iconKey: '📉', section: 'その他費用', subs: []),
        MajorCategory(
            name: '雑費', iconKey: '🏷️', section: 'その他費用', subs: ['営業用等']),
        // ── 営業外費用 ──
        MajorCategory(
            name: '支払利息', iconKey: '🏦', section: '営業外費用', subs: []),
        MajorCategory(
            name: '雑損失', iconKey: '⚠️', section: '営業外費用', subs: []),
      ]);

  /// セクションの登場順（最初に現れた順）。null/空は末尾「その他」にまとめる。
  List<String> get sectionsInOrder {
    final seen = <String>{};
    final list = <String>[];
    var hasUngrouped = false;
    for (final m in majors) {
      final s = m.section;
      if (s == null || s.isEmpty) {
        hasUngrouped = true;
        continue;
      }
      if (seen.add(s)) list.add(s);
    }
    if (hasUngrouped) list.add('その他');
    return list;
  }

  /// セクション→そのセクションに属する大カテゴリ（元の順序を保持）。
  Map<String, List<MajorCategory>> get majorsBySection {
    final map = <String, List<MajorCategory>>{};
    for (final m in majors) {
      final key = (m.section == null || m.section!.isEmpty)
          ? 'その他'
          : m.section!;
      map.putIfAbsent(key, () => []).add(m);
    }
    return map;
  }

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

  /// 所属セクション（PLのまとまり。例: "人件費" "販管費" "営業外費用"）。
  /// null/空は「その他」グループ扱い。UI でセクション見出しに使う。
  final String? section;

  const MajorCategory({
    required this.name,
    required this.subs,
    this.iconKey,
    this.subIcons,
    this.section,
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
        'section': section,
      };

  factory MajorCategory.fromJson(Map<String, dynamic> json) => MajorCategory(
        name: json['name'] as String,
        subs: (json['subs'] as List).cast<String>(),
        iconKey: json['iconKey'] as String?,
        subIcons: (json['subIcons'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        section: json['section'] as String?,
      );

  MajorCategory copyWith({
    String? name,
    List<String>? subs,
    String? iconKey,
    Map<String, String>? subIcons,
    String? section,
  }) =>
      MajorCategory(
        name: name ?? this.name,
        subs: subs ?? this.subs,
        iconKey: iconKey ?? this.iconKey,
        subIcons: subIcons ?? this.subIcons,
        section: section ?? this.section,
      );
}
