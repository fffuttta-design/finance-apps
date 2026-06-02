import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_mode.dart';
import '../../data/backup_repository.dart';
import '../../data/monthly_snapshot_repository.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/account_detail_screen.dart';
import '../../screens/card_detail_screen.dart';
import '../../utils/formatters.dart';
import '../../utils/thousands_separator_input_formatter.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// マネフォ ME 風のホーム画面（v2.1）。
/// 3 カラム構成、v1 の Repository から実データを取得して表示。
/// - 左: 総資産 + 口座/カード残高一覧
/// - 中央: カンタン入力（v1 入力モーダル呼出） + 最新入出金 + 月の収支
/// - 右: 今月の予算（v1 未実装、placeholder）+ お知らせ
class V2HomeTopNavScreen extends StatefulWidget {
  /// アクセント色（事業=青 / 個人=オレンジ）
  final Color accent;

  const V2HomeTopNavScreen({super.key, required this.accent});

  @override
  State<V2HomeTopNavScreen> createState() => _V2HomeTopNavScreenState();
}

class _V2HomeTopNavScreenState extends State<V2HomeTopNavScreen>
    with ModeAwareMixin {
  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;
  final _snapshotRepo = MonthlySnapshotRepository.instance;

  StreamSubscription<List<Transaction>>? _sub;
  List<Transaction> _transactions = [];
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  MonthlySnapshotConfig _snapshots = MonthlySnapshotConfig.empty();
  bool _loading = true;

  /// 表示月（既定は今月、月切替で前後）
  late DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  /// 月初残高の口座別内訳展開
  bool _initialBreakdownExpanded = false;

  /// 当月支出の口座別内訳展開
  bool _expenseBreakdownExpanded = false;

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (!mounted) return;
      // 起動時に v1 と同じリマインダーを順に判定（同タイミングで2連発しない）
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _maybeShowSnapshotReminder();
        if (mounted) await _maybeShowBackupReminder();
      });
    });
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    PaymentsChangeNotifier.instance.addListener(_load);
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    super.dispose();
  }

  /// 月切替（外側 widget から呼べる公開メソッド）
  void shiftMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  /// 月チップ列からの絶対指定（外側 widget から呼べる公開メソッド）
  void selectMonth(DateTime m) {
    setState(() => _selectedMonth = DateTime(m.year, m.month));
  }

  /// 内訳の開閉トグル（外側 widget から呼べる公開メソッド）
  void toggleInitialBreakdown() {
    setState(() => _initialBreakdownExpanded = !_initialBreakdownExpanded);
  }

  void toggleExpenseBreakdown() {
    setState(() => _expenseBreakdownExpanded = !_expenseBreakdownExpanded);
  }

  /// 起動時に「当月の月初残高が未記録」ならダイアログで促す。
  /// - 1日は強制表示、それ以外は月内 1 回だけ
  Future<void> _maybeShowSnapshotReminder() async {
    final now = DateTime.now();
    final existing = _snapshots.forMonth(now.year, now.month);
    if (existing != null) return;

    final modePrefix = AppModeManager.instance.current.keyPrefix;
    final monthKey = MonthlySnapshot.monthKey(now.year, now.month);
    final shownKey = 'futa.snapshot_reminder.$modePrefix.$monthKey';
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(shownKey) ?? false;

    if (now.day != 1 && alreadyShown) return;
    if (!mounted) return;
    await openSnapshotDialog(forceCurrentMonth: true);
    await prefs.setBool(shownKey, true);
  }

  /// 「最後の手動バックアップから14日経過」で1回リマインド
  Future<void> _maybeShowBackupReminder() async {
    final state =
        await BackupRepository.instance.shouldRemindBackup();
    if (state != BackupReminderState.shouldRemind) return;
    if (!mounted) return;
    final last = await BackupRepository.instance.lastManualBackupAt();
    final days = last == null
        ? 0
        : DateTime.now().difference(last).inDays;
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: Color(0xFFEA580C)),
            SizedBox(width: 8),
            Text('バックアップしませんか？'),
          ],
        ),
        content: Text(
          '最後のバックアップから $days 日経ちました。\n'
          'Drive に書き出して安全に保管しておきましょう。',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'snooze'),
            child: const Text('あとで (3日)'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'export'),
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('書き出す'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );

    if (action == 'snooze') {
      await BackupRepository.instance.snoozeReminder(days: 3);
    } else if (action == 'export') {
      if (!mounted) return;
      await _runBackupExport();
    }
  }

  Future<void> _runBackupExport() async {
    try {
      final json = await BackupRepository.instance.exportAll();
      // Web は Share Plus が動かないので（kIsWeb 経由で別フロー）今回は
      // ファイル経由の Share に統一。Web は path_provider が動かないため
      // 例外を握って通知のみ。
      if (kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Web ではバックアップは設定画面から書き出してください')),
        );
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'futa-finance-backup-$stamp.json';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(json);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'FutaFinance バックアップ ($stamp)',
          text: 'FutaFinance のデータバックアップ ($stamp)。',
        ),
      );
      await BackupRepository.instance.markManualBackupDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('書き出しに失敗しました: $e')),
      );
    }
  }

  /// 月初残高入力ダイアログ（v1 と同じロジック）。
  Future<void> openSnapshotDialog({
    bool forceCurrentMonth = false,
  }) async {
    final now = DateTime.now();
    final suggestedBalance = _payments.bankAccounts
        .fold<int>(0, (s, b) => s + (b.displayBalance ?? 0));
    final controller =
        TextEditingController(text: formatAmount(suggestedBalance));

    final result = await showDialog<int?>(
      context: context,
      barrierDismissible: !forceCurrentMonth,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.event_note, color: Color(0xFF1A237E)),
            const SizedBox(width: 8),
            Text('${now.month}月の月初残高'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${now.year}年${now.month}月1日時点の銀行・現金・電子マネー合算残高を記録します。',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsSeparatorInputFormatter(),
              ],
              autofocus: true,
              decoration: InputDecoration(
                labelText: '残高（円）',
                hintText: '例: 1,000,000',
                helperText:
                    '提案: 現口座合算 ${formatYen(suggestedBalance)}',
                prefixText: '¥ ',
              ),
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('後で')),
          FilledButton(
            onPressed: () {
              final value = parseAmount(controller.text);
              Navigator.pop(context, value);
            },
            child: const Text('記録'),
          ),
        ],
      ),
    );

    if (result == null || result < 0) return;

    final snap = MonthlySnapshot(
      yearMonth: MonthlySnapshot.monthKey(now.year, now.month),
      initialBalance: result,
      recordedAt: now,
    );
    await _snapshotRepo.upsert(snap);
    final cfg = await _snapshotRepo.load();
    if (!mounted) return;
    setState(() => _snapshots = cfg);
  }

  /// 月初時点の各口座残高を逆算（現在残高 − 当月取引差分）
  Map<String, int> _calculateMonthStartBreakdown(
      List<Transaction> monthTxns) {
    final banks = _payments.bankAccounts;
    final bankNameSet = banks.map((b) => b.name).toSet();
    final delta = <String, int>{};
    for (final t in monthTxns) {
      if (t.type == TransactionType.transfer) {
        final from = t.transferFromAccount;
        final to = t.transferToAccount;
        if (from != null && bankNameSet.contains(from)) {
          delta[from] = (delta[from] ?? 0) - t.amount;
        }
        if (to != null && bankNameSet.contains(to)) {
          delta[to] = (delta[to] ?? 0) + t.amount;
        }
        continue;
      }
      if (!bankNameSet.contains(t.paymentMethod)) continue;
      if (t.type == TransactionType.income) {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) + t.amount;
      } else {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) - t.amount;
      }
    }
    final out = <String, int>{};
    for (final b in banks) {
      final current = b.displayBalance ?? 0;
      out[b.name] = current - (delta[b.name] ?? 0);
    }
    return out;
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final payments = await _settings.loadPayments();
    final snapshots = await _snapshotRepo.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _snapshots = snapshots;
      _loading = false;
    });
  }

  // ── 計算ヘルパー ──────────────────────────

  /// 各銀行口座の「現在残高」（startingBalance + 全期間の取引差分、振替対応）。
  int _bankBalanceOf(RegisteredBankAccount b) {
    int delta = 0;
    for (final t in _transactions) {
      if (t.type == TransactionType.transfer) {
        if (t.transferFromAccount == b.name) delta -= t.amount;
        if (t.transferToAccount == b.name) delta += t.amount;
        continue;
      }
      if (t.paymentMethod != b.name) continue;
      if (t.type == TransactionType.income) {
        delta += t.amount;
      } else {
        delta -= t.amount;
      }
    }
    return (b.startingBalance ?? 0) + delta;
  }

  /// クレカ別の当月利用額。
  Map<String, int> _cardUsageOfMonth(DateTime month) {
    final names = _payments.creditCards.map((c) => c.name).toSet();
    final out = <String, int>{};
    for (final t in _transactions) {
      if (t.date.year != month.year || t.date.month != month.month) continue;
      if (t.type != TransactionType.expense) continue;
      if (!names.contains(t.paymentMethod)) continue;
      out[t.paymentMethod] = (out[t.paymentMethod] ?? 0) + t.amount;
    }
    return out;
  }

  List<Transaction> _monthTxns(DateTime month) => _transactions
      .where((t) => t.date.year == month.year && t.date.month == month.month)
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Shell の Expanded 内で content として展開されるため、
    // ホームの 3 カラム / 縦並びがコンテンツ高を超えた場合に
    // スクロールできるよう、最上位に SingleChildScrollView を置く。
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth >= 1000;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 240, child: _LeftAssetSummary(state: this)),
              const SizedBox(width: V2Spacing.lg),
              Expanded(child: _CenterColumn(state: this)),
              const SizedBox(width: V2Spacing.lg),
              SizedBox(width: 240, child: _RightSidebar(state: this)),
            ],
          );
        }
        // モバイル並び順: カンタン入力 / ◯月の収支 / 最新の入出金（中央）
        // → 総資産 → 月初残高。
        return Column(
          children: [
            _CenterColumn(state: this),
            const SizedBox(height: V2Spacing.lg),
            _LeftAssetSummary(state: this),
            const SizedBox(height: V2Spacing.lg),
            _RightSidebar(state: this),
          ],
        );
      }),
    );
  }
}

