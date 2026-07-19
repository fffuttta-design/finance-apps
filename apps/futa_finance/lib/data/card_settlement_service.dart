import 'package:finance_core/finance_core.dart' as core;

import '../utils/jp_holidays.dart';
import 'month_closing_repository.dart';
import 'settings_repository.dart';
import 'subscription_repository.dart';
import 'transaction_repository.dart';

/// クレジットカードの「自動引き落とし」を生成するサービス。
///
/// カードに引落口座(settlementAccountId)＋引落日(paymentDay)が設定されていると、
/// 引落日を過ぎた対象月ぶんの利用額を、引落口座から差し引く**振替(transfer)**取引を
/// 1本自動生成する（＝口座残高が減る／PLには計上しない。カード利用の費用は既に
/// 明細で計上済みなので二重計上しない）。
///
/// 仕様:
/// - 対象月＝「前月利用→当月払い」。引落月Wの利用月は W-1。
/// - 引落日が土日祝なら翌営業日にずらす（[JpHolidays.nextBusinessDay]）。
/// - 金額＝カードの実請求額(monthlyActualBillings)があればそれ、無ければ
///   予定額（当月の対象カード払い取引＋固定費の合計）。
/// - **二重生成防止**: 取引IDを `cardsettle_{cardId}_{利用YYYY-MM}` に固定し、
///   既存があればスキップ（起動のたび呼んでも増えない）。
/// - **遡り過ぎ防止**: 引落日が「直近62日以内〜今日」のぶんだけ生成する
///   （設定直後に過去を大量生成しない）。
class CardSettlementService {
  CardSettlementService._();

  static final Set<String> _ranModes = {};

  /// モード（business/personal）ごとに1セッション1回だけ走らせる。
  /// 起動時・モード切替時に呼ぶ想定（payments はモード別なので現モードを処理）。
  static Future<List<core.Transaction>> runOncePerMode(String modeKey) async {
    if (_ranModes.contains(modeKey)) return const [];
    _ranModes.add(modeKey);
    try {
      return await run();
    } catch (_) {
      return const [];
    }
  }

  /// 未処理の自動引落を生成し、作成した振替のリストを返す。
  static Future<List<core.Transaction>> run() async {
    final cfg = await SettingsRepository.instance.loadPayments();
    final txns = await TransactionRepository.instance.loadAll();
    final subs = (await SubscriptionRepository.instance.load()).subscriptions;
    // 締め済みの月には引落を作らない（締めた後に明細が湧く問題の対策）。
    final closing = await MonthClosingRepository.instance.load();

    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);
    // 利用月の下限（記録開始）。ここ以降の引落は、引落口座設定後にさかのぼって発行する。
    final floorUsage = DateTime(2025, 11, 1);
    final curYm = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final existingIds = txns.map((t) => t.id).toSet();

