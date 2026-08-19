import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../data/app_mode.dart';
import '../../data/month_cursor.dart';
import '../../data/monthly_snapshot_repository.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../data/ui_preferences.dart';
import '../../screens/account_detail_screen.dart';
import '../../screens/card_detail_screen.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/subscription_list_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/consumption_filter.dart' as cf;
import '../../utils/formatters.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/furusato_alert_card.dart';

/// 新デザイン（リッチUI）のホーム画面。
///
/// 既存の [TransactionRepository] などからデータを取得して描画する独立画面。
/// 現行ホーム（V2HomeTopNavScreen）には一切手を入れず、トグルで切替える。
/// 主役カード＝「今月の収支」（総資産は資産タブへ）。旧ホームの主要な数字
/// （見込み収入・推定/実測残高・固定費）も引き継ぐ。
class RichHomeScreen extends StatefulWidget {
  /// アクセント色（事業=青 / 個人=オレンジ）
  final Color accent;
  const RichHomeScreen({super.key, required this.accent});

  @override
  State<RichHomeScreen> createState() => _RichHomeScreenState();
}

class _RichHomeScreenState extends State<RichHomeScreen> with ModeAwareMixin {
  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;
  final _snapshotRepo = MonthlySnapshotRepository.instance;

  StreamSubscription<List<Transaction>>? _sub;
  List<Transaction> _transactions = [];
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  MonthlySnapshotConfig _snapshots = MonthlySnapshotConfig.empty();
  List<Subscription> _subs = [];
  bool _loading = true;
  String? _error;