// ═════════════════════════════════════════════════
// 左カラム: 総資産 + 口座/カード一覧
// ═════════════════════════════════════════════════

class _LeftAssetSummary extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _LeftAssetSummary({required this.state});

  @override
  Widget build(BuildContext context) {
    // 総資産 = 全銀行口座の現在残高合計
    final totalAsset = state._payments.bankAccounts
        .fold<int>(0, (s, b) => s + state._bankBalanceOf(b));

    // 前月末時点との差分（前月末日 23:59 を cutoff）
    final today = DateTime.now();
    final prevEnd = DateTime(today.year, today.month, 1)
        .subtract(const Duration(seconds: 1));
    final prevAsset = _assetAt(prevEnd);
    final delta = totalAsset - prevAsset;

    // クレカ当月利用
    final cardUsage = state._cardUsageOfMonth(state._selectedMonth);

    return V2Card(
      padding: const EdgeInsets.all(V2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('総資産',
              style: V2Typography.bodyStrong.copyWith(
                  color: V2Colors.textPrimary, fontSize: 13)),
          const SizedBox(height: V2Spacing.md),
          Text(formatYen(totalAsset),
              style: V2Typography.kpiValue
                  .copyWith(color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.sm),
          Row(
            children: [
              Icon(
                  delta >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 14,
                  color: delta >= 0
                      ? V2Colors.positive
                      : V2Colors.negative),
              const SizedBox(width: 4),
              Text(formatYen(delta, withSign: true),
                  style: V2Typography.caption.copyWith(
                      color: delta >= 0
                          ? V2Colors.positive
                          : V2Colors.negative,
                      fontWeight: FontWeight.w700,
                      fontFeatures: V2Typography.tabularNums)),
              const SizedBox(width: V2Spacing.xs),
              Text('前月末比',
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textSecondary)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: V2Spacing.md),
            child: Divider(height: 1),
          ),
          // 銀行口座リスト（タップで通帳＝口座詳細へ）
          for (final b in state._payments.bankAccounts)
            _AssetTile(
              icon: b.iconUrl,
              label: b.name,
              value: formatYen(state._bankBalanceOf(b)),
              valueColor: V2Colors.textPrimary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountDetailScreen(account: b)),
              ),
            ),
          // クレカ当月利用（マイナス表示・タップでカード詳細へ）
          for (final c in state._payments.creditCards)
            if ((cardUsage[c.name] ?? 0) > 0)
              _AssetTile(
                icon: c.iconUrl,
                label: c.name,
                value: '-${formatYen(cardUsage[c.name] ?? 0)}',
                valueColor: V2Colors.negative,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CardDetailScreen(card: c)),
                ),
              ),
          if (state._payments.bankAccounts.isEmpty &&
              state._payments.creditCards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '口座が未登録です。設定 → ウォレット から追加してください。',
                style: V2Typography.micro.copyWith(
                    color: V2Colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// 指定時刻時点の総資産。
  int _assetAt(DateTime cutoff) {
    final banks = state._payments.bankAccounts;
    int total = 0;
    for (final b in banks) {
      int delta = 0;
      for (final t in state._transactions) {
        if (t.date.isAfter(cutoff)) continue;
        if (t.type == TransactionType.transfer) {
          if (t.transferFromAccount == b.name) delta -= t.amount;
          if (t.transferToAccount == b.name) delta += t.amount;
          continue;
        }
        if (t.paymentMethod != b.name) continue;
        if (t.type == TransactionType.income) {
          delta += t.amount;
        } else {
          delta -= t.amount;
        }
      }
      total += (b.startingBalance ?? 0) + delta;
    }
    return total;
  }
}

class _AssetTile extends StatelessWidget {
  final String? icon;
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback? onTap;
  const _AssetTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          BrandLogo(
            iconUrl: icon,
            fallbackIcon: Icons.account_balance,
            size: 16,
            borderRadius: 4,
          ),
          const SizedBox(width: V2Spacing.sm),
          Expanded(
            child: Text(label,
                style: V2Typography.caption,
                overflow: TextOverflow.ellipsis),
          ),
          Text(value,
              style: V2Typography.caption.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 14, color: V2Colors.textMuted),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

// ═════════════════════════════════════════════════
// 中央カラム: カンタン入力 + 最新の入出金 + 月の収支
// ═════════════════════════════════════════════════

class _CenterColumn extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _CenterColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final monthTxns = state._monthTxns(state._selectedMonth);
    final incomeConfirmed = monthTxns
        .where((t) => t.type == TransactionType.income && !t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final incomePending = monthTxns
        .where((t) => t.type == TransactionType.income && t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final income = incomeConfirmed + incomePending;
    final expense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    final net = income - expense;
    final isBlack = net >= 0;

    // 支出内訳（支払方法別）
    final expenseByMethod = <String, int>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
      expenseByMethod[t.paymentMethod] =
          (expenseByMethod[t.paymentMethod] ?? 0) + t.amount;
    }
    final expenseBreakdown = expenseByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 推定残高 / 実測残高（今月のみ意味がある）
    final now = DateTime.now();
    final isCurrentMonth = state._selectedMonth.year == now.year &&
        state._selectedMonth.month == now.month;
    final snap = state._snapshots.forMonth(
        state._selectedMonth.year, state._selectedMonth.month);
    final initialBalance = snap?.initialBalance ?? 0;
    final projected = initialBalance + income - expense;
    final actual = isCurrentMonth
        ? state._payments.bankAccounts.fold<int>(
            0, (s, b) => s + (b.displayBalance ?? 0))
        : projected;
    final diff = actual - projected;

    // 最新の入出金: 日付降順で最新 5 件
    final recent = [...state._transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final recentTop = recent.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // カンタン入力セクションは廃止（右上「記録」ボタンで代替）。
        // ── 月の収支（最新の入出金より上に表示）──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${state._selectedMonth.year}年${state._selectedMonth.month}月の収支',
                  style: V2Typography.h2
                      .copyWith(color: V2Colors.textPrimary)),
              const SizedBox(height: V2Spacing.sm),
              // 月を横並びチップで切替（横スクロール）
              _MonthChipsBar(
                selected: state._selectedMonth,
                accent: state.widget.accent,
                onSelect: state.selectMonth,
              ),
              const SizedBox(height: V2Spacing.sm),
              _SummaryRow(
                  label: isBusiness ? '当月売上' : '当月収入',
                  value: formatYen(income, withSign: true),
                  color: V2Colors.positive),
              if (incomePending > 0)
                Padding(
                  padding: const EdgeInsets.only(left: V2Spacing.lg),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top,
                          size: 12, color: V2Colors.warning),
                      const SizedBox(width: 4),
                      Text('うち見込み',
                          style: V2Typography.micro
                              .copyWith(color: V2Colors.warning)),
                      const Spacer(),
                      Text(formatYen(incomePending, withSign: true),
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.warning,
                              fontWeight: FontWeight.w700,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
              const Divider(height: 1),
              // 支出行: タップで支払方法別の内訳展開
              InkWell(
                onTap: expenseBreakdown.isEmpty
                    ? null
                    : state.toggleExpenseBreakdown,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Text(isBusiness ? '当月経費' : '当月支出',
                          style: V2Typography.body),
                      if (expenseBreakdown.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Icon(
                            state._expenseBreakdownExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color: V2Colors.textSecondary),
                      ],
                      const Spacer(),
                      Text(formatYen(-expense, withSign: true),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: V2Colors.negative,
                            fontFeatures: V2Typography.tabularNums,
                          )),
                    ],
                  ),
                ),
              ),
              if (state._expenseBreakdownExpanded &&
                  expenseBreakdown.isNotEmpty) ...[
                for (final e in expenseBreakdown)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 16,
                        right: 0,
                        top: 4,
                        bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: V2Colors.negative
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.key,
                              style: V2Typography.caption,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(formatYen(-e.value),
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.negative,
                                fontWeight: FontWeight.w700,
                                fontFeatures:
                                    V2Typography.tabularNums)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
              ],
              const Divider(height: 1),
              // 黒字/赤字バッジ（v1 のホームと同じ「主役」扱い）
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: (isBlack
                          ? V2Colors.positiveSoft
                          : V2Colors.negativeSoft)
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(
                      V2Spacing.radiusMd),
                  border: Border.all(
                      color: (isBlack
                              ? V2Colors.positive
                              : V2Colors.negative)
                          .withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                            isBlack
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 22,
                            color: isBlack
                                ? V2Colors.positive
                                : V2Colors.negative),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(isBlack ? '黒字' : '赤字',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isBlack
                                        ? V2Colors.positive
                                        : V2Colors.negative,
                                    letterSpacing: 1)),
                            Text('差引（収入 − 支出）',
                                style: V2Typography.micro),
                          ],
                        ),
                      ],
                    ),
                    Text(formatYen(net, withSign: true),
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: isBlack
                                ? V2Colors.positive
                                : V2Colors.negative,
                            fontFeatures:
                                V2Typography.tabularNums)),
                  ],
                ),
              ),
              // 推定残高 / 実測残高（v1 のホームと同じ並び）
              if (snap != null) ...[
                const SizedBox(height: 12),
                Container(
                  height: 1,
                  color: V2Colors.divider,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text('推定残高', style: V2Typography.bodyStrong),
                    Text(formatYen(projected),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: projected >= 0
                              ? V2Colors.positive
                              : V2Colors.negative,
                          fontFeatures:
                              V2Typography.tabularNums,
                        )),
                  ],
                ),
                if (isCurrentMonth) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('実測 ${formatYen(actual)}',
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.textMuted,
                              fontFeatures:
                                  V2Typography.tabularNums)),
                      const SizedBox(width: 8),
                      Text(
                        diff == 0
                            ? '一致 ✓'
                            : '差 ${formatYen(diff, withSign: true)}',
                        style: V2Typography.micro.copyWith(
                          color: diff == 0
                              ? V2Colors.positive
                              : V2Colors.warning,
                          fontWeight: FontWeight.w700,
                          fontFeatures:
                              V2Typography.tabularNums,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        // ── 最新の入出金 ──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('最新の入出金',
                      style: V2Typography.h2
                          .copyWith(color: V2Colors.textPrimary)),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              if (recentTop.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('取引記録はまだありません',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary)),
                )
              else
                for (final t in recentTop) _TransactionRow(t: t),
            ],
          ),
        ),
      ],
    );
  }
}

