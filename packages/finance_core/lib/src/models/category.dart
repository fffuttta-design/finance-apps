/// FutaFinance / たくはるファイナンス 共通のカテゴリモデル。
///
/// 大カテゴリは数字プレフィックス付きで順序固定（決算分類の意図）。
class Category {
  /// 大カテゴリ（例: "0.固定費(定額)"）
  final String major;

  /// 小カテゴリ（例: "通信費"）
  final String sub;

  const Category({required this.major, required this.sub});

  /// 大カテゴリの順序番号（先頭の数字）。並び替えに使用。
  int get majorOrder {
    final match = RegExp(r'^(\d+)\.').firstMatch(major);
    return match != null ? int.parse(match.group(1)!) : 999;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category && major == other.major && sub == other.sub;

  @override
  int get hashCode => Object.hash(major, sub);

  @override
  String toString() => '$major / $sub';
}

/// FutaFinance の標準カテゴリ定義（ユーザーのスプシから抽出）。
class FutaCategories {
  static const fixedFlat = '0.固定費(定額)';
  static const fixedVariable = '1.固定費(変動)';
  static const supplies = '2.消耗品費';
  static const travel = '3.旅費交通費';
  static const entertainment = '4.交際費';
  static const training = '5.研修費';
  static const meeting = '6.会議費';
  static const misc = '7.雑費';

  /// 表示順に並べた大カテゴリ一覧。
  static const allMajor = [
    fixedFlat,
    fixedVariable,
    supplies,
    travel,
    entertainment,
    training,
    meeting,
    misc,
  ];

  /// 大カテゴリ → 小カテゴリ候補のマップ。
  static const subsByMajor = <String, List<String>>{
    fixedFlat: [
      '通信費',
      'ソフトウェア料金',
      'ライセンス料金',
      '顧問経費',
      '賃料',
      'コンサル・研修費',
    ],
    fixedVariable: [
      '通信費',
      'ソフトウェア料金',
      'ライセンス料金',
      '顧問経費',
      '賃料',
      'コンサル・研修費',
    ],
    supplies: ['機材', '資材', '装飾品', 'ソフトウェア'],
    travel: ['タクシー', '新幹線'],
    entertainment: ['会食'],
    training: ['セミナー', 'コンサル'],
    meeting: ['セルフカフェ', 'コワーキングスペース', '軽食', '会食'],
    misc: ['営業用等', '新聞図書費'],
  };
}