  // 表示月はタブ横断で共有（共有カーソルを初期値に。切替で今月へ戻さない）。
  late DateTime _month = MonthCursor.instance.month;

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    PaymentsChangeNotifier.instance.addListener(_load);
    MonthCursor.instance.addListener(_onMonthCursor);
  }

  /// 他タブで月が変わったら追従。
  void _onMonthCursor() {
    final m = MonthCursor.instance.month;
    if (!mounted) return;
    if (m.year != _month.year || m.month != _month.month) {
      setState(() => _month = DateTime(m.year, m.month));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    MonthCursor.instance.removeListener(_onMonthCursor);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await (() async {
        final txns = await _txRepo.loadAll();
        final payments = await _settings.loadPayments();
        final snapshots = await _snapshotRepo.load();
        final subs = await SubscriptionRepository.instance.load();
        return (txns, payments, snapshots, subs);
      })()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _transactions = data.$1;
        _payments = data.$2;
        _snapshots = data.$3;
        _subs = data.$4.subscriptions;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  int _subsTotalForMonth(DateTime m,
      {bool Function(Subscription)? excludeSub}) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    // 実取引化済み（fixedcost_* 明細やカードCSVミラー）の固定費は予定合計に足さない
    // ＝二重計上しない。実取引側（通信費など本来のカテゴリ）で計上済み。
    // excludeSub 指定時は、その固定費（家賃・税金など）も合計から外す＝消費ベース。
    final matched = _matchedSubIds(m);
    return _subs.fold<int>(
        0,
        (s, sub) => (matched.contains(sub.id) ||
                (excludeSub?.call(sub) ?? false))
            ? s
            : s + sub.plAmountForMonth(ym, curYm));
  }

  /// 名前の正規化（実取引との照合用）。支出タブ(rich_expenses)と同じ規則。
  String _normName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[（）()【】\[\]・:：\s　]'), '');

  /// その月に「実取引が存在する」固定費サブスクのID集合。
  /// 実取引があるサブスクは、予定行を出さず・二重計上もしない（実取引を採用）。
  /// 照合＝同月の支出取引を、①名前一致 ②金額一致 の順で1対1に割り当てる。
  Set<String> _matchedSubIds(DateTime m) {
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final txns = _transactions
        .where((t) =>
            t.type == TransactionType.expense &&
            t.date.year == m.year &&
            t.date.month == m.month)
        .toList();
    final claimed = <String>{};
    final matched = <String>{};
    for (final sub in _subs) {
      final exp = sub.isVariable ? sub.monthlyActuals[ym] : sub.amount;
      final nname = _normName(sub.name);
      Transaction? hit;
      if (nname.isNotEmpty) {
        for (final t in txns) {
          if (claimed.contains(t.id)) continue;
          final nd = _normName(t.description);
          if (nd.isNotEmpty && (nd.contains(nname) || nname.contains(nd))) {
            hit = t;
            break;
          }
        }
      }
      if (hit == null && exp != null && exp > 0) {
        for (final t in txns) {
          if (claimed.contains(t.id)) continue;
          if (t.amount == exp) {
            hit = t;
            break;
          }
        }
      }
      if (hit != null) {
        claimed.add(hit.id);
        matched.add(sub.id);
      }
    }
    return matched;
  }

  List<Transaction> _monthTxns(DateTime m) => _transactions
      .where((t) => t.date.year == m.year && t.date.month == m.month)
      .toList();

  /// 月初総資産＝各口座の「その月初より前」の残高（startingBalance＋Σ）の合計。
  /// 通帳(account_detail_screen)と同じ規則で口座別に積み上げて合算する。
  /// ミラー運用で全口座が銀行明細と一致しているため、CSVを取り込むたびに
  /// 自動で正しくなる（手入力の MonthlySnapshot が無くても月初残高が出る）。
  int _monthStartTotalAssets(DateTime month) {
    final monthFirst = DateTime(month.year, month.month, 1);
    var total = 0;
    for (final acc in _payments.bankAccounts) {
      if (acc.inactive) continue; // 休眠口座は資産に数えない
      var bal = acc.startingBalance ?? 0;
      final name = acc.name;
      for (final t in _transactions) {
        if (!t.date.isBefore(monthFirst)) continue; // 月初以降は除外
        if (t.type == TransactionType.transfer) {
          if (t.transferFromAccount == name) {
            bal -= t.amount;
          } else if (t.transferToAccount == name) {
            bal += t.amount;
          }
        } else if (t.paymentMethod == name) {
          bal += t.type == TransactionType.income ? t.amount : -t.amount;
        }
      }
      total += bal;
    }
    return total;
  }

  /// 支払方法名 → 対応するウォレットの詳細画面へ。クレカ＝CardDetailScreen、
  /// 銀行/現金/電子マネー＝AccountDetailScreen（通帳）。未登録の支払方法は何もしない。
  Future<void> _openWalletDetail(String name) async {
    // 「固定費・サブスク」は実際のウォレットではないので固定費一覧を開く。
    if (name == '固定費・サブスク') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionListScreen()),
      );
      if (mounted) await _load();
      return;
    }
    for (final c in _payments.creditCards) {
      if (c.name == name) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CardDetailScreen(card: c)),
        );
        if (mounted) await _load();
        return;
      }
    }
    for (final b in _payments.bankAccounts) {
      if (b.name == name) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AccountDetailScreen(account: b)),
        );
        if (mounted) await _load();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: V2Colors.textMuted),
              const SizedBox(height: 12),
              Text('読み込みに失敗しました\n$_error',
                  textAlign: TextAlign.center, style: V2Typography.caption),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('再読み込み'),
              ),
            ],
          ),
        ),
      );
    }

    final isBusiness = AppModeManager.instance.current == AppMode.business;
    final accent = widget.accent;
    final monthTxns = _monthTxns(_month);

    // 収支（見込み込みの売上・経費）
    final incomeConfirmed = monthTxns
        .where((t) => t.type == TransactionType.income && !t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final incomePending = monthTxns
        .where((t) => t.type == TransactionType.income && t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final income = incomeConfirmed + incomePending;
    final txExpense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.effectiveAmount);
    final subTotal = _subsTotalForMonth(_month);
    final expense = txExpense + subTotal;
    final net = income - expense;

    // 主役カードの「今月の支出」を消費ベースにする（個人モードのみ）。
    // 家賃・税金は"絶対にかかる金"で、見たいのは「今月いくら消費に使ったか」。
    // ＝表示専用の除外。収支(net)・残高計算からは外さない（実額のまま）。
    final rentHidden = !isBusiness && UiPreferences.instance.hideRentHome;
    int heroExpense = expense;
    if (rentHidden) {
      final txCons = monthTxns
          .where((t) =>
              t.type == TransactionType.expense && !cf.isRentOrTaxTx(t))
          .fold<int>(0, (s, t) => s + t.effectiveAmount);
      final subCons =
          _subsTotalForMonth(_month, excludeSub: cf.isRentOrTaxSub);
      heroExpense = txCons + subCons;
    }

    // 推定残高 / 実測残高（旧ホームと同じ）
    final now = DateTime.now();
    final isCurrentMonth =
        _month.year == now.year && _month.month == now.month;
    final snap = _snapshots.forMonth(_month.year, _month.month);
    // 月初残高＝手入力スナップショットがあればそれ、無ければ口座残高から自動計算。
    final initialBalance =
        snap?.initialBalance ?? _monthStartTotalAssets(_month);
    final projected = initialBalance + income - expense;
    final actual = isCurrentMonth
        ? _payments.bankAccounts
            .where((b) => !b.inactive) // 休眠口座は実測残高に数えない
            .fold<int>(0, (s, b) => s + (b.displayBalance ?? 0))
        : projected;
    final diff = actual - projected;

    // カテゴリ内訳（大カテゴリ別・固定費込み）＋ドリルダウン用の明細。
    final byMajor = <String, int>{};
    final txnsByMajor = <String, List<Transaction>>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.effectiveAmount;
      (txnsByMajor[major] ??= []).add(t);
    }
    // 固定費（サブスク）当月分の明細（名前・金額）。
    final fixedLines = <({String name, int amount})>[];
    {
      final nowYm =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final ym =
          '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      // 実取引化済みの固定費は「固定費・サブスク」明細から除外（実カテゴリ側で計上済み）。
      final matched = _matchedSubIds(_month);
      for (final sub in _subs) {
        if (matched.contains(sub.id)) continue;
        final amt = sub.plAmountForMonth(ym, nowYm);
        if (amt > 0) {
          fixedLines.add(
              (name: sub.name.trim().isEmpty ? '固定費' : sub.name, amount: amt));
        }
      }
      fixedLines.sort((a, b) => b.amount.compareTo(a.amount));
    }
    if (subTotal > 0) {
      byMajor['固定費・サブスク'] = (byMajor['固定費・サブスク'] ?? 0) + subTotal;
    }
    final majorEntries = byMajor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final byMajorTotal = byMajor.values.fold<int>(0, (s, v) => s + v);

    // 最近の取引（当月・日付降順）。同じレシート（receiptId 2件以上）は
    // 1行にまとめ（②レシートまとめ）、先頭から最大8単位を表示。
    final recent = [...monthTxns]..sort((a, b) => b.date.compareTo(a.date));
    final recentUnits = _groupByReceipt(recent).take(8).toList();

    // ① 支払方法別の内訳（実際の支出伝票だけ・金額降順）。
    // 固定費・サブスクはここに足さない（実際の支払はクレカ／銀行の伝票側に
    // 出るので、足すと同じ支出を二重に見せてしまう）。
    final byMethod = <String, int>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
      byMethod[t.paymentMethod] = (byMethod[t.paymentMethod] ?? 0) + t.effectiveAmount;
    }
    final methodEntries = byMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final hero = _HeroCard(
      accent: accent,
      monthLabel: '${_month.year}年${_month.month}月',
      net: net,
      income: income,
      incomePending: incomePending,
      expense: heroExpense,
      isBusiness: isBusiness,
      // 個人モードのみ「家賃・税金を除く／除外中」トグルを主役カードに出す。
      showExcludeToggle: !isBusiness,
      excludeActive: rentHidden,
      onToggleExclude: () async {
        await UiPreferences.instance
            .setHideRentHome(!UiPreferences.instance.hideRentHome);
        if (mounted) setState(() {});
      },
    );

    final balanceCard = _BalanceCard(
      hasSnap: true, // 月初残高は常に自動計算で出る（手入力が無くても未記録にしない）
      isCurrentMonth: isCurrentMonth,
      projected: projected,
      actual: actual,
      diff: diff,
      fixedCost: subTotal,
    );

    final categoryCard = _CategoryCard(
      entries: majorEntries,
      total: byMajorTotal,
      accent: accent,
      txnsByMajor: txnsByMajor,
      fixedLines: fixedLines,
    );

    final recentCard = _RecentCard(
      accent: accent,
      isBusiness: isBusiness,
      month: _month,
      units: recentUnits,
      onTapTxn: (t) async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transaction: t)),
        );
        if (changed == true) await _load();
      },
      onSeeAll: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExpenseListScreen(
              title: isBusiness ? '経費明細一覧' : '支出明細一覧',
              month: _month,
            ),
          ),
        );
        await _load();
      },
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.lg, horizontal: V2Spacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: LayoutBuilder(builder: (ctx, c) {
            final wide = c.maxWidth >= 820;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 期限が近いときだけ出る（12月＝枠の使い残し /
                // 1〜3月＝ワンストップの申請期限・受領証明書の未着）。
                const FurusatoAlertCard(),
                hero,
                const SizedBox(height: V2Spacing.md),
                balanceCard,
                if (methodEntries.isNotEmpty) ...[
                  const SizedBox(height: V2Spacing.md),
                  _MethodBreakdownCard(
                    entries: methodEntries,
                    accent: accent,
                    tappable: {
                      for (final c in _payments.creditCards) c.name,
                      for (final b in _payments.bankAccounts) b.name,
                    },
                    iconByName: {
                      for (final c in _payments.creditCards)
                        if ((c.iconUrl ?? '').trim().isNotEmpty)
                          c.name: c.iconUrl!.trim(),
                      for (final b in _payments.bankAccounts)
                        if ((b.iconUrl ?? '').trim().isNotEmpty)
                          b.name: b.iconUrl!.trim(),
                    },
                    onTapMethod: _openWalletDetail,
                  ),
                ],
                const SizedBox(height: V2Spacing.md),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: categoryCard),
                        const SizedBox(width: V2Spacing.lg),
                        Expanded(child: recentCard),
                      ],
                    ),
                  )
                else ...[
                  categoryCard,
                  const SizedBox(height: V2Spacing.md),
                  recentCard,
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 今月の収支ヒーローカード（アクセント色の主役カード）
// ═════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final Color accent;
  final String monthLabel;
  final int net;
  final int income;
  final int incomePending;
  final int expense;
  final bool isBusiness;

  /// 「家賃・税金を除く」トグルを主役カードに出すか（個人モードのみ true）。
  final bool showExcludeToggle;

  /// 現在、家賃・税金を除外表示中か（＝expense は消費ベース）。
  final bool excludeActive;

  /// トグルのタップ（除外 ON/OFF を反転）。
  final VoidCallback? onToggleExclude;
  const _HeroCard({
    required this.accent,
    required this.monthLabel,
    required this.net,
    required this.income,
    required this.incomePending,
    required this.expense,
    required this.isBusiness,
    this.showExcludeToggle = false,
    this.excludeActive = false,
    this.onToggleExclude,
  });

  @override
  Widget build(BuildContext context) {
    final isBlack = net >= 0;
    // ⬇ 濃いベタ塗り（accent 一色）をやめ、白ベース＋要点だけ色。
    // 数字は墨色で大きく出し、モード色(accent)はアイコンチップだけに使う。
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
        boxShadow: const [
          BoxShadow(
            color: V2Colors.shadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.trending_down, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
              Text(isBusiness ? '今月の経費' : '今月の支出',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.textSecondary)),
              const Spacer(),
              // 月の切替はトップバーの共有月ナビへ集約。ここは表示のみ。
              Text(monthLabel,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: V2Colors.textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          // 主役の数字＝今月の支出額（収支ではなく支出を大きく）。
          Text(formatYen(expense),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: V2Colors.textPrimary,
                fontFeatures: V2Typography.tabularNums,
              )),
          if (incomePending > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.hourglass_top,
                    size: 14, color: V2Colors.warning),
                const SizedBox(width: 5),
                Text(
                    '${isBusiness ? '売上' : '収入'}のうち見込み ${formatYen(incomePending, withSign: true)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: V2Colors.textSecondary,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
          ],
          if (showExcludeToggle) ...[
            const SizedBox(height: 8),
            // 主役の数字を邪魔しないよう、右寄せ・控えめ（グレー小）にする。
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onToggleExclude,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: V2Colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          excludeActive
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 13,
                          color: V2Colors.textMuted),
                      const SizedBox(width: 5),
                      Text(
                          excludeActive ? '家賃・税金を除外中' : '家賃・税金を除く',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: V2Colors.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: V2Spacing.md),
          Row(
            children: [
              Expanded(
                child: _HeroSubTile(
                  bg: V2Colors.surfaceMuted,
                  label: isBusiness ? '今月の売上' : '今月の収入',
                  value: formatYen(income),
                  valueColor: V2Colors.badgeGreen,
                  labelColor: V2Colors.textSecondary,
                ),
              ),
              const SizedBox(width: V2Spacing.md),
              Expanded(
                child: _HeroSubTile(
                  bg: V2Colors.surfaceMuted,
                  label: '今月の収支',
                  value: formatYen(net, withSign: true),
                  valueColor:
                      isBlack ? V2Colors.badgeGreen : V2Colors.negative,
                  labelColor: V2Colors.textSecondary,
                  badge: isBlack ? '黒字' : '赤字',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSubTile extends StatelessWidget {
  final Color bg;
  final String label;
  final String value;
  final Color valueColor;
  final Color labelColor;

  /// ラベル右のミニバッジ（例: 黒字/赤字）。null なら出さない。
  final String? badge;
  const _HeroSubTile({
    required this.bg,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.labelColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: labelColor)),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: valueColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(badge!,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: valueColor)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 残高カード（推定残高 / 実測残高 / 固定費）
// ═════════════════════════════════════════════════

class _BalanceCard extends StatelessWidget {
  final bool hasSnap;
  final bool isCurrentMonth;
  final int projected;
  final int actual;
  final int diff;
  final int fixedCost;
  const _BalanceCard({
    required this.hasSnap,
    required this.isCurrentMonth,
    required this.projected,
    required this.actual,
    required this.diff,
    required this.fixedCost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.md),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
      ),
      child: Row(
        children: [
          // 推定残高
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('推定残高',
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textSecondary)),
                const SizedBox(height: 4),
                if (hasSnap)
                  Text(formatYen(projected),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: projected >= 0
                              ? V2Colors.positive
                              : V2Colors.negative,
                          fontFeatures: V2Typography.tabularNums))
                else
                  Text('月初残高 未記録',
                      style: V2Typography.caption
                          .copyWith(color: V2Colors.warning)),
                if (hasSnap && isCurrentMonth) ...[
                  const SizedBox(height: 3),
                  Text(
                      '実測 ${formatYen(actual)} / ${diff == 0 ? '一致 ✓' : '差 ${formatYen(diff, withSign: true)}'}',
                      style: V2Typography.micro.copyWith(
                          color: diff == 0
                              ? V2Colors.positive
                              : V2Colors.warning,
                          fontFeatures: V2Typography.tabularNums)),
                ] else if (!hasSnap) ...[
                  const SizedBox(height: 3),
                  Text('資産タブで記録できます',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                ],
              ],
            ),
          ),
          Container(width: 1, height: 38, color: V2Colors.divider),
          // 固定費
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: V2Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.repeat,
                          size: 15, color: V2Colors.textSecondary),
                      const SizedBox(width: 5),
                      Text('今月の固定費',
                          style: V2Typography.caption
                              .copyWith(color: V2Colors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(formatYen(fixedCost),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: V2Colors.textPrimary,
                          fontFeatures: V2Typography.tabularNums)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// カテゴリ内訳カード（横スタックバー + 凡例）
// ═════════════════════════════════════════════════

const List<Color> _kCatPalette = [
  Color(0xFF378ADD),
  Color(0xFF1D9E75),
  Color(0xFFEF9F27),
  Color(0xFFD4537E),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
];
const Color _kCatOther = Color(0xFFB4B2A9);

const String _kFixedCostKey = '固定費・サブスク';

class _CategoryCard extends StatefulWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  final Color accent;
  final Map<String, List<Transaction>> txnsByMajor;
  final List<({String name, int amount})> fixedLines;
  const _CategoryCard({
    required this.entries,
    required this.total,
    required this.accent,
    required this.txnsByMajor,
    required this.fixedLines,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final total = widget.total;
    // 凡例＝上位5＋「その他」。色はパレットを循環。
    final top = entries.take(5).toList();
    final rest = entries.skip(5).toList();
    final restTotal = rest.fold<int>(0, (s, e) => s + e.value);
    final segments = <({String name, int value, Color color})>[
      for (int i = 0; i < top.length; i++)
        (name: top[i].key, value: top[i].value, color: _kCatPalette[i]),
      if (restTotal > 0) (name: 'その他', value: restTotal, color: _kCatOther),
    ];

    return Container(
      padding: const EdgeInsets.all(V2Spacing.md),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('カテゴリ内訳',
              style: V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.md),
          if (segments.isEmpty || total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('この月の支出はまだありません',
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  for (final s in segments)
                    Expanded(
                      flex: (s.value * 1000 ~/ total).clamp(1, 1000000),
                      child: Container(height: 10, color: s.color),
                    ),
                ],
              ),
            ),
            const SizedBox(height: V2Spacing.sm),
            for (final s in segments) _legendRow(s, rest),
          ],
        ],
      ),
    );
  }

  Widget _legendRow(
      ({String name, int value, Color color}) s,
      List<MapEntry<String, int>> rest) {
    final isOther = s.name == 'その他';
    final open = _open == s.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = open ? null : s.name),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.name,
                      style: V2Typography.body,
                      overflow: TextOverflow.ellipsis),
                ),
                Text(formatYen(s.value),
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary,
                        fontFeatures: V2Typography.tabularNums)),
                const SizedBox(width: 4),
                Icon(open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: V2Colors.textMuted),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 19, bottom: 6),
            child: Column(children: _detailRows(s.name, isOther, rest)),
          ),
      ],
    );
  }

  List<Widget> _detailRows(
      String name, bool isOther, List<MapEntry<String, int>> rest) {
    // 「その他」＝残りのカテゴリ合計を一覧。
    if (isOther) {
      if (rest.isEmpty) return [_noDetail()];
      return [for (final e in rest) _amountRow(e.key, e.value)];
    }
    // 固定費＝各サブスクの名前・金額。
    if (name == _kFixedCostKey) {
      if (widget.fixedLines.isEmpty) return [_noDetail()];
      return [for (final f in widget.fixedLines) _amountRow(f.name, f.amount)];
    }
    // 通常カテゴリ＝そのカテゴリの取引明細。
    final txns = widget.txnsByMajor[name] ?? const <Transaction>[];
    if (txns.isEmpty) return [_noDetail()];
    return [
      for (final t in txns)
        _amountRow(
            t.description.trim().isEmpty
                ? formatMonthDay(t.date)
                : '${formatMonthDay(t.date)}  ${t.description.trim()}',
            t.amount),
    ];
  }

  Widget _amountRow(String label, int amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(formatYen(amount),
                style: V2Typography.caption.copyWith(
                    color: V2Colors.textSecondary,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      );

  Widget _noDetail() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('明細なし',
              style: V2Typography.caption.copyWith(color: V2Colors.textMuted)),
        ),
      );
}