/// 月を横並びチップで切り替えるバー（横スクロール）。
/// 当月を左端に置き、右へスクロールすると過去月。範囲外の選択月は追加表示。
class _MonthChipsBar extends StatelessWidget {
  final DateTime selected;
  final Color accent;
  final ValueChanged<DateTime> onSelect;
  const _MonthChipsBar({
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month);
    // 新しい月が先頭（左）。当月→12ヶ月前。
    final months = <DateTime>[
      for (int i = 0; i <= 12; i++) DateTime(base.year, base.month - i),
    ];
    if (!months.any(
        (m) => m.year == selected.year && m.month == selected.month)) {
      months.add(DateTime(selected.year, selected.month));
      months.sort((a, b) => b.compareTo(a));
    }
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: months.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = months[i];
          final isSel =
              m.year == selected.year && m.month == selected.month;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(m),
            child: Container(
              width: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel ? accent : V2Colors.surfaceMuted,
                borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
                border:
                    Border.all(color: isSel ? accent : V2Colors.border),
              ),
              child: Center(
                child: Text('${m.month}月',
                    style: V2Typography.bodyStrong.copyWith(
                        color: isSel
                            ? Colors.white
                            : V2Colors.textPrimary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Transaction t;
  const _TransactionRow({required this.t});

  String _typeLabel() {
    switch (t.type) {
      case TransactionType.income:
        return '収入';
      case TransactionType.expense:
        return '支出';
      case TransactionType.transfer:
        return '振替';
    }
  }

  String _categoryLabel() {
    final major = t.category.major.trim();
    final sub = t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return _typeLabel();
    if (sub.isEmpty) return major;
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final color = isTransfer
        ? V2Colors.textBody
        : (isIncome ? V2Colors.positive : V2Colors.negative);
    final sign = isTransfer ? '' : (isIncome ? '+' : '-');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: V2Colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text('${t.date.month}/${t.date.day}',
                  style: V2Typography.caption.copyWith(
                      fontFeatures: V2Typography.tabularNums))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
            ),
            child: Text(
              _categoryLabel(),
              style: V2Typography.micro,
            ),
          ),
          const SizedBox(width: V2Spacing.md),
          Expanded(
            child: Text(
              t.description.isEmpty ? t.paymentMethod : t.description,
              style: V2Typography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$sign${formatYen(t.amount)}',
              style: V2Typography.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(label, style: V2Typography.body),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: V2Typography.tabularNums,
              )),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 右カラム: 月初残高 + お知らせ
// ═════════════════════════════════════════════════

class _RightSidebar extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _RightSidebar({required this.state});

  @override
  Widget build(BuildContext context) {
    final snap = state._snapshots
        .forMonth(state._selectedMonth.year, state._selectedMonth.month);
    final today = DateTime.now();
    final isCurrentMonth = state._selectedMonth.year == today.year &&
        state._selectedMonth.month == today.month;
    final monthTxns = state._monthTxns(state._selectedMonth);
    // 月初残高内訳は今月のみ計算可能（過去月は履歴がないため）
    final breakdown = isCurrentMonth
        ? state._calculateMonthStartBreakdown(monthTxns)
        : <String, int>{};

    return Column(
      children: [
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${state._selectedMonth.month}月の月初残高',
                      style: V2Typography.bodyStrong.copyWith(
                          color: V2Colors.textPrimary, fontSize: 13)),
                  const Spacer(),
                  if (isCurrentMonth)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.edit,
                          color: V2Colors.textMuted),
                      onPressed: () => state.openSnapshotDialog(),
                      tooltip: '月初残高を編集',
                    ),
                ],
              ),
              const SizedBox(height: V2Spacing.sm),
              if (snap != null)
                InkWell(
                  onTap: breakdown.isEmpty
                      ? null
                      : state.toggleInitialBreakdown,
                  child: Row(
                    children: [
                      Text(formatYen(snap.initialBalance),
                          style: V2Typography.h1.copyWith(
                              color: V2Colors.textPrimary,
                              fontFeatures:
                                  V2Typography.tabularNums)),
                      if (breakdown.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Icon(
                            state._initialBreakdownExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 14,
                            color: V2Colors.textMuted),
                      ],
                    ],
                  ),
                )
              else ...[
                Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 14, color: V2Colors.warning),
                    const SizedBox(width: 4),
                    Text('未記録',
                        style: V2Typography.caption.copyWith(
                            color: V2Colors.warning,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: V2Spacing.xs),
                if (isCurrentMonth)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => state.openSnapshotDialog(),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('記録する'),
                  ),
              ],
              const SizedBox(height: V2Spacing.xs),
              Text(
                snap != null
                    ? 'タップで口座別内訳を展開'
                    : '残高の起点として記録できます',
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textSecondary),
              ),
              // 月初残高の口座別内訳展開
              if (state._initialBreakdownExpanded &&
                  breakdown.isNotEmpty) ...[
                const SizedBox(height: V2Spacing.sm),
                const Divider(height: 1),
                const SizedBox(height: V2Spacing.sm),
                for (final e in (breakdown.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: V2Colors.accent
                                .withValues(alpha: 0.5),
                            borderRadius:
                                BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.key,
                              style: V2Typography.micro,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(formatYen(e.value),
                            style: V2Typography.micro.copyWith(
                                color: V2Colors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontFeatures:
                                    V2Typography.tabularNums)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
