import 'package:finance_core/finance_core.dart' as core;

/// 「一緒に（折半）」を表す paidBy のセンチネル値。
/// 固定費側と同じ値を使う（片方に寄せると立替が発生しないことを表す）。
const String kPaidByBoth = 'both';

/// 特別支出1件ぶんの集計と精算結果。
///
/// 精算は「実際に出ていったお金」だけで計算する＝**予定（未払い）は含めない**。
/// 予定はあくまで「これから出る見込み」として別枠で持つ。
class SpecialExpenseSummary {
  /// 確定（支払い済み）の合計。
  final int confirmed;

  /// 予定（まだ払っていない）の合計。
  final int pending;

  /// 誰がいくら立て替えたか（確定分のみ・uid→金額）。
  /// 「一緒に払った」「支払者不明」は誰の立替でもないので入らない。
  final Map<String, int> paidByUid;

  /// 立替が起きた分の合計（＝精算の対象になる金額）。
  final int advancedTotal;

  /// 精算でお金を渡す人／受け取る人（差が無ければ両方 null）。
  final String? fromUid;
  final String? toUid;

  /// 渡す金額（差が無ければ 0）。
  final int settleAmount;

  const SpecialExpenseSummary({
    required this.confirmed,
    required this.pending,
    required this.paidByUid,
    required this.advancedTotal,
    required this.fromUid,
    required this.toUid,
    required this.settleAmount,
  });

  /// 確定＋予定の総額（旅行がいくらかかるか）。
  int get total => confirmed + pending;

  /// 1人あたりの総額（人数で割る）。
  int perPerson(int memberCount) =>
      memberCount <= 0 ? total : (total / memberCount).round();

  /// 精算するものが残っているか。
  bool get needsSettle => settleAmount > 0;

  /// [txns]（その特別支出にぶら下がる取引）から集計する。
  ///
  /// [memberUids] は世帯のメンバー。2人以外でも壊れないように、
  /// 「立替が起きた金額を人数で割った自己負担」との差額で精算相手を決める。
  factory SpecialExpenseSummary.of(
      List<core.Transaction> txns, List<String> memberUids) {
    var confirmed = 0;
    var pending = 0;
    final paid = <String, int>{};
    var advanced = 0;

    for (final t in txns) {
      // 収入・振替はこの箱の「かかったお金」ではないので数えない。
      if (t.type != core.TransactionType.expense) continue;
      final amount = t.effectiveAmount;
      if (t.isPending) {
        pending += amount;
        continue;
      }
      confirmed += amount;

      final payer = t.paidBy ?? t.recordedBy;
      // 「一緒に払った」「誰が払ったか分からない」は、その場で折半済みとみなす。
      if (payer == null || payer == kPaidByBoth) continue;
      paid[payer] = (paid[payer] ?? 0) + amount;
      advanced += amount;
    }

    // 立替が無ければ精算も無い。
    final n = memberUids.isEmpty ? 1 : memberUids.length;
    if (advanced == 0) {
      return SpecialExpenseSummary(
        confirmed: confirmed,
        pending: pending,
        paidByUid: paid,
        advancedTotal: 0,
        fromUid: null,
        toUid: null,
        settleAmount: 0,
      );
    }

    // 立替が起きた金額を人数で割ったものが1人の自己負担。
    // 立替額との差がプラスなら「受け取る側」、マイナスなら「渡す側」。
    final share = advanced / n;
    String? maxUid;
    String? minUid;
    var maxDiff = 0.0;
    var minDiff = 0.0;
    for (final uid in memberUids) {
      final diff = (paid[uid] ?? 0) - share;
      if (diff > maxDiff) {
        maxDiff = diff;
        maxUid = uid;
      }
      if (diff < minDiff) {
        minDiff = diff;
        minUid = uid;
      }
    }

    final amount = maxDiff.round();
    return SpecialExpenseSummary(
      confirmed: confirmed,
      pending: pending,
      paidByUid: paid,
      advancedTotal: advanced,
      // 少なく払った人（minUid）が、多く払った人（maxUid）へ渡す。
      fromUid: amount > 0 ? minUid : null,
      toUid: amount > 0 ? maxUid : null,
      settleAmount: amount > 0 ? amount : 0,
    );
  }
}
