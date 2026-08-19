import 'dart:convert';

/// ふるさと納税の「寄付金受領証明書」の状態。
enum FurusatoCertificate {
  /// まだ届いていない（＝控除が消えるリスクがある状態）。
  none,

  /// 紙の受領証明書を受け取った。
  received,

  /// ポータルが発行する「寄付金控除に関する証明書」(XML) でカバーされる。
  xml,
}

extension FurusatoCertificateX on FurusatoCertificate {
  String get label => switch (this) {
        FurusatoCertificate.none => '未着',
        FurusatoCertificate.received => '受領済',
        FurusatoCertificate.xml => 'XMLでカバー',
      };

  /// 確定申告に出せる状態か。
  bool get isReady => this != FurusatoCertificate.none;

  static FurusatoCertificate parse(String? v) =>
      FurusatoCertificate.values.firstWhere(
        (e) => e.name == v,
        orElse: () => FurusatoCertificate.none,
      );
}

/// 1件の寄付に付ける追加情報。
///
/// 金額・日付は既存の Transaction が持っているので**ここには持たない**
/// （二重管理を避ける）。取引IDに紐づけて、記帳だけでは表せない
/// 「どの自治体か」「証明書は届いたか」「ワンストップを出したか」だけを保持する。
class FurusatoEntry {
  /// 紐づく Transaction.id。
  final String txId;

  /// 自治体名（例: 神奈川県川崎市）。ワンストップの5自治体判定に使う。
  final String municipality;

  /// 申し込んだポータル（例: さとふる）。証明書がポータル単位で出るため持つ。
  final String portal;

  /// ワンストップ特例の申請を出したか。
  final bool onestopApplied;

  /// 受領証明書の状態。
  final FurusatoCertificate certificate;

  /// 補足（返礼品名など）。
  final String? note;

  const FurusatoEntry({
    required this.txId,
    this.municipality = '',
    this.portal = '',
    this.onestopApplied = false,
    this.certificate = FurusatoCertificate.none,
    this.note,
  });

  FurusatoEntry copyWith({
    String? municipality,
    String? portal,
    bool? onestopApplied,
    FurusatoCertificate? certificate,
    String? note,
  }) =>
      FurusatoEntry(
        txId: txId,
        municipality: municipality ?? this.municipality,
        portal: portal ?? this.portal,
        onestopApplied: onestopApplied ?? this.onestopApplied,
        certificate: certificate ?? this.certificate,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'txId': txId,
        'municipality': municipality,
        'portal': portal,
        'onestopApplied': onestopApplied,
        'certificate': certificate.name,
        if (note != null) 'note': note,
      };

  factory FurusatoEntry.fromJson(Map<String, dynamic> j) => FurusatoEntry(
        txId: j['txId'] as String? ?? '',
        municipality: j['municipality'] as String? ?? '',
        portal: j['portal'] as String? ?? '',
        onestopApplied: j['onestopApplied'] as bool? ?? false,
        certificate: FurusatoCertificateX.parse(j['certificate'] as String?),
        note: j['note'] as String?,
      );
}

/// 年ごとの設定（控除上限額と、その根拠になった入力値）。
class FurusatoYearConfig {
  final int year;

  /// 控除上限額（円）。計算機で出すか、手入力する。
  final int limitAmount;

  // 以下は限度額計算機の入力を保持しておくためのもの（再計算・検算用）。
  /// 給与収入（役員報酬の年額）。
  final int salaryIncome;

  /// 社会保険料の年額。
  final int socialInsurance;

  /// その他の所得控除（生命保険料・配偶者控除など）。
  final int otherDeduction;

  /// ワンストップ特例を使う方針か（true なら5自治体の見張りを出す）。
  final bool useOnestop;

  const FurusatoYearConfig({
    required this.year,
    this.limitAmount = 0,
    this.salaryIncome = 0,
    this.socialInsurance = 0,
    this.otherDeduction = 0,
    this.useOnestop = true,
  });

