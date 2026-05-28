import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/monthly_snapshot_repository.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/ui_preferences.dart';
import '../utils/formatters.dart';
import '../widgets/brand_logo.dart';
import 'account_detail_screen.dart';

/// 資産タブ。
/// 銀行/現金/電子マネー（=「総資産」）の動きを俯瞰する画面。
/// クレジットカードは後払いなのでここには含めない（負債扱い）。
///
/// 構成（MVP1）:
///   - 総資産合計カード（前月末比）
///   - 口座別残高リスト
///   - 入出金履歴（時系列、資産口座に関連する取引のみ）
class AssetScreen extends StatefulWidget {
  const AssetScreen({super.key});

  @override
  State<AssetScreen> createState() => _AssetScreenState();
}

class _AssetScreenState extends State<AssetScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _settings = SettingsRepository();
  final _snapshotRepo = MonthlySnapshotRepository.instance;
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig? _payments;
  core.MonthlySnapshotConfig _snapshots =
      core.MonthlySnapshotConfig.empty();

  /// 「資産推移」セクションの開閉状態。デフォルトは開いた状態。
  bool _trendExpanded = true;

  /// 「口座別残高」セクションの開閉状態。デフォルトは開いた状態。
  bool _accountsExpanded = true;

  /// 「入出金履歴」セクションの開閉状態。デフォルトは開いた状態。
  bool _historyExpanded = true;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    // 通帳画面等で口座情報(startingBalance含む)が更新された時に再ロード
    PaymentsChangeNotifier.instance.addListener(_load);
    // 「残高0を隠す」設定の変更で再描画
    UiPreferences.instance.addListener(_onUiPrefsChanged);
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    UiPreferences.instance.removeListener(_onUiPrefsChanged);
    super.dispose();
  }

  void _onUiPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    final p = await _settings.loadPayments();
    final snaps = await _snapshotRepo.load();
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _payments = p;
      _snapshots = snaps;
    });
  }

  /// 資産口座（銀行/現金/電子マネー）の現在残高を口座IDキーで返す。
  Map<String, int> _currentBalances(
      List<core.RegisteredBankAccount> accounts) {
    final nameSet = accounts.map((a) => a.name).toSet();
    final delta = <String, int>{};
    for (final t in _transactions) {
      if (t.type == core.TransactionType.transfer) {
        final from = t.transferFromAccount;
        final to = t.transferToAccount;
        if (from != null && nameSet.contains(from)) {
          delta[from] = (delta[from] ?? 0) - t.amount;
        }
        if (to != null && nameSet.contains(to)) {
          delta[to] = (delta[to] ?? 0) + t.amount;
        }
        continue;
      }
      if (!nameSet.contains(t.paymentMethod)) continue;
      if (t.type == core.TransactionType.income) {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) + t.amount;
      } else {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) - t.amount;
      }
    }
    final out = <String, int>{};
    for (final a in accounts) {
      out[a.name] = (a.startingBalance ?? 0) + (delta[a.name] ?? 0);
    }
    return out;
  }

  /// 指定日以前の取引だけで残高を再計算（前月末時点など）。
  Map<String, int> _balancesAt(
      List<core.RegisteredBankAccount> accounts, DateTime cutoff) {
    final nameSet = accounts.map((a) => a.name).toSet();
    final delta = <String, int>{};
    for (final t in _transactions) {
      if (t.date.isAfter(cutoff)) continue;
      if (t.type == core.TransactionType.transfer) {
        final from = t.transferFromAccount;
        final to = t.transferToAccount;
        if (from != null && nameSet.contains(from)) {
          delta[from] = (delta[from] ?? 0) - t.amount;
        }
        if (to != null && nameSet.contains(to)) {
          delta[to] = (delta[to] ?? 0) + t.amount;
        }
        continue;
      }
      if (!nameSet.contains(t.paymentMethod)) continue;
      if (t.type == core.TransactionType.income) {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) + t.amount;
      } else {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) - t.amount;
      }
    }
    final out = <String, int>{};
    for (final a in accounts) {
      out[a.name] = (a.startingBalance ?? 0) + (delta[a.name] ?? 0);
    }
    return out;
  }

  /// 資産口座に関連する取引のみを時系列降順で返す。
  List<core.Transaction> _assetTransactions(
      List<core.RegisteredBankAccount> accounts) {
    final nameSet = accounts.map((a) => a.name).toSet();
    final filtered = _transactions.where((t) {
      if (t.type == core.TransactionType.transfer) {
        return nameSet.contains(t.transferFromAccount) ||
            nameSet.contains(t.transferToAccount);
      }
      return nameSet.contains(t.paymentMethod);
    }).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final p = _payments;
    if (p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // 計算は全口座でやってから、表示直前に hideInactive フィルタを掛ける。
    // ただし「残高が1円以上あれば休眠と見なさない」ので、隠れるのは
    // inactive && 残高<=0 の口座のみ。
    final allAccounts = p.bankAccounts;
    final allBalances = _currentBalances(allAccounts);
    final hideInactive = UiPreferences.instance.hideInactive;
    final accounts = hideInactive
        ? allAccounts
            .where((a) =>
                !(a.inactive && (allBalances[a.name] ?? 0) <= 0))
            .toList()
        : allAccounts;
    final balances = Map<String, int>.fromEntries(
        accounts.map((a) => MapEntry(a.name, allBalances[a.name] ?? 0)));
    final total = balances.values.fold<int>(0, (s, v) => s + v);

    // 前月末時点の残高で前月比を計算
    final now = DateTime.now();
    final prevMonthLast =
        DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
    // 23:59:59 まで含めるよう日付調整
    final cutoff = DateTime(prevMonthLast.year, prevMonthLast.month,
        prevMonthLast.day, 23, 59, 59);
    final prevBalances = _balancesAt(accounts, cutoff);
    final prevTotal =
        prevBalances.values.fold<int>(0, (s, v) => s + v);
    final delta = total - prevTotal;

    final txns = _assetTransactions(accounts);

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('資産', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _totalCard(total, delta),
            const SizedBox(height: 12),
            _savingsTrendCard(),
            const SizedBox(height: 12),
            _accountListCard(accounts, balances, total),
            const SizedBox(height: 12),
            _historyCard(txns, accounts),
          ],
        ),
      ),
    );
  }

  // ── 総資産合計カード ──
  Widget _totalCard(int total, int delta) {
    final isUp = delta >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.savings, color: Color(0xFF1A237E), size: 18),
              SizedBox(width: 6),
              Text('総資産',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatYen(total),
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: isUp
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 2),
              Text(
                '前月末比 ${formatYen(delta, withSign: true)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isUp
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '（クレカ後払い分は含まない）',
                style: TextStyle(
                    fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 口座別残高リスト（ドラッグ並び替え可） ──
  Widget _accountListCard(
      List<core.RegisteredBankAccount> accounts,
      Map<String, int> balances,
      int total) {
    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Center(
          child: Text(
            'まだ口座が登録されていません。設定 → ウォレットから追加してください。',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // 並び順は payments.bankAccounts のリスト順そのまま（ユーザー編集可能）
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // ヘッダー（タップで開閉）
          InkWell(
            onTap: () =>
                setState(() => _accountsExpanded = !_accountsExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      color: Color(0xFF1A237E), size: 16),
                  const SizedBox(width: 6),
                  const Text('口座別残高',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  const Spacer(),
                  if (_accountsExpanded) ...[
                    const Icon(Icons.drag_indicator,
                        color: Color(0xFFD1D5DB), size: 14),
                    const SizedBox(width: 4),
                    const Text('ドラッグで並び替え',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF))),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                      _accountsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: const Color(0xFF6B7280),
                      size: 20),
                ],
              ),
            ),
          ),
          if (_accountsExpanded) ...[
            const Divider(height: 1),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: accounts.length,
              itemBuilder: (ctx, i) {
                final a = accounts[i];
                return _accountRow(
                  key: ValueKey(a.id),
                  index: i,
                  a: a,
                  balance: balances[a.name] ?? 0,
                  total: total,
                );
              },
              onReorder: _onReorderAccounts,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onReorderAccounts(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final p = _payments;
    if (p == null) return;
    final list = List<core.RegisteredBankAccount>.from(p.bankAccounts);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final newPayments = core.PaymentMethodsConfig(
      bankAccounts: list,
      creditCards: p.creditCards,
    );
    setState(() => _payments = newPayments);
    try {
      await SettingsRepository.instance.savePayments(newPayments);
      PaymentsChangeNotifier.instance.notifyChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('並び順の保存に失敗しました: $e')),
      );
    }
  }

  Widget _accountRow({
    required Key key,
    required int index,
    required core.RegisteredBankAccount a,
    required int balance,
    required int total,
  }) {
    final share = total == 0 ? 0.0 : balance / total;
    return Container(
      key: key,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccountDetailScreen(account: a),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
          child: Row(
            children: [
              // ドラッグハンドル
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator,
                      color: Color(0xFFD1D5DB), size: 20),
                ),
              ),
              a.iconUrl != null && a.iconUrl!.isNotEmpty
                  ? BrandLogo(
                      iconUrl: a.iconUrl,
                      fallbackEmoji: a.accountType.emoji,
                      size: 32)
                  : Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(a.accountType.emoji,
                          style: const TextStyle(fontSize: 18)),
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text(
                      '${a.accountType.shortLabel}  ·  ${(share * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              Text(
                formatYen(balance),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: balance >= 0
                        ? const Color(0xFF111827)
                        : const Color(0xFFDC2626)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 18, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  // ── 入出金履歴カード ──
  Widget _historyCard(List<core.Transaction> txns,
      List<core.RegisteredBankAccount> accounts) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // ヘッダー（タップで開閉）
          InkWell(
            onTap: () =>
                setState(() => _historyExpanded = !_historyExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.history,
                      color: Color(0xFF1A237E), size: 16),
                  const SizedBox(width: 6),
                  const Text('入出金履歴',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  const Spacer(),
                  if (!_historyExpanded && txns.isNotEmpty)
                    Text(
                      '${txns.length > 100 ? "100+" : txns.length}件',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                      _historyExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: const Color(0xFF6B7280),
                      size: 20),
                ],
              ),
            ),
          ),
          if (_historyExpanded) ...[
            const Divider(height: 1),
            if (txns.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('まだ取引がありません',
                      style:
                          TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                ),
              )
            else
              // 最新100件まで（パフォーマンスとの兼ね合い）
              for (final t in txns.take(100)) _historyRow(t),
          ],
        ],
      ),
    );
  }

  Widget _historyRow(core.Transaction t) {
    // 振替・収入・支出 でアイコンと表記を変える
    late IconData icon;
    late Color color;
    late String headline;
    late int signedAmount;
    if (t.type == core.TransactionType.transfer) {
      icon = Icons.swap_horiz;
      color = const Color(0xFFEA580C);
      headline = '${t.transferFromAccount ?? '?'} → ${t.transferToAccount ?? '?'}';
      signedAmount = 0; // 振替は + も - も付かない（純総資産は不変）
    } else if (t.type == core.TransactionType.income) {
      icon = Icons.arrow_downward;
      color = const Color(0xFF16A34A);
      headline = '${t.paymentMethod} ← ${t.description}';
      signedAmount = t.amount;
    } else {
      icon = Icons.arrow_upward;
      color = const Color(0xFFDC2626);
      headline = '${t.paymentMethod} → ${t.description}';
      signedAmount = -t.amount;
    }
    // 表示順を「日付 → 明細 → 金額」に。日付を先頭に等幅で固定表示。
    final dateLabel =
        '${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}';
    final yearLabel = '${t.date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          // ── 日付（左端固定幅） ──
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      fontFamily: 'monospace'),
                ),
                Text(yearLabel,
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          // ── 明細 ──
          Expanded(
            child: Text(headline,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          // ── 金額（右端） ──
          Text(
            t.type == core.TransactionType.transfer
                ? formatYen(t.amount)
                : formatYen(signedAmount, withSign: true),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────
  // 資産推移カード（月初残高スナップショットの月次推移）
  // ───────────────────────────────────────────────

  /// 月初残高スナップショットから直近12ヶ月の推移を描画する。
  /// データが2点未満の場合はメッセージのみ。
  Widget _savingsTrendCard() {
    // 直近12ヶ月のスナップショットを年月昇順で抽出
    final all = List<core.MonthlySnapshot>.from(_snapshots.snapshots)
      ..sort((a, b) => a.yearMonth.compareTo(b.yearMonth));
    final last12 = all.length <= 12
        ? all
        : all.sublist(all.length - 12);

    // 純増減（最新月初残 − 最古月初残）。データ不足なら null。
    int? netDelta;
    if (last12.length >= 2) {
      netDelta = last12.last.initialBalance - last12.first.initialBalance;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // ヘッダー（タップで開閉）
          InkWell(
            onTap: () =>
                setState(() => _trendExpanded = !_trendExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.show_chart,
                      color: Color(0xFF16A34A), size: 16),
                  const SizedBox(width: 6),
                  const Text('資産推移',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  const SizedBox(width: 6),
                  Text(
                    '(${last12.length}ヶ月)',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF9CA3AF)),
                  ),
                  const Spacer(),
                  Icon(
                      _trendExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: const Color(0xFF6B7280),
                      size: 20),
                ],
              ),
            ),
          ),
          if (_trendExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: last12.length < 2
                  ? const _TrendEmpty()
                  : _TrendChart(
                      snapshots: last12,
                      netDelta: netDelta!,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 資産推移のデータ不足時メッセージ。
class _TrendEmpty extends StatelessWidget {
  const _TrendEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          '月初残高のスナップショットが 2ヶ月分以上ないと推移は描けません。\nホームの月初リマインドで毎月記録してください。',
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 資産推移の本体（直近1年の純増減 + 折れ線）。
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.snapshots, required this.netDelta});

  final List<core.MonthlySnapshot> snapshots;
  final int netDelta;

  @override
  Widget build(BuildContext context) {
    final isUp = netDelta >= 0;
    final color = isUp
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final firstLabel = _shortMonth(snapshots.first.yearMonth);
    final lastLabel = _shortMonth(snapshots.last.yearMonth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 純増減（主役） ──
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (isUp
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEE2E2))
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                      isUp
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 20,
                      color: color),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUp ? '貯金増加' : '貯金減少',
                        style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '$firstLabel → $lastLabel',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                formatYen(netDelta, withSign: true),
                style: TextStyle(
                    fontSize: 22,
                    color: color,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── 折れ線グラフ本体 ──
        SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _TrendLinePainter(snapshots: snapshots),
            child: Container(),
          ),
        ),
      ],
    );
  }

  /// 'YYYY-MM' → 'YY/M' (例: '2026-05' → '26/5')
  static String _shortMonth(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    final year = parts[0].length >= 4
        ? parts[0].substring(2)
        : parts[0];
    final month = int.tryParse(parts[1]) ?? 0;
    return '$year/$month';
  }
}

