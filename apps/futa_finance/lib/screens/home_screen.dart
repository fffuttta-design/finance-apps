import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_mode.dart';
import '../data/backup_repository.dart';
import '../data/monthly_snapshot_repository.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/ui_preferences.dart';
import '../utils/formatters.dart';
import '../widgets/brand_logo.dart';
import 'account_detail_screen.dart';
import 'card_detail_screen.dart';
import 'expense_input_screen.dart';
import 'income_input_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;
  final _snapshotRepo = MonthlySnapshotRepository.instance;
  StreamSubscription<List<Transaction>>? _sub;

  List<Transaction> _transactions = [];
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  MonthlySnapshotConfig _snapshots = MonthlySnapshotConfig.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _maybeShowSnapshotReminder();
        // 月初リマインダーが出てない時のみ、14日バックアップリマインダーを判定。
        // 同タイミングで2連発ダイアログは出さない。
        if (mounted) await _maybeShowBackupReminder();
      });
    });
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    // ウォレット編集や通帳画面で payments が更新された時に再ロード
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

  /// 当月のスナップショットが未設定なら、リマインドダイアログを表示する。
  /// - 1日: 必ず表示
  /// - その他の日: その月でまだ一度も表示してなければ表示（1回限り）
  Future<void> _maybeShowSnapshotReminder() async {
    final now = DateTime.now();
    final existing = _snapshots.forMonth(now.year, now.month);
    if (existing != null) return; // 既に記録済み

    final modePrefix = AppModeManager.instance.current.keyPrefix;
    final monthKey = MonthlySnapshot.monthKey(now.year, now.month);
    final shownKey = 'futa.snapshot_reminder.$modePrefix.$monthKey';
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(shownKey) ?? false;

    // 1日は強制表示、それ以外は1回まで
    if (now.day != 1 && alreadyShown) return;

    if (!mounted) return;
    await _showSnapshotDialog(forceCurrentMonth: true);
    await prefs.setBool(shownKey, true);
  }

  /// 「最後の手動バックアップから14日経過」で起動時に1回リマインドする。
  /// 一度もバックアップしてない人には出さない（押し付けがましくないように）。
  Future<void> _maybeShowBackupReminder() async {
    final state = await BackupRepository.instance.shouldRemindBackup();
    if (state != BackupReminderState.shouldRemind) return;
    if (!mounted) return;

    final last = await BackupRepository.instance.lastManualBackupAt();
    final days =
        last == null ? 0 : DateTime.now().difference(last).inDays;
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: const [
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
      // 設定画面のバックアップ書き出しと同じフロー（共有シート）
      await _runBackupExportFromReminder();
    }
  }

  /// リマインダー経由でバックアップ書き出しを実行。
  /// 設定画面の _exportBackup と同じ処理を最小限で再現。
  Future<void> _runBackupExportFromReminder() async {
    try {
      final json = await BackupRepository.instance.exportAll();
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
          text:
              'FutaFinance のデータバックアップ ($stamp)。\n'
              '保存先推奨: マイドライブ/ツール開発/FutaFinance/backups/',
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

  /// 月初残高入力ダイアログ。
  Future<void> _showSnapshotDialog({bool forceCurrentMonth = false}) async {
    final now = DateTime.now();
    final suggestedBalance = _payments.bankAccounts
        .fold<int>(0, (s, b) => s + (b.displayBalance ?? 0));
    final controller =
        TextEditingController(text: suggestedBalance.toString());

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
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '残高（円）',
                hintText: '例: 1000000',
                helperText: '提案: 現口座合算 ${formatYen(suggestedBalance)}',
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
              final value = int.tryParse(controller.text.trim());
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

  /// 当月の取引のみ。
  List<Transaction> _monthTxns(DateTime today) => _transactions
      .where((t) => t.date.year == today.year && t.date.month == today.month)
      .toList();

  void _openAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.remove_circle_outline,
                    color: Color(0xFFDC2626)),
              ),
              title: const Text('支出を追加',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('経費・購入・引き落としなど',
                  style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(sheet);
                showExpenseInputModal(context).then((_) => _load());
              },
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF16A34A)),
              ),
              title: const Text('収入を追加',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('売上・入金など（収入マスタから選択）',
                  style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(sheet);
                showIncomeInputModal(context).then((_) => _load());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance, size: 22, color: Color(0xFF1A237E)),
            SizedBox(width: 8),
            Text(
              'FutaFinance',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Color(0xFF111827)),
            ),
          ],
        ),
        actions: [
          // 「+ 記録」ボタン: アイコンだけより目を引く + 用途が一目で分かる
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: FilledButton.icon(
              onPressed: _openAddSheet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('記録'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 0),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _todayHeader(today),
                  const SizedBox(height: 12),
                  _monthlyFlow(today),
                  const SizedBox(height: 12),
                  _balanceSummary(),
                  const SizedBox(height: 24),
                  _footer(),
                ],
              ),
            ),
    );
  }

  // ===================== Section: 今日 =====================

  Widget _todayHeader(DateTime today) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.today,
                color: Color(0xFF1A237E), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('今日',
                  style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(
                '${today.year}年${today.month}月${today.day}日（${weekdayKanji(today)}）',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== Section: 月次フロー =====================

  Widget _monthlyFlow(DateTime today) {
    final snap = _snapshots.forMonth(today.year, today.month);
    final monthTxns = _monthTxns(today);
    final income = monthTxns
        .where((t) => t.type == TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    final initial = snap?.initialBalance ?? 0;
    final projected = initial + income - expense;
    final actual = _payments.bankAccounts
        .fold<int>(0, (s, b) => s + (b.displayBalance ?? 0));
    final diff = actual - projected;

    return _card(
      icon: Icons.timeline,
      iconColor: const Color(0xFF1A237E),
      title: '今月のフロー（${today.month}月）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snap == null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '月初残高が未記録',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _showSnapshotDialog,
                    child: const Text('記録する'),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '月初残高 (${today.month}/1)',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ),
                Text(
                  formatYen(snap.initialBalance),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      fontFamily: 'monospace'),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.edit, color: Color(0xFF9CA3AF)),
                  onPressed: _showSnapshotDialog,
                  tooltip: '月初残高を編集',
                ),
              ],
            ),
          const SizedBox(height: 8),
          _flowRow(
              AppModeManager.instance.current == AppMode.business
                  ? '+ 当月売上'
                  : '+ 当月収入',
              formatYen(income, withSign: true),
              const Color(0xFF16A34A)),
          _flowRow(
              AppModeManager.instance.current == AppMode.business
                  ? '- 当月経費'
                  : '- 当月支出',
              formatYen(-expense, withSign: true),
              const Color(0xFFDC2626)),
          const SizedBox(height: 10),
          // ── 差引（主役）────────────────────────────────
          // この月の収支が黒字 / 赤字かを一番大きく見せる。
          // ホームを開いた瞬間に「今月の調子」が読み取れるようにする。
          Builder(builder: (_) {
            final net = income - expense;
            final isBlack = net >= 0;
            final color = isBlack
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626);
            final bgColor = isBlack
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFFEE2E2);
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                          isBlack
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 22,
                          color: color),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBlack ? '黒字' : '赤字',
                            style: TextStyle(
                                fontSize: 14,
                                color: color,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1),
                          ),
                          const Text(
                            '差引（収入 − 支出）',
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    formatYen(net, withSign: true),
                    style: TextStyle(
                        fontSize: 28,
                        color: color,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('推定残高',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w600)),
              Text(
                formatYen(projected),
                style: TextStyle(
                    fontSize: 20,
                    color: projected >= 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          if (snap != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '実測 ${formatYen(actual)}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Text(
                  diff == 0
                      ? '一致 ✓'
                      : '差 ${formatYen(diff, withSign: true)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: diff == 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFEA580C),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _flowRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ===================== Section: 残高 =====================

  Widget _balanceSummary() {
    final allBanks = _payments.bankAccounts;
    final today = DateTime.now();
    final hideZero = UiPreferences.instance.hideZeroBalance;

    // 銀行/現金/電子マネーの現在残高 = startingBalance + 全期間の取引集計（入金 - 出金）
    // ユーザーは startingBalance だけ手動入力し、以降は取引から自動増減。
    // 振替(transfer)は from を減、to を増として残高に反映。
    // 注: bankNameSet は集計用なので「全銀行」を対象にする（hideZero フィルタは
    //     最終的な表示・合計の段階だけに適用、計算ロジック自体は素通し）。
    final bankNameSet = allBanks.map((b) => b.name).toSet();
    final bankDelta = <String, int>{};
    for (final t in _transactions) {
      if (t.type == TransactionType.transfer) {
        final from = t.transferFromAccount;
        final to = t.transferToAccount;
        if (from != null && bankNameSet.contains(from)) {
          bankDelta[from] = (bankDelta[from] ?? 0) - t.amount;
        }
        if (to != null && bankNameSet.contains(to)) {
          bankDelta[to] = (bankDelta[to] ?? 0) + t.amount;
        }
        continue;
      }
      if (!bankNameSet.contains(t.paymentMethod)) continue;
      if (t.type == TransactionType.income) {
        bankDelta[t.paymentMethod] =
            (bankDelta[t.paymentMethod] ?? 0) + t.amount;
      } else {
        bankDelta[t.paymentMethod] =
            (bankDelta[t.paymentMethod] ?? 0) - t.amount;
      }
    }
    int currentBalanceOf(RegisteredBankAccount b) =>
        (b.startingBalance ?? 0) + (bankDelta[b.name] ?? 0);

    // クレカ累積は「当月の取引集計（クレカ支払い分の合計）」で自動計算する。
    // 引落日等の概念は持たず、月初リセットの簡易ルール。
    final cardNameSet =
        _payments.creditCards.map((c) => c.name).toSet();
    final cardUsage = <String, int>{};
    for (final t in _transactions) {
      if (t.date.year != today.year || t.date.month != today.month) continue;
      if (t.type != TransactionType.expense) continue;
      if (!cardNameSet.contains(t.paymentMethod)) continue;
      cardUsage[t.paymentMethod] =
          (cardUsage[t.paymentMethod] ?? 0) + t.amount;
    }

    // 当月利用が 0 のカードはホーム画面には表示しない（残高表示の混雑回避）。
    // さらに hideZero=ON なら累積額 0 のカードを「休眠中」として除外。
    final cards = _payments.creditCards
        .where((c) {
          final usage = cardUsage[c.name] ?? 0;
          if (usage <= 0) return false;
          return true;
        })
        .toList();

    // 表示対象の銀行: hideZero=ON なら現在残高 0 を除外。
    final banks = hideZero
        ? allBanks.where((b) => currentBalanceOf(b) != 0).toList()
        : allBanks;

    final assetTotal =
        banks.fold<int>(0, (s, b) => s + currentBalanceOf(b));
    final cardTotal =
        cards.fold<int>(0, (s, c) => s + (cardUsage[c.name] ?? 0));
    final netWorth = assetTotal - cardTotal;

    // 前月末時点の総資産（前月末比を出すため）
    final prevMonthEnd = DateTime(today.year, today.month, 1)
        .subtract(const Duration(seconds: 1));
    final prevAssetTotal = _assetTotalAt(banks, prevMonthEnd);
    final assetDelta = assetTotal - prevAssetTotal;

    return _card(
      icon: Icons.account_balance_wallet,
      iconColor: const Color(0xFF1A237E),
      title: '残高',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (banks.isEmpty && cards.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'ウォレット/カードが未登録です。設定 → ウォレット から追加してください。',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            )
          else ...[
            // ── 総資産センター表示（一番上に大きく） ──
            if (banks.isNotEmpty) ...[
              _totalAssetCenter(assetTotal, assetDelta),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 8),
            ],
            // 内訳: 銀行 / 現金 / 電子マネー（残高は自動計算）
            ...banks.map((b) => _balanceRow(b, currentBalanceOf(b))),
            // クレカ累積（当月利用合計を自動集計）
            // これは来月の引き落とし予定なので、想定残高では資産から引かれる扱い
            if (cards.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 8),
              ...cards.map((c) =>
                  _cardBalanceRow(c, cardUsage[c.name] ?? 0)),
              _subtotalRow('予定差し引き額（クレカ引落予定）', -cardTotal,
                  color: const Color(0xFFDC2626)),
            ],
            // 想定残高 = 総資産 − 予定差し引き額（クレカ）
            // クレカが無い場合でも総資産 = 想定残高で表示（一貫性のため）
            if (banks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(height: 1, color: const Color(0xFF1A237E)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('想定残高',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w700)),
                      if (cards.isNotEmpty)
                        const Text('（クレカ引落後）',
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF9CA3AF))),
                    ],
                  ),
                  Text(
                    formatYen(netWorth),
                    style: TextStyle(
                        fontSize: 22,
                        color: netWorth >= 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// 指定日時点の総資産を再計算（前月末比などに使用）。
  int _assetTotalAt(
      List<RegisteredBankAccount> banks, DateTime cutoff) {
    final nameSet = banks.map((b) => b.name).toSet();
    final delta = <String, int>{};
    for (final t in _transactions) {
      if (t.date.isAfter(cutoff)) continue;
      if (t.type == TransactionType.transfer) {
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
      if (t.type == TransactionType.income) {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) + t.amount;
      } else {
        delta[t.paymentMethod] =
            (delta[t.paymentMethod] ?? 0) - t.amount;
      }
    }
    int total = 0;
    for (final b in banks) {
      total += (b.startingBalance ?? 0) + (delta[b.name] ?? 0);
    }
    return total;
  }

  /// 総資産センター表示。残高セクション最上部に大きく出す。
  Widget _totalAssetCenter(int total, int delta) {
    final isUp = delta >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '総資産',
            style: TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          Text(
            formatYen(total),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: isUp
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 2),
              Text(
                '前月末比 ${formatYen(delta, withSign: true)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUp
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceRow(RegisteredBankAccount b, int balance) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountDetailScreen(account: b),
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            // ロゴ画像（iconUrl があれば画像、無ければ種別の絵文字フォールバック）
            BrandLogo(
              iconUrl: b.iconUrl,
              fallbackEmoji: b.accountType.emoji,
              size: 20,
              borderRadius: 4,
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                b.accountType.shortLabel,
                style:
                    const TextStyle(fontSize: 9, color: Color(0xFF6B7280)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(b.name,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF111827)),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              formatYen(balance),
              style: TextStyle(
                  fontSize: 13,
                  color: balance >= 0
                      ? const Color(0xFF111827)
                      : const Color(0xFFDC2626),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 14, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  Widget _cardBalanceRow(RegisteredCreditCard c, int amount) {
    return InkWell(
      onTap: () {
        // クレカ詳細（明細画面）に遷移
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CardDetailScreen(card: c),
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            // ロゴ画像（iconUrl があれば画像、無ければ 💳 フォールバック）
            BrandLogo(
              iconUrl: c.iconUrl,
              fallbackEmoji: '💳',
              size: 20,
              borderRadius: 4,
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '当月',
                style: TextStyle(fontSize: 9, color: Color(0xFFDC2626)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(c.name,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF111827)),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              formatYen(-amount, withSign: true),
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFDC2626),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 14, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  Widget _subtotalRow(String label, int amount, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          Text(
            formatYen(amount),
            style: TextStyle(
                fontSize: 14,
                color: color,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ===================== 共通 =====================

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _footer() {
    return Column(
      children: [
        // PackageInfo から動的にバージョン取得（ハードコード防止）
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final v = snap.data?.version ?? '---';
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'v$v',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A237E),
                    letterSpacing: 0.4),
              ),
            );
          },
        ),
      ],
    );
  }
}