    final created = <core.Transaction>[];
    for (final card in cfg.creditCards) {
      if (card.inactive) continue;
      final acctId = card.settlementAccountId;
      final day = card.paymentDay;
      if (acctId == null || day == null) continue;
      core.RegisteredBankAccount? bank;
      for (final b in cfg.bankAccounts) {
        if (b.id == acctId) {
          bank = b;
          break;
        }
      }
      if (bank == null) continue;

      // 引落月 W を今月から過去へ走査（W-1 が利用月）。利用月が下限を下回ったら打ち切り。
      // 引落口座を後から設定しても、記録開始まで確実にさかのぼって発行する（「必ず発行」）。
      for (int back = 0; back <= 24; back++) {
        final w = DateTime(today.year, today.month - back, 1); // 引落月
        final usage = DateTime(w.year, w.month - 1, 1); // 利用月（前月）
        if (usage.isBefore(floorUsage)) break;
        final usageYm =
            '${usage.year}-${usage.month.toString().padLeft(2, '0')}';
        // 引落日（月末クランプ）→ 土日祝なら翌営業日。
        final lastDay = DateTime(w.year, w.month + 1, 0).day;
        final due = JpHolidays.nextBusinessDay(
            DateTime(w.year, w.month, day > lastDay ? lastDay : day));
        // 引落日がまだ来ていないぶんは作らない（未来の引落は予定のまま）。
        if (due.isAfter(todayD)) continue;

        final id = 'cardsettle_${card.id}_$usageYm';
        if (existingIds.contains(id)) continue;

        // 引落日の月（W）が締め済みなら作らない（引落口座/カードのどちらかが締め済みでも）。
        final wYm = '${w.year}-${w.month.toString().padLeft(2, '0')}';
        final bankName = bank.name; // closure 外で確定（null 昇格のため）
        final cardName = card.name;
        final monthClosed = closing.closings.any((c) =>
            (c.yearMonth == 'w:$bankName:$wYm' ||
                c.yearMonth == 'card:$cardName:$wYm') &&
            c.isClosed);
        if (monthClosed) continue;

        final amount = card.monthlyActualBillings[usageYm] ??
            _planned(card.name, usageYm, txns, subs, curYm);
        if (amount <= 0) continue;

        // 引落明細のカテゴリ。カード側で設定があればそれ、無ければ「振替」。
        // （引落は振替扱いで収支/PL非計上。カテゴリは明細の表示ラベル。）
        final catMajor =
            (card.settlementCategoryMajor?.trim().isNotEmpty ?? false)
                ? card.settlementCategoryMajor!.trim()
                : '振替';
        final catSub = card.settlementCategorySub?.trim() ?? '';
        final tx = core.Transaction(
          id: id,
          date: due,
          type: core.TransactionType.transfer,
          category: core.Category(major: catMajor, sub: catSub),
          paymentMethod: '',
          description: '${card.name} 引落（${usage.month}月利用分）',
          amount: amount,
          transferFromAccount: bank.name,
          transferToAccount: card.name,
          memo: '自動引落',
        );
        await TransactionRepository.instance.add(tx);
        existingIds.add(id);
        created.add(tx);
      }
    }
    return created;
  }

  /// カードの引落カテゴリを変更したら、既存の引落明細（cardsettle_{cardId}_*）にも反映する。
  static Future<void> syncCategory(core.RegisteredCreditCard card) async {
    List<core.Transaction> txns;
    try {
      txns = await TransactionRepository.instance.loadAll();
    } catch (_) {
      return;
    }
    final prefix = 'cardsettle_${card.id}_';
    final major = (card.settlementCategoryMajor?.trim().isNotEmpty ?? false)
        ? card.settlementCategoryMajor!.trim()
        : '振替';
    final sub = card.settlementCategorySub?.trim() ?? '';
    final updates = <core.Transaction>[];
    for (final t in txns) {
      if (!t.id.startsWith(prefix)) continue;
      if (t.category.major == major && t.category.sub == sub) continue;
      updates
          .add(t.copyWith(category: core.Category(major: major, sub: sub)));
    }
    if (updates.isNotEmpty) {
      await TransactionRepository.instance.updateMany(updates);
    }
  }

  /// 予定額（＝ウォレット照合の「予定」と同じ計算）: 当月の対象カード払い取引＋固定費。
  static int _planned(String name, String ym, List<core.Transaction> txns,
      List<core.Subscription> subs, String curYm) {
    final parts = ym.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final txSum = txns
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == name &&
            t.date.year == year &&
            t.date.month == month)
        .fold<int>(0, (s, t) => s + t.amount);
    // 過去月は実取引だけで数える（その月に実際は課金されていない固定費を
    // サブスク設定の支払方法だけで予定計上して膨らませない。ウォレット/明細と揃える）。
    if (ym.compareTo(curYm) < 0) return txSum;
    // 既に実明細化された固定費は txSum に含まれるので二重に数えない。
    final subSum = subs
        .where((s) => (s.paymentMethod ?? '') == name)
        .where((s) => !txns.any((t) => t.id == 'fixedcost_${s.id}_$ym'))
        .fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
    return txSum + subSum;
  }
}
