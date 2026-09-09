import 'income_history_repository.dart';
import 'income_year.dart';

/// 二村さんの年収・税・社会保険の実績（2026-09-09 調査）。
///
/// 出典は4つ。**推測で埋めた数字は `source` に「概算」と入れてある。**
/// - 確定申告書（令和6年分・令和7年分）／源泉徴収票（ＵＴグループ・令和6年分）
/// - 給与明細（RunStrategy株式会社・2026年）
/// - マイナポータル「税・所得」＝愛知県名古屋市の個人住民税課税情報
///   （課税年度2022〜2026＝2021年分〜2025年分。それより前は市が保有しておらず取得不可）
/// - ねんきんネット＝厚生年金の標準報酬月額の履歴・国民年金の納付実績
///
/// **住民税は「その所得に対して課された金額」を、稼いだ年の行に入れている**
/// （2024年分の所得 → 2025年度住民税 → 2024年の行）。いつ稼いだ分の税か、で
/// 並べたほうが年ごとの負担が読めるため。
List<IncomeYear> buildIncomeHistorySeed() => const [
      IncomeYear(
        id: 'seed-2017',
        year: 2017,
        age: 22,
        status: WorkStatus.student,
        employer: '学生（国民年金は学生納付特例）',
        note: '国民年金は学生納付特例で猶予＝保険料の負担なし。'
            '給与の記録は年金にも住民税にも残っていない。',
        source: 'ねんきんネット',
      ),
      IncomeYear(
        id: 'seed-2018',
        year: 2018,
        age: 23,
        status: WorkStatus.student,
        employer: '学生（国民年金は学生納付特例）',
        note: '2019年4月のゲオホールディングス入社まで学生納付特例。'
            '学生納付特例は通算47か月ぶんあり、10年以内なら追納できる。',
        source: 'ねんきんネット',
      ),
      IncomeYear(
        id: 'seed-2019',
        year: 2019,
        age: 24,
        status: WorkStatus.employee,
        employer: '株式会社ゲオホールディングス（4月入社）',
        salary: 2340000,
        pension: 214110,
        healthInsurance: 115830,
        employmentInsurance: 7020,
        note: '4月入社。標準報酬月額26万円。額面・社会保険は「26万×9か月」で計算した概算。'
            'マイナポータルの課税情報は2021年分より前を取得できないため、実額は未確認。',
        source: 'ねんきんネット（標準報酬月額）＋概算',
      ),
      IncomeYear(
        id: 'seed-2020',
        year: 2020,
        age: 25,
        status: WorkStatus.employee,
        employer: '株式会社ゲオホールディングス',
        salary: 3290000,
        pension: 300120,
        healthInsurance: 162360,
        employmentInsurance: 9870,
        note: '9月に標準報酬月額が26万→30万へ。4月に賞与1万円。'
            '額面・社会保険は標準報酬月額からの概算（実額は未確認）。',
        source: 'ねんきんネット（標準報酬月額）＋概算',
      ),
      IncomeYear(
        id: 'seed-2021',
        year: 2021,
        age: 26,
        status: WorkStatus.employee,
        employer: '株式会社ゲオホールディングス（12月10日 退職）',
        salary: 4066286,
        totalIncome: 2766400,
        residentTax: 178600,
        pension: 307440,
        healthInsurance: 166320,
        employmentInsurance: 12190,
        nationalPension: 16610,
        nationalHealthInsurance: 20068,
        note: '合計所得276万・社会保険料52万・住民税17.8万は住民税の課税情報の実額。'
            '額面406万は合計所得からの逆算。9月に標準報酬月額が30万→32万へ。'
            '12月10日に退職し、12月から国民年金・国民健康保険（名古屋市）へ。'
            '社会保険の内訳は合計52.2万を料率で割り振った概算。',
        source: 'マイナポータル 税・所得（2022年度）＋ねんきんネット',
      ),
      IncomeYear(
        id: 'seed-2022',
        year: 2022,
        age: 27,
        status: WorkStatus.employee,
        employer: 'ＵＴグループ株式会社（2月16日 入社）',
        salary: 1928000,
        totalIncome: 1269600,
        residentTax: 61700,
        pension: 155000,
        healthInsurance: 68000,
        employmentInsurance: 6690,
        note: '合計所得127万・社会保険料22.9万・住民税6.2万は課税情報の実額。'
            '額面193万は合計所得からの逆算。標準報酬月額15万→9月に20万。'
            'この年は確定申告をしていない（年末調整のみ）。'
            '社会保険の内訳は合計22.9万を料率で割り振った概算。',
        source: 'マイナポータル 税・所得（2023年度）＋ねんきんネット',
      ),
      IncomeYear(
        id: 'seed-2023',
        year: 2023,
        age: 28,
        status: WorkStatus.employeeSide,
        employer: 'ＵＴグループ株式会社 ＋ 事業（YouTube等）',
        salary: 2400000,
        business: 1030708,
        totalIncome: 2630708,
        residentTax: 172200,
        pension: 220000,
        healthInsurance: 105000,
        employmentInsurance: 13772,
        note: '合計所得263万・社会保険料33.9万・住民税17.2万は課税情報の実額。'
            '給与240万は標準報酬月額20万からの概算で、事業ぶん103万は'
            '「合計所得−給与所得」の差額＝所得ベース（売上ではない）。'
            'この年から確定申告をしている。',
        source: 'マイナポータル 税・所得（2024年度）＋ねんきんネット',
      ),
      IncomeYear(
        id: 'seed-2024',
        year: 2024,
        age: 29,
        status: WorkStatus.soleProprietor,
        employer: 'ＵＴグループ株式会社（6月末 退職）→ 個人事業',
        salary: 1293039,
        business: 3768180,
        totalIncome: 3408822,
        incomeTax: 148580,
        residentTax: 271500,
        pension: 130000,
        healthInsurance: 60000,
        employmentInsurance: 7455,
        note: '確定申告書 令和6年分の実額。事業収入376万＋給与129万（源泉徴収票）。'
            '所得税は源泉17,480＋申告納税額131,100（定額減税3万円が効いている）。'
            '住民税27.1万は2025年度分。'
            '🔴 社会保険料控除が197,455円＝給与天引き分だけで、'
            '7月以降に払った国民年金・国民健康保険が入っていない（控除漏れの疑い）。',
        source: '確定申告書 令和6年分＋源泉徴収票＋マイナポータル（2025年度）',
      ),
      IncomeYear(
        id: 'seed-2025',
        year: 2025,
        age: 30,
        status: WorkStatus.soleProprietor,
        employer: '個人事業（YouTube広告・BGM印税・運用代行）',
        business: 10350216,
        totalIncome: 7322705,
        incomeTax: 940238,
        residentTax: 670200,
        businessTax: 134000,
        nationalPension: 213000,
        nationalHealthInsurance: 400000,
        note: '収入内訳＝YouTube広告649万／BGM印税175万／運用代行211万。'
            '更正の請求で経費302万が認められ、所得は1,000万→732万に。'
            '所得税は更正後の所得での再計算（概算）。住民税67万は2026年度分の実額。'
            '個人事業税はBGMを非課税で通した場合の見込み額。'
            '🔴 確定申告に社会保険料控除が1円も入っていない（課税情報でも0円）。'
            '国民年金・国保の金額は概算なので、控除証明書と名古屋市の納付済額で'
            '置き換えてから更正の請求をすること。',
        source: '確定申告書 令和7年分（更正後）＋マイナポータル（2026年度）',
      ),
      IncomeYear(
        id: 'seed-2026',
        year: 2026,
        age: 31,
        status: WorkStatus.executive,
        employer: 'ＲｕｎＳｔｒａｔｅｇｙ株式会社（役員報酬）',
        salary: 7200000,
        incomeTax: 382430,
        pension: 593835,
        healthInsurance: 322813,
        otherInsurance: 5424,
        note: '1月1日から役員報酬 月60万円（標準報酬月額59万円・健保33級/厚年30級）。'
            '毎月の天引きは 健保29,293＋厚年53,985＋子ども子育て支援金678＋所得税30,640。'
            '9月以降は予定額を含む。会社も同額の社会保険料を負担しているので、'
            '厚生年金だけで年約119万円が国に入っている計算。'
            '2026年分の所得に対する住民税は2027年度に課される（この行には入れていない）。',
        source: '給与明細（RunStrategy）＋ねんきんネット',
      ),
    ];

/// 調査済みの実績を流し込む。**既にある年は触らない**ので何度呼んでも壊れない。
///
/// 業績タブのカードと、設定の「年収の記録」画面の両方から呼ぶ（入口を1つにすると
/// 「どっちのボタンを押せば入るのか」で迷うため、見えている場所で必ず入るようにした）。
Future<int> loadIncomeHistorySeed() async {
  final cfg = await IncomeHistoryRepository.instance.load();
  final existing = {for (final y in cfg.years) y.year};
  final merged = [...cfg.years];
  var added = 0;
  for (final s in buildIncomeHistorySeed()) {
    if (existing.contains(s.year)) continue;
    merged.add(s);
    added++;
  }
  if (added > 0) {
    await IncomeHistoryRepository.instance
        .save(IncomeHistoryConfig(years: merged));
  }
  return added;
}