  FurusatoYearConfig copyWith({
    int? limitAmount,
    int? salaryIncome,
    int? socialInsurance,
    int? otherDeduction,
    bool? useOnestop,
  }) =>
      FurusatoYearConfig(
        year: year,
        limitAmount: limitAmount ?? this.limitAmount,
        salaryIncome: salaryIncome ?? this.salaryIncome,
        socialInsurance: socialInsurance ?? this.socialInsurance,
        otherDeduction: otherDeduction ?? this.otherDeduction,
        useOnestop: useOnestop ?? this.useOnestop,
      );

  Map<String, dynamic> toJson() => {
        'year': year,
        'limitAmount': limitAmount,
        'salaryIncome': salaryIncome,
        'socialInsurance': socialInsurance,
        'otherDeduction': otherDeduction,
        'useOnestop': useOnestop,
      };

  factory FurusatoYearConfig.fromJson(Map<String, dynamic> j) =>
      FurusatoYearConfig(
        year: (j['year'] as num?)?.toInt() ?? 2026,
        limitAmount: (j['limitAmount'] as num?)?.toInt() ?? 0,
        salaryIncome: (j['salaryIncome'] as num?)?.toInt() ?? 0,
        socialInsurance: (j['socialInsurance'] as num?)?.toInt() ?? 0,
        otherDeduction: (j['otherDeduction'] as num?)?.toInt() ?? 0,
        useOnestop: j['useOnestop'] as bool? ?? true,
      );
}

/// ふるさと納税管理の全設定。
class FurusatoConfig {
  /// 集計対象にする支出カテゴリ（大 / 小）。
  /// ここに一致する支出を「寄付」として拾う＝専用データを持たない設計。
  final String categoryMajor;
  final String categorySub;

  final Map<int, FurusatoYearConfig> years;
  final List<FurusatoEntry> entries;

  const FurusatoConfig({
    this.categoryMajor = defaultMajor,
    this.categorySub = defaultSub,
    this.years = const {},
    this.entries = const [],
  });

  // カテゴリマスタに実在する組み合わせに合わせる。
  // 新しい大カテゴリを足すと既存の集計が割れるので、既存の「税金」に小カテゴリを1つ足す形にした。
  static const defaultMajor = '税金';
  static const defaultSub = 'ふるさと納税';

  /// ワンストップ特例が使える自治体数の上限。
  static const onestopMunicipalityLimit = 5;

  /// ワンストップ特例の申請期限（寄付した翌年の1月10日）。
  static DateTime onestopDeadlineFor(int year) => DateTime(year + 1, 1, 10);

  factory FurusatoConfig.empty() => const FurusatoConfig();

  FurusatoYearConfig yearOf(int year) =>
      years[year] ?? FurusatoYearConfig(year: year);

  FurusatoEntry entryOf(String txId) => entries.firstWhere(
        (e) => e.txId == txId,
        orElse: () => FurusatoEntry(txId: txId),
      );

  FurusatoConfig upsertYear(FurusatoYearConfig y) =>
      copyWith(years: {...years, y.year: y});

  FurusatoConfig upsertEntry(FurusatoEntry e) {
    final list = [...entries];
    final i = list.indexWhere((x) => x.txId == e.txId);
    if (i >= 0) {
      list[i] = e;
    } else {
      list.add(e);
    }
    return copyWith(entries: list);
  }

  FurusatoConfig copyWith({
    String? categoryMajor,
    String? categorySub,
    Map<int, FurusatoYearConfig>? years,
    List<FurusatoEntry>? entries,
  }) =>
      FurusatoConfig(
        categoryMajor: categoryMajor ?? this.categoryMajor,
        categorySub: categorySub ?? this.categorySub,
        years: years ?? this.years,
        entries: entries ?? this.entries,
      );