/// 折れ線グラフ + 各点の金額ラベル描画。
class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({required this.snapshots});

  final List<core.MonthlySnapshot> snapshots;

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.length < 2) return;

    // 余白（軸ラベル分）
    const leftPad = 4.0;
    const rightPad = 4.0;
    const topPad = 20.0; // 各点の金額ラベル分
    const bottomPad = 18.0; // X軸ラベル分

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final values = snapshots.map((s) => s.initialBalance).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = maxV - minV;
    // 平坦な時に y が NaN にならないよう
    final yRange = range == 0 ? 1 : range;

    final n = snapshots.length;
    Offset pointAt(int i) {
      final x = leftPad +
          (n == 1 ? chartW / 2 : chartW * i / (n - 1));
      final y = topPad +
          chartH * (1 - (values[i] - minV) / yRange);
      return Offset(x, y);
    }

    // 塗りエリア（グラデーション風の単色うすめ）
    final fillPath = Path()
      ..moveTo(leftPad, topPad + chartH);
    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      if (i == 0) {
        fillPath.lineTo(p.dx, p.dy);
      } else {
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    fillPath.lineTo(size.width - rightPad, topPad + chartH);
    fillPath.close();

    final fillPaint = Paint()
      ..color = const Color(0xFF16A34A).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 折れ線本体
    final linePaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (int i = 1; i < n; i++) {
      final p = pointAt(i);
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(linePath, linePaint);

    // 各点 + 金額/月ラベル
    final pointPaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..style = PaintingStyle.fill;
    final pointBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      canvas.drawCircle(p, 3.5, pointPaint);
      canvas.drawCircle(p, 3.5, pointBorder);

      // 金額ラベル（上）：データ点が多すぎる時は隔月ぐらいに間引く
      final showAmount = n <= 6 || i % 2 == 0 || i == n - 1;
      if (showAmount) {
        final tp = TextPainter(
          text: TextSpan(
            text: _shortYen(values[i]),
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF111827),
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(p.dx - tp.width / 2, p.dy - tp.height - 4),
        );
      }

      // 月ラベル（下）：全部書くと潰れるので、最初/最後/中間で十分
      final showMonth =
          i == 0 || i == n - 1 || (n > 4 && i % (n ~/ 4) == 0);
      if (showMonth) {
        final ym = snapshots[i].yearMonth.split('-');
        final label = ym.length == 2
            ? '${int.tryParse(ym[1]) ?? ''}月'
            : snapshots[i].yearMonth;
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF9CA3AF),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(p.dx - tp.width / 2,
              topPad + chartH + 4),
        );
      }
    }
  }

  /// 'XX 万' のような短縮表示。10000円以上で「万」、それ未満は素のまま。
  static String _shortYen(int v) {
    if (v.abs() >= 10000) {
      final man = (v / 10000).toStringAsFixed(v.abs() < 100000 ? 1 : 0);
      return '$man 万';
    }
    return v.toString();
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) =>
      oldDelegate.snapshots != snapshots;
}
