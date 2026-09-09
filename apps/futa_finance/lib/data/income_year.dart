import 'dart:convert';

/// その年の「立場」。年収の意味づけ（学生バイト／会社員／個人事業／法人役員）が
/// 変わると数字の読み方も変わるので、年ごとに持たせる。
enum WorkStatus {
  student, // 学生（学生納付特例など）
  employee, // 会社員（給与のみ）
  employeeSide, // 会社員＋副業（給与＋事業）
  soleProprietor, // 個人事業主
  executive, // 法人役員（役員報酬）
  other,
}

extension WorkStatusX on WorkStatus {
  String get label {
    switch (this) {
      case WorkStatus.student:
        return '学生';
      case WorkStatus.employee:
        return '会社員';
      case WorkStatus.employeeSide:
        return '会社員＋副業';
      case WorkStatus.soleProprietor:
        return '個人事業';
      case WorkStatus.executive:
        return '法人役員';
      case WorkStatus.other:
        return 'その他';
    }
  }

  String get emoji {
    switch (this) {
      case WorkStatus.student:
        return '🎓';
      case WorkStatus.employee:
        return '🏢';
      case WorkStatus.employeeSide:
        return '🏢＋';
      case WorkStatus.soleProprietor:
        return '🧑‍💻';
      case WorkStatus.executive:
        return '👔';
      case WorkStatus.other:
        return '📄';
    }
  }
}

/// 1年ぶんの年収・税・社会保険の記録。
///
/// 「いくら稼いで、いくら持っていかれて、いくら残ったか」を1年＝1レコードで残す。
/// 数字はすべて**暦年（1/1〜12/31）**ベースの円。分からない項目は 0 のままでよい。
class IncomeYear {
  final String id;
  final int year; // 暦年（2019 など）
  final int? age; // その年の誕生日を迎えたあとの年齢
  final WorkStatus status;
  final String? employer; // 勤務先・屋号（「UTグループ」「RunStrategy株式会社」など）

  // ── 収入（額面） ─────────────────────────────
  final int salary; // 給与収入（源泉徴収票の支払金額・役員報酬もここ）
  final int business; // 事業収入（売上）
  final int otherIncome; // その他の収入

  /// 合計所得金額（確定申告書・住民税の課税情報の「合計所得金額」）。
  /// 収入から控除・経費を引いたあとの数字。0 なら未入力。
  final int totalIncome;

  // ── 税 ───────────────────────────────────
  final int incomeTax; // 所得税＋復興特別所得税（その年分）
  final int residentTax; // 住民税（その年に納めた年度分の合計）
  final int businessTax; // 個人事業税

  // ── 社会保険（本人負担分） ───────────────────
  final int healthInsurance; // 健康保険（給与天引き）
  final int pension; // 厚生年金（本人負担）
  final int nationalPension; // 国民年金（第1号・付加保険料込み）
  final int nationalHealthInsurance; // 国民健康保険
  final int employmentInsurance; // 雇用保険
  final int otherInsurance; // 介護保険・子ども子育て支援金など

  final String? note; // メモ
  final String? source; // 出典（源泉徴収票／確定申告書／マイナポータル 等）

  const IncomeYear({
    required this.id,
    required this.year,
    this.age,
    this.status = WorkStatus.other,
    this.employer,
    this.salary = 0,
    this.business = 0,
    this.otherIncome = 0,
    this.totalIncome = 0,
    this.incomeTax = 0,
    this.residentTax = 0,
    this.businessTax = 0,
    this.healthInsurance = 0,
    this.pension = 0,
    this.nationalPension = 0,
    this.nationalHealthInsurance = 0,
    this.employmentInsurance = 0,
    this.otherInsurance = 0,
    this.note,
    this.source,
  });

  /// 額面の合計（いわゆる「年収」）。
  int get grossIncome => salary + business + otherIncome;

  /// 税の合計。
  int get taxTotal => incomeTax + residentTax + businessTax;

  /// 社会保険の合計（本人負担分）。
  int get insuranceTotal =>
      healthInsurance +
      pension +
      nationalPension +
      nationalHealthInsurance +
      employmentInsurance +
      otherInsurance;

  /// 税＋社会保険＝持っていかれた合計。
  int get burdenTotal => taxTotal + insuranceTotal;

  /// ざっくり手取り（額面 − 税 − 社会保険）。事業の経費は引いていない。
  int get netIncome => grossIncome - burdenTotal;

