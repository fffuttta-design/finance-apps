import 'dart:convert';

/// PL の年間計画（経営計画の予実用）。
/// まずは主要3科目（売上高 / 売上原価 / 販管費）の年間計画額を持つ簡易版。
/// 粗利・営業利益はここから自動計算する。
class PlPlanConfig {
  /// 計画の対象事業年度（期首の年, 10月開始なら fyStartYear=2025 → 2025/10〜2026/9）。
  final int fyStartYear;
  final int sales; // 売上高（年間計画）
  final int cogs; // 売上原価（年間計画）
  final int sga; // 販管費（年間計画）

  const PlPlanConfig({
    required this.fyStartYear,
    this.sales = 0,
    this.cogs = 0,
    this.sga = 0,
  });

  factory PlPlanConfig.empty(int fyStartYear) =>
      PlPlanConfig(fyStartYear: fyStartYear);

  int get grossPlan => sales - cogs; // 粗利
  int get operPlan => grossPlan - sga; // 営業利益

  Map<String, dynamic> toJson() => {
        'fyStartYear': fyStartYear,
        'sales': sales,
        'cogs': cogs,
        'sga': sga,
      };

  factory PlPlanConfig.fromJson(Map<String, dynamic> j) => PlPlanConfig(
        fyStartYear: (j['fyStartYear'] as num?)?.toInt() ?? 0,
        sales: (j['sales'] as num?)?.toInt() ?? 0,
        cogs: (j['cogs'] as num?)?.toInt() ?? 0,
        sga: (j['sga'] as num?)?.toInt() ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());

  factory PlPlanConfig.fromJsonString(String source) =>
      PlPlanConfig.fromJson(jsonDecode(source) as Map<String, dynamic>);

  PlPlanConfig copyWith({int? sales, int? cogs, int? sga}) => PlPlanConfig(
        fyStartYear: fyStartYear,
        sales: sales ?? this.sales,
        cogs: cogs ?? this.cogs,
        sga: sga ?? this.sga,
      );
}