  Map<String, dynamic> toJson() => {
        'categoryMajor': categoryMajor,
        'categorySub': categorySub,
        'years': years.values.map((y) => y.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory FurusatoConfig.fromJson(Map<String, dynamic> j) {
    final ys = <int, FurusatoYearConfig>{};
    for (final raw in (j['years'] as List? ?? const [])) {
      final y =
          FurusatoYearConfig.fromJson(Map<String, dynamic>.from(raw as Map));
      ys[y.year] = y;
    }
    return FurusatoConfig(
      categoryMajor: j['categoryMajor'] as String? ?? defaultMajor,
      categorySub: j['categorySub'] as String? ?? defaultSub,
      years: ys,
      entries: [
        for (final raw in (j['entries'] as List? ?? const []))
          FurusatoEntry.fromJson(Map<String, dynamic>.from(raw as Map))
      ],
    );
  }

  factory FurusatoConfig.fromJsonString(String s) =>
      FurusatoConfig.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
}

/// ふるさと納税の控除上限額を概算する。
///
/// 給与所得者（役員報酬を取っている場合を含む）向けの標準式：
///
///   上限 = 住民税所得割額 × 20% ÷ (90% − 所得税率 × 1.021) + 2,000円
///
/// あくまで概算。実際の控除は各種控除の有無で動くので、大口の寄付前には
/// ポータルの詳細シミュレーターとも突き合わせること。
class FurusatoLimit {
  FurusatoLimit._();

  /// 復興特別所得税の係数。
  static const reconstruction = 1.021;

  /// 自己負担額（年間合計に対して1回だけかかる）。
  static const selfPay = 2000;

  /// 所得税の基礎控除（令和7年分〜）。
  static const basicDeductionIncomeTax = 580000;

  /// 住民税の基礎控除。
  static const basicDeductionResidentTax = 430000;

  /// 損益分岐となる年間寄付額。返礼品は寄付額の3割が上限なので、
  /// 年間合計がこの額を下回ると自己負担2,000円のほうが大きくなる。
  static const breakEvenDonation = 6667;

  /// 給与所得控除の額。
  static int salaryDeduction(int income) {
    if (income <= 0) return 0;
    if (income <= 1900000) return income < 650000 ? income : 650000;
    if (income <= 3600000) return (income * 0.3).round() + 80000;
    if (income <= 6600000) return (income * 0.2).round() + 440000;
    if (income <= 8500000) return (income * 0.1).round() + 1100000;
    return 1950000;
  }

  /// 所得税の税率（超過累進の該当区分）。
  static double incomeTaxRate(int taxable) {
    if (taxable <= 1949000) return 0.05;
    if (taxable <= 3299000) return 0.10;
    if (taxable <= 6949000) return 0.20;
    if (taxable <= 8999000) return 0.23;
    if (taxable <= 17999000) return 0.33;
    if (taxable <= 39999000) return 0.40;
    return 0.45;
  }

  /// 給与収入・社会保険料・その他控除から上限額を概算する。
  static FurusatoLimitResult estimate({
    required int salaryIncome,
    required int socialInsurance,
    int otherDeduction = 0,
  }) {
    if (salaryIncome <= 0) {
      return const FurusatoLimitResult(
          limit: 0, residentTaxBase: 0, incomeTaxRate: 0);
    }
    final afterSalaryDeduction = salaryIncome - salaryDeduction(salaryIncome);
    final common = socialInsurance + otherDeduction;

    var taxableIncomeTax =
        afterSalaryDeduction - common - basicDeductionIncomeTax;
    if (taxableIncomeTax < 0) taxableIncomeTax = 0;
    var taxableResident =
        afterSalaryDeduction - common - basicDeductionResidentTax;
    if (taxableResident < 0) taxableResident = 0;

    final rate = incomeTaxRate(taxableIncomeTax);
    final shotokuwari = (taxableResident * 0.10).round();
    final denom = 0.90 - rate * reconstruction;
    if (denom <= 0) {
      return FurusatoLimitResult(
          limit: 0, residentTaxBase: shotokuwari, incomeTaxRate: rate);
    }
    final limit = (shotokuwari * 0.20 / denom).floor() + selfPay;
    return FurusatoLimitResult(
        limit: limit, residentTaxBase: shotokuwari, incomeTaxRate: rate);
  }
}

class FurusatoLimitResult {
  /// 控除上限額（この額までなら自己負担2,000円で済む）。
  final int limit;

  /// 住民税所得割額。
  final int residentTaxBase;

  /// 適用された所得税率。
  final double incomeTaxRate;

  const FurusatoLimitResult({
    required this.limit,
    required this.residentTaxBase,
    required this.incomeTaxRate,
  });
}
