import 'package:finance_core/finance_core.dart';

/// FutaFinance のサンプルデータ（2026年5月、ユーザーから提供された実データ）。
/// 設定画面の「サンプルデータを投入」ボタンから TransactionRepository に流し込む。
class MockData {
  /// 年間払いの固定費契約（テスト/初期表示用）。
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

  /// サンプル銀行口座（住信SBI、月初¥10,652,701）。
  static const RegisteredBankAccount sampleBank = RegisteredBankAccount(
    id: 'sample-sbi',
    name: '住信SBI',
    startingBalance: 10652701,
  );

  /// 2026年5月の実取引（30件、ユーザー提供データに忠実）。
  static List<Transaction> sampleTransactions() => [
        _t('s01', 1, '0.固定費(定額)', 'コンサル・研修費', 'Chilol(Youtubeコミュニティ)',
            980, '三井住友カード'),
        _t('s02', 1, '0.固定費(定額)', 'ソフトウェア料金', 'gyazo', 590, '三井住友カード'),
        _t('s03', 1, '0.固定費(定額)', 'ソフトウェア料金',
            'GoogleWorkSpace(ドメイン・サーバー)', 2090, '三井住友カード'),
        _t('s04', 1, '0.固定費(定額)', 'ソフトウェア料金',
            'gigafile便:スタンダートプラン', 198, '三井住友カード'),
        _t('s05', 1, '0.固定費(定額)', 'ソフトウェア料金', 'kndle unlimited', 980,
            '三井住友カード'),
        _t('s06', 1, '0.固定費(定額)', '顧問経費', 'VS税務顧問', 38500, '銀行引落'),
        _t('s07', 1, '0.固定費(定額)', '通信費', 'Wi-Fi料金・コミュファ光', 6820,
            '三井住友カード'),
        _t('s08', 1, '1.固定費(変動)', 'ソフトウェア料金', 'ChatGPT', 3583,
            '三井住友カード'),
        _t('s09', 1, '1.固定費(変動)', 'ソフトウェア料金', 'Claude Pro', 3580,
            '三井住友カード'),
        _t('s10', 1, '1.固定費(変動)', '通信費', '携帯料金・LINEモバイル', 6402,
            '三井住友カード'),
        _t('s11', 6, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 898, '三井住友カード'),
        _t('s12', 6, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 898, '三井住友カード'),
        _t('s13', 7, '7.雑費', '新聞図書費', '鬼速PDCA', 1267, '三井住友カード'),
        _t('s14', 10, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 895, '三井住友カード'),
        _t('s15', 10, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 895, '三井住友カード'),
        _t('s16', 11, '2.消耗品費', 'ソフトウェア', 'Clade 10\$', 1790,
            '三井住友カード'),
        _t('s17', 11, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 895, '三井住友カード'),
        _t('s18', 11, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 895, '三井住友カード'),
        _t('s19', 11, '2.消耗品費', 'ソフトウェア', 'Clade 7\$', 1253,
            '三井住友カード'),
        _t('s20', 11, '7.雑費', '新聞図書費',
            '2025-2026年版 みんなが欲しかった！ FPの教科書 3級 みんなが欲しかったシリーズ',
            1472, '三井住友カード'),
        _t('s21', 12, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 895, '三井住友カード'),
        _t('s22', 12, '2.消耗品費', 'ソフトウェア', 'Clade 5\$', 897, '三井住友カード'),
        _t('s23', 12, '7.雑費', '新聞図書費', '起業家 (幻冬舎文庫)', 644, '三井住友カード'),
        _t('s24', 13, '2.消耗品費', 'ソフトウェア', 'Clade 50\$', 8074,
            '三井住友カード'),
        _t('s25', 20, '2.消耗品費', '機材', 'ハンディ扇風機', 2850, '三井住友カード'),
        _t('s26', 20, '2.消耗品費', '資材', '椅子クッション', 1330, '三井住友カード'),
        _t('s27', 20, '7.雑費', '新聞図書費', '成長以外すべて死', 1339, '三井住友カード'),
        _tWithMemo('s28', 20, '2.消耗品費', 'ソフトウェア',
            'Claude Code Max5\$プラン', 14217, '三井住友カード',
            'USD \$94.78 換算 (¥150/USDで概算)'),
        _t('s29', 21, '6.会議費', 'セルフカフェ', '1時間予約', 359, '三井住友カード'),
        _t('s30', 24, '2.消耗品費', '', 'ガジェポーチ＆時計', 4791, '三井住友カード'),
      ];

  static Transaction _t(String id, int d, String major, String sub,
      String desc, int amount, String payment) {
    return Transaction(
      id: id,
      date: DateTime(2026, 5, d),
      type: TransactionType.expense,
      category: Category(major: major, sub: sub),
      paymentMethod: payment,
      description: desc,
      amount: amount,
    );
  }

  static Transaction _tWithMemo(String id, int d, String major, String sub,
      String desc, int amount, String payment, String memo) {
    return Transaction(
      id: id,
      date: DateTime(2026, 5, d),
      type: TransactionType.expense,
      category: Category(major: major, sub: sub),
      paymentMethod: payment,
      description: desc,
      amount: amount,
      memo: memo,
    );
  }
}
