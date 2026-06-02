import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../utils/thousands_separator_input_formatter.dart';
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

  /// ホームで表示する月。デフォルトは今月。月切替バーで前後に動かす。
  late DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  /// 月初残高の内訳展開フラグ。
  bool _initialBreakdownExpanded = false;

  /// 経費内訳の展開フラグ。
  bool _expenseBreakdownExpanded = false;

  /// 残高セクションで銀行口座を「全件展開」しているか。
  /// false の時は上位3件のみ表示。
  bool _allBanksExpanded = false;

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
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
                  // 表示順は「月切替 → 今日 → フロー」。
                  // 月切替が画面のメイン軸なので一番上、その下に補助情報の今日。
                  _monthSwitcher(),
                  const SizedBox(height: 8),
                  _todayHeader(today),
                  const SizedBox(height: 12),
                  _monthlyFlow(_selectedMonth),
                  const SizedBox(height: 12),
                  _balanceSummary(_selectedMonth),
                  const SizedBox(height: 24),
                  _footer(),
                ],
              ),
            ),
    );
  }

  // ===================== Section: 月切替 =====================

  /// 月送りバー。「< 2026年5月 >」+ 今月に戻るボタン。
  Widget _monthSwitcher() {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                color: Color(0xFF1A237E)),
            onPressed: () => setState(() {
              _selectedMonth = DateTime(
                  _selectedMonth.year, _selectedMonth.month - 1);
            }),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedMonth = DateTime(now.year, now.month);
              }),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_selectedMonth.year}年${_selectedMonth.month}月',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827)),
                    ),
                    if (!isCurrentMonth)
                      const Text('タップで今月に戻る',
                          style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right,
                color: Color(0xFF1A237E)),
            onPressed: () => setState(() {
              _selectedMonth = DateTime(
                  _selectedMonth.year, _selectedMonth.month + 1);
            }),
          ),
        ],
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

  Widget _monthlyFlow(DateTime month) {
    final monthTxns = _monthTxns(month);
    // 売上は「確定」と「見込み」に分けて集計。
    // 見込みは銀行残高に反映されていないので別行で見せる。
    final incomeConfirmed = monthTxns
        .where((t) =>
            t.type == TransactionType.income && !t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final incomePending = monthTxns
        .where((t) =>
            t.type == TransactionType.income && t.isPending)
        .fold<int>(0, (s, t) => s + t.amount);
    final income = incomeConfirmed + incomePending;
    final expense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    // 経費内訳（ウォレット別）。当月の支出取引を支払方法でグループ化。
    final expenseByMethod = <String, int>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
      expenseByMethod[t.paymentMethod] =
          (expenseByMethod[t.paymentMethod] ?? 0) + t.amount;
    }
    final expenseBreakdown = expenseByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _card(
      icon: Icons.timeline,
      iconColor: const Color(0xFF1A237E),
      title: '${month.month}月のフロー',
      iconSize: 22,
      titleGap: 8,
      titleStyle: const TextStyle(
        fontSize: 20,
        color: Color(0xFF111827),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 当月の収支のみシンプルに ──
          // 月初残高/推定残高/実測残高は「残高」セクションへ移動済。
          // 当月売上（確定） / 収入 — リスト風の長方形カード
          _flowListItem(
            label: AppModeManager.instance.current == AppMode.business
                ? '＋ 当月売上（確定）'
                : '＋ 当月収入',
            value: formatYen(incomeConfirmed, withSign: true),
            fg: const Color(0xFF16A34A),
            bg: const Color(0xFFECFDF5),
            border: const Color(0xFFA7F3D0),
          ),
          // 当月売上（見込み）— 金額がある時だけ
          if (incomePending > 0)
            _flowListItem(
              label: '＋ 当月売上（見込み）',
              value: formatYen(incomePending, withSign: true),
              fg: const Color(0xFFD97706),
              bg: const Color(0xFFFFFBEB),
              border: const Color(0xFFFDE68A),
              leadingIcon: Icons.hourglass_top,
            ),
          // 当月経費 / 支出 — タップで内訳展開
          _flowListItem(
            label: AppModeManager.instance.current == AppMode.business
                ? '－ 当月経費'
                : '－ 当月支出',
            value: formatYen(-expense, withSign: true),
            fg: const Color(0xFFDC2626),
            bg: const Color(0xFFFEF2F2),
            border: const Color(0xFFFECACA),
            showExpand: expenseBreakdown.isNotEmpty,
            expanded: _expenseBreakdownExpanded,
            onTap: expenseBreakdown.isEmpty
                ? null
                : () => setState(() => _expenseBreakdownExpanded =
                    !_expenseBreakdownExpanded),
          ),
          if (_expenseBreakdownExpanded &&
              expenseBreakdown.isNotEmpty) ...[
            const SizedBox(height: 2),
            ...expenseBreakdown.map((e) {
              final logo = _logoFor(e.key);
              return Padding(
                padding: const EdgeInsets.only(
                    left: 12, right: 4, top: 3, bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626)
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    BrandLogo(
                        iconUrl: logo.iconUrl,
                        fallbackEmoji: logo.emoji,
                        size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280)),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      formatYen(-e.value),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFDC2626),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 10),
          // ── 差引（主役）────────────────────────────────
          // この月の収支が黒字 / 赤字かを一番大きく見せる。
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
        ],
      ),
    );
  }

  /// 月初時点の各口座残高を逆算する。
  /// 現在の displayBalance から「今月の取引差分」を引いた値が月初残高。
  /// 振替は from を増（戻す）、to を減（戻す）として扱う。
  Map<String, int> _calculateMonthStartBreakdown(
      List<Transaction> monthTxns) {
    final banks = _payments.bankAccounts;
    final bankNameSet = banks.map((b) => b.name).toSet();

    // 今月の取引差分を口座別に計算
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

    // 月初残高 = 現在残高 - 今月の差分
    final out = <String, int>{};
    for (final b in banks) {
      final current = b.displayBalance ?? 0;
      out[b.name] = current - (delta[b.name] ?? 0);
    }
    return out;
  }

  /// 支払方法名（銀行/カード名）からロゴ用 iconUrl と fallback 絵文字を引く。
  /// 該当しなければ null/デフォルトを返す。
  ({String? iconUrl, String emoji}) _logoFor(String name) {
    for (final b in _payments.bankAccounts) {
      if (b.name == name) {
        return (iconUrl: b.iconUrl, emoji: b.accountType.emoji);
      }
    }
    for (final c in _payments.creditCards) {
      if (c.name == name) {
        return (iconUrl: c.iconUrl, emoji: '💳');
      }
    }
    return (iconUrl: null, emoji: '📦');
  }

  /// 内訳一覧を口座別タイルで返す（月初残高内訳の表示用）。
  List<Widget> _breakdownTiles(Map<String, int> breakdown) {
    final entries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) {
      final logo = _logoFor(e.key);
      return Padding(
        padding:
            const EdgeInsets.only(left: 12, right: 4, top: 3, bottom: 3),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color:
                    const Color(0xFF1A237E).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            BrandLogo(
                iconUrl: logo.iconUrl,
                fallbackEmoji: logo.emoji,
                size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(e.key,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              formatYen(e.value),
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF111827),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// フローの収支行を「淡い色背景＋枠」のリストアイテムとして描画する。
  /// [showExpand] が true の時は展開シェブロンを出し、[onTap] で開閉する。
  Widget _flowListItem({
    required String label,
    required String value,
    required Color fg,
    required Color bg,
    required Color border,
    IconData? leadingIcon,
    bool showExpand = false,
    bool expanded = false,
    VoidCallback? onTap,
  }) {
    final content = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: fg, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          if (showExpand) ...[
            const SizedBox(width: 4),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 16, color: fg.withValues(alpha: 0.7)),
          ],
          const Spacer(),
          Text(
            value,
            style: TextStyle(
                fontSize: 15,
                color: fg,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: content,
    );
  }

  // ===================== Section: 残高 =====================

  Widget _balanceSummary(DateTime month) {
    final allBanks = _payments.bankAccounts;
    final today = DateTime.now();
    final hideInactive = UiPreferences.instance.hideInactive;

    // 月初残高（残高の起点）。
    final snap = _snapshots.forMonth(month.year, month.month);
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;
    final monthTxns = _monthTxns(month);
    final initialBreakdown = isCurrentMonth
        ? _calculateMonthStartBreakdown(monthTxns)
        : <String, int>{};

    // 銀行/現金/電子マネーの現在残高 = startingBalance + 全期間の取引集計（入金 - 出金）
    // ユーザーは startingBalance だけ手動入力し、以降は取引から自動増減。
    // 振替(transfer)は from を減、to を増として残高に反映。
    // 注: bankNameSet は集計用なので「全銀行」を対象にする（hideInactive フィルタは
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
    // さらに hideInactive=ON でも、累積額（当月利用+過去入力）が 1円以上なら
    // 休眠と見なさず表示する。
    final cards = _payments.creditCards
        .where((c) {
          final usage = cardUsage[c.name] ?? 0;
          if (usage <= 0) return false;
          final accum = usage + c.displayBalance;
          if (hideInactive && c.inactive && accum <= 0) return false;
          return true;
        })
        .toList();

    // 表示対象の銀行: hideInactive=ON でも、残高が1円以上あれば
    // 「休眠と見なさない」ので表示する（フラグ自動無視）。
    // 隠れるのは inactive && 残高<=0 の口座のみ。
    final banks = hideInactive
        ? allBanks
            .where((b) => !(b.inactive && currentBalanceOf(b) <= 0))
            .toList()
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
      title: '総資産',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 月初残高（残高の起点。フローから移動）──────────
          // snap == null の時は警告バナー、ある時は数値表示（編集 + 内訳タップ）。
          if (snap == null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                  Expanded(
                    child: Text(
                      '${month.month}月の月初残高が未記録',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
                  if (isCurrentMonth)
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
          else ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: initialBreakdown.isEmpty
                  ? null
                  : () => setState(() => _initialBreakdownExpanded =
                      !_initialBreakdownExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '${month.month}月初残高 (${month.month}/1)',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600),
                          ),
                          if (initialBreakdown.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _initialBreakdownExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 14,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      formatYen(snap.initialBalance),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                          fontFamily: 'monospace'),
                    ),
                    if (isCurrentMonth)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 14,
                        padding: const EdgeInsets.only(left: 4),
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.edit,
                            color: Color(0xFF9CA3AF)),
                        onPressed: _showSnapshotDialog,
                        tooltip: '月初残高を編集',
                      ),
                  ],
                ),
              ),
            ),
            if (_initialBreakdownExpanded &&
                initialBreakdown.isNotEmpty) ...[
              const SizedBox(height: 4),
              ..._breakdownTiles(initialBreakdown),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 8),
          ],
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
            // 残高が大きい順にソート → 上位3件は常時表示、残りは折りたたみ。
            // 縦に長くなりがちな口座リストを圧縮し、ホーム画面のスクロール量を削減。
            ...(() {
              final sorted = [...banks]
                ..sort((a, b) => currentBalanceOf(b)
                    .compareTo(currentBalanceOf(a)));
              const topN = 3;
              final showAll =
                  _allBanksExpanded || sorted.length <= topN;
              final visible = showAll
                  ? sorted
                  : sorted.take(topN).toList();
              final hiddenCount = sorted.length - visible.length;
              final tiles = <Widget>[
                ...visible
                    .map((b) => _balanceRow(b, currentBalanceOf(b))),
              ];
              if (sorted.length > topN) {
                tiles.add(
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() =>
                        _allBanksExpanded = !_allBanksExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                              _allBanksExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: const Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          Text(
                            _allBanksExpanded
                                ? '閉じる'
                                : 'すべて表示（残り$hiddenCount件）',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return tiles;
            })(),
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
          // 見出し（セクションタイトル「総資産」）と重複するため小ラベルは削除。
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
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
    TextStyle? titleStyle,
    double iconSize = 16,
    double titleGap = 6,
    double contentGap = 12,
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
              Icon(icon, size: iconSize, color: iconColor),
              SizedBox(width: titleGap),
              Text(title,
                  style: titleStyle ??
                      const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: contentGap),
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
