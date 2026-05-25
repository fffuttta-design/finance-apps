import 'package:finance_core/finance_core.dart';

/// FutaFinance のモックデータ（2026年5月、スプシ実数値ベース）。
/// データ層はDフェーズでFirestore接続に置き換える。
class MockData {
  /// 「今日」の日付（実機の現在日時を使うとテスト毎にズレるので固定）。
  static final DateTime today = DateTime(2026, 5, 25);

  /// 資金口座（住信SBI）の月初残高。
  static const Account account = Account(
    id: 'sbi-main',
    name: '住信SBI',
    monthStartBalance: 10652701,
  );

  /// 当月の取引一覧（スプシから抽出）。
  static final List<Transaction> transactions = [
    // 5/01 まとめて引き落とし系
    _t('1', 5, 1, FutaCategories.fixedFlat, 'コンサル・研修費',
        'ChiloI(Youtubeコミュニティ)', 980, '三井住友カード'),
    _t('2', 5, 1, FutaCategories.fixedFlat, 'ソフトウェア料金', 'gyazo', 590,
        '三井住友カード'),
    _t('3', 5, 1, FutaCategories.fixedFlat, 'ソフトウェア料金',
        'GoogleWorkSpace(ドメイン・サブ)', 2090, '三井住友カード'),
    _t('4', 5, 1, FutaCategories.fixedFlat, 'ソフトウェア料金',
        'gigafile便:スタンダードプラン', 198, '三井住友カード'),
    _t('5', 5, 1, FutaCategories.fixedFlat, 'ソフトウェア料金', 'kindle unlimited',
        980, '三井住友カード'),
    _t('6', 5, 1, FutaCategories.fixedFlat, '顧問経費', 'VS税務顧問', 38500, '銀行引落'),
    _t('7', 5, 1, FutaCategories.fixedFlat, '通信費', 'Wi-Fi料金・コミュファ光', 6820,
        '三井住友カード'),
    _t('8', 5, 1, FutaCategories.fixedVariable, 'ソフトウェア料金', 'ChatGPT', 3583,
        '三井住友カード'),
    _t('9', 5, 1, FutaCategories.fixedVariable, 'ソフトウェア料金', 'Claude Pro', 3580,
        '三井住友カード'),
    _t('10', 5, 1, FutaCategories.fixedVariable, '通信費', '携帯料金・LINEモバイル',
        6402, '三井住友カード'),
    // 5/06〜 消耗品費系（Claude / 書籍）
    _t('11', 5, 6, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 898,
        '三井住友カード'),
    _t('12', 5, 6, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 898,
        '三井住友カード'),
    _t('13', 5, 7, FutaCategories.misc, '新聞図書費', '鬼速PDCA', 1267, '三井住友カード'),
    _t('14', 5, 10, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 895,
        '三井住友カード'),
    _t('15', 5, 10, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 895,
        '三井住友カード'),
    _t('16', 5, 11, FutaCategories.supplies, 'ソフトウェア', 'Clade 10\$', 1790,
        '三井住友カード'),
    _t('17', 5, 11, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 895,
        '三井住友カード'),
    _t('18', 5, 11, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 895,
        '三井住友カード'),
    _t('19', 5, 11, FutaCategories.supplies, 'ソフトウェア', 'Clade 7\$', 1253,
        '三井住友カード'),
    _t('20', 5, 11, FutaCategories.misc, '新聞図書費',
        '2025-2026年版 みんなが欲しかった', 1472, '三井住友カード'),
    _t('21', 5, 12, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 895,
        '三井住友カード'),
    _t('22', 5, 12, FutaCategories.supplies, 'ソフトウェア', 'Clade 5\$', 897,
        '三井住友カード'),
    _t('23', 5, 12, FutaCategories.misc, '新聞図書費', '起業家(幻冬舎文庫)', 644,
        '三井住友カード'),
    _t('24', 5, 13, FutaCategories.supplies, 'ソフトウェア', 'Clade 50\$', 8074,
        '三井住友カード'),
    _t('25', 5, 20, FutaCategories.supplies, '機材', 'ハンディ扇風機', 2850, '三井住友カード'),
    _t('26', 5, 20, FutaCategories.supplies, '資材', '椅子クッション', 1330, '三井住友カード'),
    _t('27', 5, 20, FutaCategories.misc, '新聞図書費', '成長以外すべて死', 1339, '三井住友カード'),
    // 注: 元はUSD表記 $94.78 → ここでは円換算済みの値で扱う
    _t('28', 5, 20, FutaCategories.supplies, 'ソフトウェア', 'Claude Code Max5\$プラン',
        14217, '三井住友カード'),
    _t('29', 5, 21, FutaCategories.meeting, 'セルフカフェ', '1時間予約', 359, '三井住友カード'),
    _t('30', 5, 24, FutaCategories.supplies, '機材', 'ガジェポーチ&時計', 4791, '三井住友カード'),
  ];

  /// 年間払いの固定費契約。
  static final List<AnnualContract> annualContracts = [
    AnnualContract(
      id: 'gmo-office',
      name: 'GMOバーチャルオフィス',
      amount: 5940,
      nextChargeDate: DateTime(2026, 9, 30),
    ),
    const AnnualContract(
      id: 'smbc-card',
      name: '三井住友カード年会費',
      amount: 5500,
      nextChargeDate: null,
      memo: '次回請求日未確定',
    ),
  ];

  // 内部ヘルパー
  static Transaction _t(String id, int m, int d, String major, String sub,
      String desc, int amount, String payment) {
    return Transaction(
      id: id,
      date: DateTime(2026, m, d),
      category: Category(major: major, sub: sub),
      paymentMethod: payment,
      description: desc,
      amount: amount,
      receiptUrl: 'https://drive.google.com/...', // モック
    );
  }
}