// ═════════════════════════════════════════════════
// 最近の取引カード
// ═════════════════════════════════════════════════

class _RecentCard extends StatelessWidget {
  final Color accent;
  final bool isBusiness;
  final DateTime month;
  final List<_RecentUnit> units;
  final void Function(Transaction) onTapTxn;
  final VoidCallback onSeeAll;
  const _RecentCard({
    required this.accent,
    required this.isBusiness,
    required this.month,
    required this.units,
    required this.onTapTxn,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.md),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${month.month}月の取引',
                  style:
                      V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
              const Spacer(),
              InkWell(
                onTap: onSeeAll,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Text('すべて見る',
                          style: V2Typography.caption.copyWith(color: accent)),
                      Icon(Icons.chevron_right, size: 16, color: accent),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.sm),
          if (units.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('取引記録はまだありません',
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
            )
          else
            for (int i = 0; i < units.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: V2Colors.divider),
              if (units[i].isGroup)
                _ReceiptGroupRow(
                    members: units[i].members!, onTapMember: onTapTxn)
              else
                _TxnRow(
                    t: units[i].single!,
                    onTap: () => onTapTxn(units[i].single!)),
            ],
        ],
      ),
    );
  }
}

/// 最近の取引の表示単位：単品（single）か、同じレシートのまとめ（group）。
class _RecentUnit {
  final Transaction? single;
  final List<Transaction>? members;
  const _RecentUnit.single(this.single) : members = null;
  const _RecentUnit.group(this.members) : single = null;
  bool get isGroup => members != null;
}

