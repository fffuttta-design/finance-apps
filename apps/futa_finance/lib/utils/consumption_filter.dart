import 'package:finance_core/finance_core.dart' as core;

/// 「消費」から外したいハズレ値（家賃・税金・税務顧問料）を判定する共通ロジック。
///
/// 支出タブ（rich_expenses）とホームの主役カード（rich_home）が **同じ定義**で
/// 家賃・税金を除外できるように、キーワードと判定関数をここに一本化する。
/// どちらか片方だけキーワードを直すと表示がズレるため、必ずこのファイルを正とする。

/// 家賃とみなすキーワード。ユーザーは「家賃＝共同生活費」で運用しているため
/// 「共同生活費」等も同一視する。「ナカネ」は共同生活費（家賃）の振込先名義。
const List<String> kRentKeywords = ['家賃', '共同生活費', '共同生活', 'ナカネ'];

/// 税金・社会保険とみなすキーワード（本人指定 2026-08-14）。
/// ⚠ 短すぎる語（「税」「年金」単体）は無関係な明細に誤ヒットするため使わず、
///   具体的な税目・保険名だけを列挙する。
const List<String> kTaxKeywords = [
  '税金', '個人事業税', '事業税', '住民税', '市民税', '県民税', '所得税',
  '予定納税', '消費税', '固定資産税', '自動車税', '軽自動車税',
  '国民健康保険', '健康保険料', '国民年金', '厚生年金', '社会保険',
];

/// 税務顧問料とみなすキーワード（事業モードのハズレ値）。
/// ⚠️ 実データの摘要は「VS税務顧問」（"料"なし）なので "税務顧問" で拾う。
const List<String> kAdvisoryKeywords = ['税務顧問', '顧問料', '税理士'];

bool _has(List<String> kws, String? s) =>
    s != null && kws.any((k) => s.contains(k));

// ── 家賃 ──────────────────────────────────────────────
bool isRentTx(core.Transaction t) =>
    _has(kRentKeywords, t.category.sub) ||
    _has(kRentKeywords, t.category.major) ||
    _has(kRentKeywords, t.description);

bool isRentSub(core.Subscription s) =>
    _has(kRentKeywords, s.name) ||
    _has(kRentKeywords, s.category) ||
    _has(kRentKeywords, s.plMajor);

// ── 税金・社会保険 ────────────────────────────────────
bool isTaxTx(core.Transaction t) =>
    _has(kTaxKeywords, t.category.sub) ||
    _has(kTaxKeywords, t.category.major) ||
    _has(kTaxKeywords, t.description);

bool isTaxSub(core.Subscription s) =>
    _has(kTaxKeywords, s.name) ||
    _has(kTaxKeywords, s.category) ||
    _has(kTaxKeywords, s.plMajor);

// ── 家賃 or 税金（個人モードの「家賃・税金を除く」トグル対象）──────
bool isRentOrTaxTx(core.Transaction t) => isRentTx(t) || isTaxTx(t);
bool isRentOrTaxSub(core.Subscription s) => isRentSub(s) || isTaxSub(s);

// ── 税務顧問料（事業モードの「税務顧問料を除く」トグル対象）─────────
bool isAdvisoryTx(core.Transaction t) =>
    _has(kAdvisoryKeywords, t.category.sub) ||
    _has(kAdvisoryKeywords, t.category.major) ||
    _has(kAdvisoryKeywords, t.description);

bool isAdvisorySub(core.Subscription s) =>
    _has(kAdvisoryKeywords, s.name) ||
    _has(kAdvisoryKeywords, s.category) ||
    _has(kAdvisoryKeywords, s.plMajor);
