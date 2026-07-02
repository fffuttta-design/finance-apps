import 'package:finance_core/finance_core.dart' as core;

import 'subscription_repository.dart';
import 'transaction_repository.dart';

/// 固定費（サブスク）の「請求日を過ぎた月」を、実取引（明細）として自動生成する。
///
/// 目的：固定費も他の経費と同じく“実明細”として並び、タップで詳細が開き、
/// 領収書チェック（電子/紙）を付けられるようにする。請求日を過ぎたら実明細化する。
///
/// 仕様:
/// - 対象＝月払いサブスク。請求日(billingDay)を過ぎた月ぶんを生成。
///   - 過去月は全部、今月は請求日<=今日のぶんだけ（未到来はまだ予定＝生成しない）。
/// - 金額＝定額はamount / 変動はmonthlyActuals[月]（変動で未入力の月は生成しない＝入力待ちのまま）。
/// - **二重生成防止**: id=`fixedcost_{subId}_{YYYY-MM}` 固定。既存はスキップ（起動のたび呼んでも増えない）。
///   さらに同月に同名/同額の“固定費”実取引が既にあれば生成しない（カードCSV取込等と二重にしない）。
/// - カテゴリ/支払方法は、同一固定費の既存「固定費」取引（最寄り月）から踏襲。無ければサブスク設定。
/// - **遡り下限**: 記録開始の 2025-11 まで（サブスクの startYearMonth があればそれ以降）。
class FixedCostMaterializer {
  FixedCostMaterializer._();

  static final Set<String> _ranModes = {};
  static const _floorYm = '2025-11';

  /// モード（business/personal）ごとに1セッション1回だけ走らせる。
  static Future<List<core.Transaction>> runOncePerMode(String modeKey) async {
    if (_ranModes.contains(modeKey)) return const [];
    _ranModes.add(modeKey);
    try {
      return await run();
    } catch (_) {
      return const [];
    }
  }

  static String _ym(int y, int m) => '$y-${m.toString().padLeft(2, '0')}';
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[（）()【】\[\]・:：\s　]'), '');

  static Future<List<core.Transaction>> run() async {
    final txns = await TransactionRepository.instance.loadAll();
    final subs = (await SubscriptionRepository.instance.load()).subscriptions;
    final now = DateTime.now();
    final curYm = _ym(now.year, now.month);
    final existingIds = txns.map((t) => t.id).toSet();
    final created = <core.Transaction>[];

    for (final sub in subs) {
      if (sub.cycle != core.SubscriptionCycle.monthly) continue;
      final bd = sub.billingDay ?? 1;
      final nn = _norm(sub.name);

      var startYm = sub.startYearMonth ?? _floorYm;
      if (startYm.compareTo(_floorYm) < 0) startYm = _floorYm;
      var y = int.tryParse(startYm.split('-')[0]) ?? now.year;
      var m = int.tryParse(startYm.split('-')[1]) ?? now.month;

      while (y < now.year || (y == now.year && m <= now.month)) {
        final ymStr = _ym(y, m);
        // 終了月を過ぎたら打ち切り。
        if (sub.endYearMonth != null && ymStr.compareTo(sub.endYearMonth!) > 0) {
          break;
        }
        final dim = DateTime(y, m + 1, 0).day;
        final day = bd > dim ? dim : bd;
        // 請求日を過ぎているか（今月は今日まで、過去月は常に過ぎている）。
        final passed = ymStr.compareTo(curYm) < 0 ||
            (ymStr == curYm && day <= now.day);
        if (!passed) {
          m++;
          if (m > 12) {
            m = 1;
            y++;
          }
          continue;
        }
        final amt = sub.isVariable ? (sub.monthlyActuals[ymStr] ?? 0) : sub.amount;
        final id = 'fixedcost_${sub.id}_$ymStr';
        final already = existingIds.contains(id) ||
            txns.any((t) => _isSameFixed(t, y, m, amt, nn));
        if (amt > 0 && !already) {
          final tmpl = _template(txns, nn, y, m);
          // カテゴリ/支払方法/領収書の受け取り方は固定費マスタの設定を優先。
          // 会計科目(plMajor)を小カテゴリに、無ければ従来の推定(既存取引)を使う。
          final masterSub = (sub.plMajor?.trim().isNotEmpty ?? false)
              ? sub.plMajor!.trim()
              : ((sub.category?.trim().isNotEmpty ?? false)
                  ? sub.category!.trim()
                  : (tmpl?.category.sub ?? ''));
          final pay = (sub.paymentMethod?.trim().isNotEmpty ?? false)
              ? sub.paymentMethod!.trim()
              : (tmpl?.paymentMethod ?? '');
          final rk = sub.receiptKind; // 'paper' / 'drive' / null
          final tx = core.Transaction(
            id: id,
            date: DateTime(y, m, day),
            type: core.TransactionType.expense,
            category: core.Category(
              major: sub.isVariable ? '1.固定費(変動)' : '0.固定費(定額)',
              sub: masterSub,
            ),
            paymentMethod: pay,
            description: sub.name,
            amount: amt,
            // 紙で受け取る固定費は最初から「保管済み」として作る。
            receiptSaved: rk == 'paper',
            receiptType: (rk == 'paper' || rk == 'drive') ? rk : null,
          );
          await TransactionRepository.instance.add(tx);
          existingIds.add(id);
          created.add(tx);
        }
        m++;
        if (m > 12) {
          m = 1;
          y++;
        }
      }
    }
    return created;
  }

  /// その月に、同じ固定費の実取引（同名 or 同額の固定費費目）が既にあるか。
  static bool _isSameFixed(
      core.Transaction t, int y, int m, int amt, String nn) {
    if (t.type != core.TransactionType.expense) return false;
    if (t.date.year != y || t.date.month != m) return false;
    final nd = _norm(t.description);
    final nameHit =
        nn.isNotEmpty && nd.isNotEmpty && (nd.contains(nn) || nn.contains(nd));
    final amtHit = t.amount == amt && t.category.major.contains('固定費');
    return nameHit || amtHit;
  }

  /// 同名の「固定費」実取引のうち、対象月に最も近いもの（カテゴリ/支払の踏襲元）。
  static core.Transaction? _template(
      List<core.Transaction> txns, String nn, int y, int m) {
    core.Transaction? best;
    var bestDist = 1 << 30;
    final target = y * 12 + m;
    for (final t in txns) {
      if (!t.category.major.contains('固定費')) continue;
      final nd = _norm(t.description);
      if (nn.isEmpty || nd.isEmpty) continue;
      if (!(nd.contains(nn) || nn.contains(nd))) continue;
      final dist = ((t.date.year * 12 + t.date.month) - target).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = t;
      }
    }
    return best;
  }
}
