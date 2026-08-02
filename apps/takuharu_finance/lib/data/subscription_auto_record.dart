import 'package:finance_core/finance_core.dart' as core;

import 'auth_service.dart';
import 'household_service.dart';
import 'subscription.dart';
import 'subscription_repository.dart';
import 'tx_repository.dart';

/// 固定費を「支払日が来たら自動で支出に記録」するサービス。
///
/// 手動の「今月分を支出に記録」（subscriptions_screen）と同じ receiptId
/// （`sub-{id}-{YYYYMM}`）を使うので、手動・自動どちらで記録されても
/// 二重計上にはならない。自動記帳のドキュメントIDは receiptId 自体にして、
/// 2台（たく・はる）で同時に起動しても同じレコードを上書きするだけにする
/// （＝重複行が生まれない）。
class SubscriptionAutoRecord {
  SubscriptionAutoRecord._();
  static final SubscriptionAutoRecord instance = SubscriptionAutoRecord._();

  /// 直近の実行時刻（アプリ復帰のたびに走るのを間引く）。
  DateTime? _lastRun;

  /// 支払日を過ぎた今月分の固定費を自動記帳する。戻り値は新たに記帳した件数。
  ///
  /// - 支払日（payDay）が来ている固定費だけを対象にする。payDay 未設定は
  ///   「月初（1日）」扱いで、その月に入っていれば記帳する。
  /// - 変動費（水道光熱費など）は、その月の実額が入力されるまで記帳しない
  ///   （金額が確定していないため）。実額が入ったら次の起動で記帳される。
  /// - 金額が 0 のものは記帳しない。
  Future<int> run() async {
    final now = DateTime.now();
    // 短時間の連続呼び出し（復帰の連打）を間引く。
    if (_lastRun != null && now.difference(_lastRun!).inMinutes < 10) return 0;

    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return 0;

    try {
      final subs = await SubscriptionRepository.instance.fetch(hid);
      final due = subs.where((s) {
        if (!s.appliesTo(now.year, now.month)) return false;
        // 変動費は実額が入るまで待つ。
        if (s.variable && !s.hasActualFor(now.year, now.month)) return false;
        // 支払日が来ているか（未指定・範囲外は月初=1日扱い）。
        return now.day >= _effectivePayDay(s);
      }).toList();
      if (due.isEmpty) {
        _lastRun = now;
        return 0;
      }

      final ym = '${now.year}${now.month.toString().padLeft(2, '0')}';
      final keys = {for (final s in due) s.id: 'sub-${s.id}-$ym'};
      final existing = await TxRepository.instance
          .existingReceiptIds(hid, keys.values.toList());

      final txns = <core.Transaction>[];
      for (final s in due) {
        final rid = keys[s.id]!;
        if (existing.contains(rid)) continue; // 既に記録済み
        final amount = s.amountForMonth(now.year, now.month);
        if (amount <= 0) continue;
        final day = _effectivePayDay(s);
        txns.add(core.Transaction(
          // ドキュメントIDを receiptId にして冪等化（2台同時起動でも重複しない）。
          id: rid,
          date: DateTime(now.year, now.month, day),
          type: core.TransactionType.expense,
          category: core.Category(major: s.category, sub: ''),
          paymentMethod: '',
          description: s.name,
          amount: amount,
          receiptId: rid,
          paidBy: s.paidBy,
          memo: '固定費',
        ));
      }
      if (txns.isNotEmpty) {
        await TxRepository.instance.addAll(hid, txns, uid);
      }
      _lastRun = now;
      return txns.length;
    } catch (_) {
      // 失敗しても黙って諦める（次の起動/復帰で再挑戦）。
      return 0;
    }
  }

  /// 記帳に使う支払日（1-28）。未設定・範囲外は月初(1日)にフォールバック。
  int _effectivePayDay(Subscription s) =>
      (s.payDay != null && s.payDay! >= 1 && s.payDay! <= 28) ? s.payDay! : 1;
}
