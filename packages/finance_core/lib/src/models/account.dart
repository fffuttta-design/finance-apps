/// 資金口座（例: 住信SBIネット銀行）。
class Account {
  final String id;
  final String name;

  /// 当月初時点の残高（円）。
  final int monthStartBalance;

  const Account({
    required this.id,
    required this.name,
    required this.monthStartBalance,
  });
}