  /// 負担率（税＋社保 ÷ 額面）。額面0なら0。
  double get burdenRate => grossIncome == 0 ? 0 : burdenTotal / grossIncome;

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'age': age,
        'status': status.name,
        'employer': employer,
        'salary': salary,
        'business': business,
        'otherIncome': otherIncome,
        'totalIncome': totalIncome,
        'incomeTax': incomeTax,
        'residentTax': residentTax,
        'businessTax': businessTax,
        'healthInsurance': healthInsurance,
        'pension': pension,
        'nationalPension': nationalPension,
        'nationalHealthInsurance': nationalHealthInsurance,
        'employmentInsurance': employmentInsurance,
        'otherInsurance': otherInsurance,
        'note': note,
        'source': source,
      };

  static int _i(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt() ?? 0;

  factory IncomeYear.fromJson(Map<String, dynamic> j) => IncomeYear(
        id: j['id'] as String,
        year: (j['year'] as num).toInt(),
        age: (j['age'] as num?)?.toInt(),
        status: WorkStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String? ?? 'other'),
          orElse: () => WorkStatus.other,
        ),
        employer: j['employer'] as String?,
        salary: _i(j, 'salary'),
        business: _i(j, 'business'),
        otherIncome: _i(j, 'otherIncome'),
        totalIncome: _i(j, 'totalIncome'),
        incomeTax: _i(j, 'incomeTax'),
        residentTax: _i(j, 'residentTax'),
        businessTax: _i(j, 'businessTax'),
        healthInsurance: _i(j, 'healthInsurance'),
        pension: _i(j, 'pension'),
        nationalPension: _i(j, 'nationalPension'),
        nationalHealthInsurance: _i(j, 'nationalHealthInsurance'),
        employmentInsurance: _i(j, 'employmentInsurance'),
        otherInsurance: _i(j, 'otherInsurance'),
        note: j['note'] as String?,
        source: j['source'] as String?,
      );

  IncomeYear copyWith({
    int? year,
    int? age,
    WorkStatus? status,
    String? employer,
    int? salary,
    int? business,
    int? otherIncome,
    int? totalIncome,
    int? incomeTax,
    int? residentTax,
    int? businessTax,
    int? healthInsurance,
    int? pension,
    int? nationalPension,
    int? nationalHealthInsurance,
    int? employmentInsurance,
    int? otherInsurance,
    String? note,
    String? source,
  }) =>
      IncomeYear(
        id: id,
        year: year ?? this.year,
        age: age ?? this.age,
        status: status ?? this.status,
        employer: employer ?? this.employer,
        salary: salary ?? this.salary,
        business: business ?? this.business,
        otherIncome: otherIncome ?? this.otherIncome,
        totalIncome: totalIncome ?? this.totalIncome,
        incomeTax: incomeTax ?? this.incomeTax,
        residentTax: residentTax ?? this.residentTax,
        businessTax: businessTax ?? this.businessTax,
        healthInsurance: healthInsurance ?? this.healthInsurance,
        pension: pension ?? this.pension,
        nationalPension: nationalPension ?? this.nationalPension,
        nationalHealthInsurance:
            nationalHealthInsurance ?? this.nationalHealthInsurance,
        employmentInsurance: employmentInsurance ?? this.employmentInsurance,
        otherInsurance: otherInsurance ?? this.otherInsurance,
        note: note ?? this.note,
        source: source ?? this.source,
      );
}

/// [IncomeYear] の集合。永続化単位。
class IncomeHistoryConfig {
  final List<IncomeYear> years;

  const IncomeHistoryConfig({required this.years});

  factory IncomeHistoryConfig.empty() =>
      const IncomeHistoryConfig(years: []);

  /// 年の新しい順に並べたリスト。
  List<IncomeYear> get sortedDesc {
    final list = [...years];
    list.sort((a, b) => b.year.compareTo(a.year));
    return list;
  }

  /// 年の古い順（グラフ用）。
  List<IncomeYear> get sortedAsc {
    final list = [...years];
    list.sort((a, b) => a.year.compareTo(b.year));
    return list;
  }

  int get lifetimeGross =>
      years.fold<int>(0, (s, y) => s + y.grossIncome);
  int get lifetimeTax => years.fold<int>(0, (s, y) => s + y.taxTotal);
  int get lifetimeInsurance =>
      years.fold<int>(0, (s, y) => s + y.insuranceTotal);
  int get lifetimeBurden => lifetimeTax + lifetimeInsurance;
  int get lifetimeNet => lifetimeGross - lifetimeBurden;

  String toJsonString() =>
      jsonEncode({'years': years.map((y) => y.toJson()).toList()});

  factory IncomeHistoryConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return IncomeHistoryConfig(
      years: (json['years'] as List)
          .map((y) => IncomeYear.fromJson(y as Map<String, dynamic>))
          .toList(),
    );
  }
}