/// 同じ receiptId が2件以上 → まとめ（group）、それ以外 → 単品（single）。
/// 並び順は渡された行の順を保つ。
List<_RecentUnit> _groupByReceipt(List<Transaction> rows) {
  final counts = <String, int>{};
  for (final t in rows) {
    final rid = t.receiptId;
    if (rid != null && rid.isNotEmpty) counts[rid] = (counts[rid] ?? 0) + 1;
  }
  final units = <_RecentUnit>[];
  final seen = <String>{};
  for (final t in rows) {
    final rid = t.receiptId;
    if (rid != null && rid.isNotEmpty && (counts[rid] ?? 0) >= 2) {
      if (seen.add(rid)) {
        units.add(_RecentUnit.group(
            rows.where((x) => x.receiptId == rid).toList()));
      }
    } else {
      units.add(_RecentUnit.single(t));
    }
  }
  return units;
}

/// レシートまとめ行：合計を1行で表示し、タップで品目を展開。
class _ReceiptGroupRow extends StatefulWidget {
  final List<Transaction> members;
  final void Function(Transaction) onTapMember;
  const _ReceiptGroupRow(
      {required this.members, required this.onTapMember});

  @override
  State<_ReceiptGroupRow> createState() => _ReceiptGroupRowState();
}

class _ReceiptGroupRowState extends State<_ReceiptGroupRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final total = members.fold<int>(0, (s, t) => s + t.amount);
    final first = members.first;
    final storeRaw = first.store?.trim() ?? '';
    final store = storeRaw.isNotEmpty
        ? storeRaw
        : (first.description.trim().isNotEmpty
            ? first.description.trim()
            : first.paymentMethod);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: V2Colors.negative.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.receipt_long,
                      size: 16, color: V2Colors.negative),
                ),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$store ほか',
                          style: V2Typography.bodyStrong,
                          overflow: TextOverflow.ellipsis, maxLines: 1),
                      const SizedBox(height: 2),
                      Text(
                          '${formatMonthDay(first.date)} · ${members.length}件まとめ・${first.paymentMethod}',
                          style: V2Typography.micro
                              .copyWith(color: V2Colors.textMuted),
                          overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
                const SizedBox(width: V2Spacing.sm),
                Text('-${formatYen(total)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: V2Colors.negative,
                        fontFeatures: V2Typography.tabularNums)),
                const SizedBox(width: 2),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: V2Colors.textMuted),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 38, bottom: 6),
            child: Column(
              children: [
                for (final t in members)
                  InkWell(
                    onTap: () => widget.onTapMember(t),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                t.description.trim().isEmpty
                                    ? (t.category.sub.trim().isEmpty
                                        ? '品目'
                                        : t.category.sub.trim())
                                    : t.description.trim(),
                                style: V2Typography.caption.copyWith(
                                    color: V2Colors.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text('-${formatYen(t.amount)}',
                              style: V2Typography.caption.copyWith(
                                  color: V2Colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: V2Typography.tabularNums)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// ① 支払方法別の内訳カード（既定は展開＝中身が見える状態）。
class _MethodBreakdownCard extends StatefulWidget {
  final List<MapEntry<String, int>> entries;
  final Color accent;

  /// 詳細画面へ飛べる支払方法名（登録済みの口座・カード名）。
  final Set<String> tappable;

  /// 支払方法名 → ブランドロゴURL（登録済みで iconUrl があるものだけ）。
  final Map<String, String> iconByName;

  /// 行タップ時に呼ぶ（支払方法名を渡す）。
  final void Function(String name) onTapMethod;
  const _MethodBreakdownCard(
      {required this.entries,
      required this.accent,
      required this.tappable,
      required this.iconByName,
      required this.onTapMethod});

  @override
  State<_MethodBreakdownCard> createState() => _MethodBreakdownCardState();
}

class _MethodBreakdownCardState extends State<_MethodBreakdownCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final total = widget.entries.fold<int>(0, (s, e) => s + e.value);
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 17, color: V2Colors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('支払方法別の内訳',
                            style: V2Typography.bodyStrong
                                .copyWith(color: V2Colors.textPrimary)),
                        Text('立替を差し引いた実支払額',
                            style: V2Typography.micro
                                .copyWith(color: V2Colors.textMuted)),
                      ],
                    ),
                  ),
                  Text(formatYen(total),
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary,
                          fontFeatures: V2Typography.tabularNums)),
                  const SizedBox(width: 4),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: V2Colors.textMuted),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  V2Spacing.md, 0, V2Spacing.md, V2Spacing.sm),
              child: Column(
                children: [
                  for (final e in widget.entries) ...[
                    const Divider(height: 1, color: V2Colors.divider),
                    _MethodRow(
                      name: e.key,
                      amount: e.value,
                      accent: widget.accent,
                      iconUrl: widget.iconByName[e.key],
                      tappable: widget.tappable.contains(e.key),
                      onTap: () => widget.onTapMethod(e.key),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 支払方法別内訳の1行。登録済みウォレット（[tappable]）なら押して詳細へ飛べる
/// （右端に「>」を出す）。未登録の支払方法（固定費・サブスク等）はタップ不可。
class _MethodRow extends StatelessWidget {
  final String name;
  final int amount;
  final Color accent;
  final String? iconUrl;
  final bool tappable;
  final VoidCallback onTap;
  const _MethodRow({
    required this.name,
    required this.amount,
    required this.accent,
    required this.iconUrl,
    required this.tappable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          BrandLogo(
            iconUrl: iconUrl,
            size: 24,
            borderRadius: 6,
            fallbackIcon: Icons.account_balance_wallet_outlined,
            fallbackBgColor: accent.withValues(alpha: 0.12),
            fallbackFgColor: accent.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: V2Typography.body, overflow: TextOverflow.ellipsis),
          ),
          Text(formatYen(amount),
              style: V2Typography.caption.copyWith(
                  color: V2Colors.textSecondary,
                  fontFeatures: V2Typography.tabularNums)),
          if (tappable) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 18, color: V2Colors.textMuted),
          ] else
            const SizedBox(width: 20),
        ],
      ),
    );
    if (!tappable) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

class _TxnRow extends StatelessWidget {
  final Transaction t;
  final VoidCallback onTap;
  const _TxnRow({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final IconData icon;
    final Color tint;
    if (isIncome) {
      icon = Icons.south_west;
      tint = V2Colors.positive;
    } else if (isTransfer) {
      icon = Icons.swap_horiz;
      tint = V2Colors.textSecondary;
    } else {
      icon = Icons.receipt_long_outlined;
      tint = V2Colors.negative;
    }
    final sign = isTransfer ? '' : (isIncome ? '+' : '-');
    final cat = t.category.sub.trim().isNotEmpty
        ? t.category.sub.trim()
        : t.category.major.trim();
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (cat.isNotEmpty ? cat : t.paymentMethod);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: V2Typography.bodyStrong,
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                  const SizedBox(height: 2),
                  Text(
                      '${formatMonthDay(t.date)} · ${cat.isEmpty ? t.paymentMethod : '$cat・${t.paymentMethod}'}',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('$sign${formatYen(t.amount)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isTransfer ? V2Colors.textBody : tint,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}
