import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:finance_core/finance_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_mode.dart';
import '../../data/auth_service.dart';
import '../../data/backup_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/monthly_snapshot_repository.dart';
import '../../data/payments_change_notifier.dart';
import '../../data/settings_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/account_detail_screen.dart';
import '../../screens/card_detail_screen.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/receipt_group_detail_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/emoji_palette.dart';
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

  /// true のとき「資産」タブとして総資産のみを表示する。
  /// false（既定）はホーム本来の表示（総資産は出さない）。
  final bool assetsOnly;

  const V2HomeTopNavScreen(
      {super.key, required this.accent, this.assetsOnly = false});

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
  // 当月経費に固定費（サブスク）を上乗せするためのサブスク一覧。
  List<Subscription> _subs = [];
  // 支出の内訳セクションのアイコン解決用（大カテゴリ → iconKey）。
  CategoryConfig? _categories;
  bool _loading = true;

  /// 読み込みに失敗/タイムアウトしたときのエラー文（null=正常）。
  /// これがセットされると永久スピナーではなくエラー＋再読み込みを表示する。
  String? _loadError;

  /// 権限エラー（permission-denied）。ログインアカウント違いの可能性が高いので
  /// 専用メッセージ＋アカウント切替を出す。
  bool _isPermissionError = false;

  /// 表示月（既定は今月、月切替で前後）
  late DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  /// 当月支出の口座別内訳展開
  bool _expenseBreakdownExpanded = false;

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (!mounted) return;
      // 資産タブ表示時はリマインダーを出さない（ホーム本体のみ）。
      if (widget.assetsOnly) return;
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
        NoComposingUnderlineController(text: formatAmount(suggestedBalance));

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
                HalfWidthDigitsFormatter(),
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

  Future<void> _load() async {
    try {
      // 4種類のデータをまとめて読み込み。回線不調で Firestore が
      // 応答しないと終わらないため、全体にタイムアウトを掛ける。
      final data = await (() async {
        final txns = await _txRepo.loadAll();
        final payments = await _settings.loadPayments();
        final snapshots = await _snapshotRepo.load();
        final subs = await SubscriptionRepository.instance.load();
        final cats = await _settings.loadCategories();
        return (txns, payments, snapshots, subs, cats);
      })()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _transactions = data.$1;
        _payments = data.$2;
        _snapshots = data.$3;
        _subs = data.$4.subscriptions;
        _categories = data.$5;
        _loading = false;
        _loadError = null;
        _isPermissionError = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isPermissionError = false;
        _loadError = '読み込みに時間がかかっています（通信が不安定かもしれません）。';
      });
    } catch (e) {
      // permission-denied = このアカウントにデータの権限が無い
      // （＝ログインアカウント違いの可能性が高い）。それ以外は生エラーを出す。
      final perm = e is FirebaseException && e.code == 'permission-denied';
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isPermissionError = perm;
        _loadError = perm ? null : e.toString();
      });
    }
  }

  /// エラー状態からの再読み込み。
  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadError = null;
      _isPermissionError = false;
    });
    _load();
  }

  /// 別アカウントでログインし直す（サインアウト→AuthGate がログイン画面へ）。
  Future<void> _signOutAndRelogin() async {
    try {
      await AuthService.instance.signOut();
      // authStateChanges により自動でログイン画面へ遷移する。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('サインアウトに失敗: $e')));
    }
  }

  /// 大カテゴリ名（番号なし）→ アイコンキー。支出の内訳のアイコン解決用。
  String? _iconKeyForMajor(String bareMajor) {
    final c = _categories;
    if (c == null) return null;
    for (final m in c.majors) {
      if (m.name == bareMajor) return m.iconKey;
    }
    return null;
  }

  /// 指定月（[m]）に計上すべき固定費（サブスク）合計。
  /// 月次=定額/変動の当月分、年払い=請求月のみ。未来月は計上しない（当月まで）。
  int subsTotalForMonth(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    return _subs.fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
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
    if (_loadError != null || _isPermissionError) {
      return _LoadErrorView(
        permissionError: _isPermissionError,
        message: _loadError,
        email: AuthService.instance.currentUser?.email,
        onRetry: _retryLoad,
        onSignOut: _signOutAndRelogin,
      );
    }
    // Shell の Expanded 内で content として展開されるため、
    // ホームの 3 カラム / 縦並びがコンテンツ高を超えた場合に
    // スクロールできるよう、最上位に SingleChildScrollView を置く。
    // 「資産」タブ: 月切替 + 総資産のみを表示。
    if (widget.assetsOnly) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            vertical: V2Spacing.xl, horizontal: V2Spacing.md),
        child: Column(
          children: [
            _AssetMonthBar(state: this),
            const SizedBox(height: V2Spacing.md),
            _LeftAssetSummary(state: this),
          ],
        ),
      );
    }
    // Shell の Expanded 内で content として展開されるため、
    // ホームの 3 カラム / 縦並びがコンテンツ高を超えた場合に
    // スクロールできるよう、最上位に SingleChildScrollView を置く。
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.xl, horizontal: V2Spacing.md),
      child: LayoutBuilder(builder: (ctx, c) {
        // 総資産は「資産」タブへ移動したため、ホームでは中央カラムのみ。
        return _CenterColumn(state: this);
      }),
    );
  }
}

/// 「資産」タブ用の月切替バー（< 2026年6月 >）。
class _AssetMonthBar extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _AssetMonthBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final m = state._selectedMonth;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: V2Colors.textSecondary),
          onPressed: () => state.shiftMonth(-1),
        ),
        Text('${m.year}年${m.month}月',
            style: V2Typography.bodyStrong
                .copyWith(color: V2Colors.textPrimary)),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: V2Colors.textSecondary),
          onPressed: () => state.shiftMonth(1),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════
// 左カラム: 総資産 + 口座/カード一覧
// ═════════════════════════════════════════════════

/// 総資産カード（v2.1）。
/// 「総資産」ラベル（大）→ 月初残高 → 当月の増減 → 口座/カードのリスト →
/// 最下行に実際の総資産（大）、という「月初◯円 → 増減 → 現在」の流れで見せる。
/// 旧・月初残高カード（右カラム）はこのカードへ統合した。
class _LeftAssetSummary extends StatelessWidget {
  final _V2HomeTopNavScreenState state;
  const _LeftAssetSummary({required this.state});

  @override
  Widget build(BuildContext context) {
    final banks = state._payments.bankAccounts;
    final cards = state._payments.creditCards;
    // 総資産 = 全銀行口座の現在残高合計
    final totalAsset =
        banks.fold<int>(0, (s, b) => s + state._bankBalanceOf(b));
    final cardUsage = state._cardUsageOfMonth(state._selectedMonth);

    final today = DateTime.now();
    final isCurrentMonth = state._selectedMonth.year == today.year &&
        state._selectedMonth.month == today.month;
    final snap = state._snapshots
        .forMonth(state._selectedMonth.year, state._selectedMonth.month);
    final hasSnap = snap != null;
    final initial = snap?.initialBalance ?? 0;
    // 当月の増減 = 現在の総資産 − 月初残高
    final delta = totalAsset - initial;

    // 口座 + クレカ当月利用を 1 本のリストに（タップで通帳/カード詳細へ）
    final assetRows = <Widget>[
      for (final b in banks)
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
      for (final c in cards)
        if ((cardUsage[c.name] ?? 0) > 0)
          _AssetTile(
            icon: c.iconUrl,
            label: '${c.name}（今月利用）',
            value: '-${formatYen(cardUsage[c.name] ?? 0)}',
            valueColor: V2Colors.negative,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CardDetailScreen(card: c)),
            ),
          ),
    ];

    return V2Card(
      padding: const EdgeInsets.all(V2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── タイトル（大）──
          Text('総資産',
              style: V2Typography.h1.copyWith(color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.md),

          // ── 月初残高（編集可 / 未記録なら記録ボタン）──
          Row(
            children: [
              const Icon(Icons.event_note,
                  size: 14, color: V2Colors.textSecondary),
              const SizedBox(width: 6),
              Text('${state._selectedMonth.month}月の月初残高',
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
              const Spacer(),
              if (hasSnap)
                Text(formatYen(initial),
                    style: V2Typography.bodyStrong.copyWith(
                        color: V2Colors.textPrimary,
                        fontFeatures: V2Typography.tabularNums))
              else
                Row(children: [
                  const Icon(Icons.warning_amber,
                      size: 13, color: V2Colors.warning),
                  const SizedBox(width: 3),
                  Text('未記録',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.warning,
                          fontWeight: FontWeight.w700)),
                ]),
              if (isCurrentMonth) ...[
                const SizedBox(width: 2),
                InkWell(
                  onTap: () => state.openSnapshotDialog(),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.edit,
                        size: 13, color: V2Colors.textMuted),
                  ),
                ),
              ],
            ],
          ),
          // ── 当月の増減（月初比）──
          if (hasSnap) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                    delta >= 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    size: 14,
                    color: delta >= 0
                        ? V2Colors.positive
                        : V2Colors.negative),
                const SizedBox(width: 6),
                Text('当月の増減',
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textSecondary)),
                const Spacer(),
                Text(formatYen(delta, withSign: true),
                    style: V2Typography.bodyStrong.copyWith(
                        color: delta >= 0
                            ? V2Colors.positive
                            : V2Colors.negative,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
          ] else if (isCurrentMonth) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => state.openSnapshotDialog(),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('月初残高を記録'),
              ),
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: V2Spacing.md),
            child: Divider(height: 1),
          ),

          // ── 内訳（口座/カード）をリスト形式で ──
          if (assetRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '口座が未登録です。設定 → ウォレット から追加してください。',
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textSecondary),
              ),
            )
          else
            for (int i = 0; i < assetRows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              assetRows[i],
            ],

          const SizedBox(height: V2Spacing.sm),
          Container(
              height: 1,
              color: V2Colors.textPrimary.withValues(alpha: 0.15)),
          const SizedBox(height: V2Spacing.md),

          // ── 総資産（大・最下行）──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('総資産',
                  style: V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 15)),
              const Spacer(),
              Text(formatYen(totalAsset),
                  style: V2Typography.kpiValue
                      .copyWith(color: V2Colors.textPrimary)),
            ],
          ),
        ],
      ),
    );
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
    final txExpense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);
    // 固定費（サブスク）の当月分を「当月経費」にあらかじめ加算。
    final subTotal = state.subsTotalForMonth(state._selectedMonth);
    final expense = txExpense + subTotal;
    final net = income - expense;
    final isBlack = net >= 0;

    // 支出内訳（支払方法別）＋固定費
    final expenseByMethod = <String, int>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
      expenseByMethod[t.paymentMethod] =
          (expenseByMethod[t.paymentMethod] ?? 0) + t.amount;
    }
    if (subTotal > 0) {
      expenseByMethod['固定費・サブスク'] =
          (expenseByMethod['固定費・サブスク'] ?? 0) + subTotal;
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

    // 最新の入出金: 選択中の月のみ・日付降順。
    // 同じレシート（receiptId が2件以上）は1行にまとめる（支出明細と同じ挙動）。
    final recent = [...monthTxns]
      ..sort((a, b) => b.date.compareTo(a.date));
    final recentUnits = _groupByReceipt(recent).take(8).toList();

    // 支出の内訳（大カテゴリ別）。番号は表示・集計とも除いて名前で束ねる。
    // タップ展開用に、カテゴリ別の取引一覧も同時に集める。
    final byMajor = <String, int>{};
    final txnsByMajor = <String, List<Transaction>>{};
    for (final t in monthTxns) {
      if (t.type != TransactionType.expense) continue;
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.amount;
      (txnsByMajor[major] ??= []).add(t);
    }
    // 固定費（サブスク）の当月分も大カテゴリ別内訳に1行として加える。
    // 支払方法別の内訳と同じ扱いにし、内訳合計を当月経費（固定費込み）と一致させる。
    if (subTotal > 0) {
      const kFixed = '固定費・サブスク';
      byMajor[kFixed] = (byMajor[kFixed] ?? 0) + subTotal;
    }
    final majorEntries = byMajor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final byMajorTotal =
        byMajor.values.fold<int>(0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // カンタン入力セクションは廃止（右上「記録」ボタンで代替）。
        // ── 月の収支（最新の入出金より上に表示）──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                      '${state._selectedMonth.year}年${state._selectedMonth.month}月の収支',
                      style: V2Typography.h2
                          .copyWith(color: V2Colors.textPrimary)),
                  const Spacer(),
                  // 月送り（前月/翌月）。
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 22,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => state.shiftMonth(-1),
                    tooltip: '前の月',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 22,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => state.shiftMonth(1),
                    tooltip: '次の月',
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.sm),
              // 月切替は見出し横の ◁ ▷（矢印式）に一本化。
              // 横並びの月ボックス（_MonthChipsBar）は廃止。
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
        // ── 支出の内訳（大カテゴリ別） ──────────────────
        if (majorEntries.isNotEmpty) ...[
          V2Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('支出の内訳',
                    style: V2Typography.h2
                        .copyWith(color: V2Colors.textPrimary)),
                const SizedBox(height: V2Spacing.md),
                _CategoryBreakdown(
                  entries: majorEntries.take(6).toList(),
                  total: byMajorTotal,
                  txnsByMajor: txnsByMajor,
                  accent: state.widget.accent,
                  iconKeyFor: state._iconKeyForMajor,
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
        ],
        // ── 最新の入出金（選択中の月）──────────────────
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // タップでその月の支出明細一覧へ遷移。
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpenseListScreen(
                        title: isBusiness ? '経費明細一覧' : '支出明細一覧',
                        month: state._selectedMonth,
                      ),
                    ),
                  );
                  await state._load();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                          '${state._selectedMonth.month}月の入出金',
                          style: V2Typography.h2
                              .copyWith(color: V2Colors.textPrimary)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 18, color: V2Colors.textMuted),
                      const Text('明細',
                          style: TextStyle(
                              fontSize: 11, color: V2Colors.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: V2Spacing.md),
              if (recentUnits.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('取引記録はまだありません',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary)),
                )
              else
                for (final u in recentUnits)
                  if (u.isGroup)
                    // まとめ（複数品目）：タップでそのまとまりの内訳だけを表示。
                    // 単品（GU等）と同じく「その明細」へ進む感覚に揃える。
                    _ReceiptGroupRow(
                      members: u.members!,
                      onTap: () async {
                        final changed = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReceiptGroupDetailScreen(
                                members: u.members!),
                          ),
                        );
                        if (changed == true) await state._load();
                      },
                    )
                  else
                    _TransactionRow(
                      t: u.single!,
                      onTap: () async {
                        final changed = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TransactionDetailScreen(
                                  transaction: u.single!)),
                        );
                        if (changed == true) await state._load();
                      },
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransactionRow extends StatefulWidget {
  final Transaction t;
  final VoidCallback? onTap;
  const _TransactionRow({required this.t, this.onTap});

  @override
  State<_TransactionRow> createState() => _TransactionRowState();
}

class _TransactionRowState extends State<_TransactionRow> {
  bool _hover = false;

  String _typeLabel() {
    switch (widget.t.type) {
      case TransactionType.income:
        return '収入';
      case TransactionType.expense:
        return '支出';
      case TransactionType.transfer:
        return '振替';
    }
  }

  String _categoryLabel() {
    final major = widget.t.category.major.trim();
    final sub = widget.t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return _typeLabel();
    if (sub.isEmpty) return major;
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final onTap = widget.onTap;
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final color = isTransfer
        ? V2Colors.textBody
        : (isIncome ? V2Colors.positive : V2Colors.negative);
    final sign = isTransfer ? '' : (isIncome ? '+' : '-');
    final card = Container(
      // たくはる風: 1 行 = 角丸枠付きの長方形カード。ホバーで背景を変える。
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: _hover ? V2Colors.hover : V2Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: V2Colors.border),
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
    if (onTap == null) return card;
    // 最近の入出金は編集しやすいよう、行タップで詳細画面を直接開く。
    // カーソルを当てるとフォーカス（ホバー背景）が出る（支出タブと同じ）。
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// 入出金一覧の表示単位：単品（single）か、同じレシートのまとめ（group）。
/// 支出の内訳（カテゴリ別）。区切り線で各カテゴリを仕切り、
/// 行タップでそのカテゴリにぶら下がる取引明細を展開表示する。
class _CategoryBreakdown extends StatefulWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  final Map<String, List<Transaction>> txnsByMajor;
  final Color accent;
  final String? Function(String) iconKeyFor;
  const _CategoryBreakdown({
    required this.entries,
    required this.total,
    required this.txnsByMajor,
    required this.accent,
    required this.iconKeyFor,
  });

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < widget.entries.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, thickness: 1, color: V2Colors.border),
          _categoryRow(widget.entries[i]),
        ],
      ],
    );
  }

  Widget _categoryRow(MapEntry<String, int> e) {
    final ratio = widget.total == 0 ? 0.0 : e.value / widget.total;
    final open = _open == e.key;
    final txns = widget.txnsByMajor[e.key] ?? const <Transaction>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = open ? null : e.key),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: categoryIconWidget(widget.iconKeyFor(e.key),
                          size: 17, color: widget.accent),
                    ),
                    const SizedBox(width: V2Spacing.sm),
                    Expanded(
                      child: Text(e.key,
                          style: V2Typography.body,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(formatYen(e.value),
                        style: V2Typography.numericCell
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: V2Colors.textMuted),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: V2Colors.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(widget.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 38, bottom: 8),
            child: Column(
              children: [
                for (final t in txns) _txnRow(t),
                if (txns.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('明細なし',
                          style: V2Typography.caption
                              .copyWith(color: V2Colors.textMuted)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _txnRow(Transaction t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(formatMonthDay(t.date),
                style:
                    V2Typography.caption.copyWith(color: V2Colors.textMuted)),
          ),
          Expanded(
            child: Text(t.description.isEmpty ? '—' : t.description,
                style: V2Typography.caption
                    .copyWith(color: V2Colors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ),
          Text('-${formatYen(t.amount)}',
              style: V2Typography.caption.copyWith(
                  color: V2Colors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RecentUnit {
  final Transaction? single;
  final List<Transaction>? members;
  const _RecentUnit.single(this.single) : members = null;
  const _RecentUnit.group(this.members) : single = null;
  bool get isGroup => members != null;
}

/// 同じ receiptId が2件以上 → まとめ（group）、それ以外 → 単品（single）。
/// 並び順は元の rows の順（親はその最初の品目の位置）を保つ。
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

/// レシートのまとめ行（同じレシートの複数品目を1行に集約）。
/// 「日付 / レシートN件バッジ / 店舗 / 合計」を表示。
class _ReceiptGroupRow extends StatefulWidget {
  final List<Transaction> members;
  final VoidCallback? onTap;
  const _ReceiptGroupRow({required this.members, this.onTap});

  @override
  State<_ReceiptGroupRow> createState() => _ReceiptGroupRowState();
}

class _ReceiptGroupRowState extends State<_ReceiptGroupRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final onTap = widget.onTap;
    final first = members.first;
    final isIncome = first.type == TransactionType.income;
    final color = isIncome ? V2Colors.positive : V2Colors.negative;
    final sign = isIncome ? '+' : '-';
    final total = members.fold<int>(0, (s, t) => s + t.amount);
    final store = (first.store ?? '').trim().isNotEmpty
        ? first.store!.trim()
        : (first.description.trim().isNotEmpty
            ? first.description.trim()
            : first.paymentMethod);
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: _hover ? V2Colors.hover : V2Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: V2Colors.border),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text('${first.date.month}/${first.date.day}',
                  style: V2Typography.caption.copyWith(
                      fontFeatures: V2Typography.tabularNums))),
          // レシートまとめバッジ（N件）
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long,
                    size: 11, color: V2Colors.textSecondary),
                const SizedBox(width: 3),
                Text('${members.length}件', style: V2Typography.micro),
              ],
            ),
          ),
          const SizedBox(width: V2Spacing.md),
          Expanded(
            child: Text(store,
                style: V2Typography.body, overflow: TextOverflow.ellipsis),
          ),
          Text('$sign${formatYen(total)}',
              style: V2Typography.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
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

/// ホームのデータ読み込み失敗時に出すエラー＋再読み込みビュー。
/// 永久スピナーを避け、原因切り分け用にエラー文も表示する。
/// [permissionError] のときは「権限なし＝アカウント違いかも」専用の案内を出す。
class _LoadErrorView extends StatelessWidget {
  final bool permissionError;
  final String? message;
  final String? email;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;
  const _LoadErrorView({
    required this.permissionError,
    required this.message,
    required this.email,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 56, horizontal: V2Spacing.lg),
      child: Center(
        child: V2Card(
          padding: const EdgeInsets.all(V2Spacing.xl),
          child: permissionError
              ? _buildPermission(context)
              : _buildGeneric(context),
        ),
      ),
    );
  }

  /// 権限エラー: ログインアカウント違いの可能性が高い。
  Widget _buildPermission(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_person_outlined,
            size: 40, color: V2Colors.warning),
        const SizedBox(height: V2Spacing.md),
        Text('このアカウントでは表示できません',
            style: V2Typography.h2, textAlign: TextAlign.center),
        const SizedBox(height: V2Spacing.xs),
        Text(
          'ログイン中のアカウントには、このデータを見る権限がありません。'
          'アカウントを間違えていないか確認してください。',
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        if (email != null) ...[
          const SizedBox(height: V2Spacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(V2Spacing.sm),
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_circle_outlined,
                    size: 18, color: V2Colors.textSecondary),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Text('ログイン中: $email',
                      style: V2Typography.caption
                          .copyWith(color: V2Colors.textPrimary)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: V2Spacing.lg),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('別のアカウントでログインし直す'),
            style: FilledButton.styleFrom(
              backgroundColor: V2Colors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(V2Spacing.radiusMd),
              ),
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.sm),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('もう一度試す'),
        ),
      ],
    );
  }

  /// 通信エラーなどの汎用。
  Widget _buildGeneric(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off,
            size: 40, color: V2Colors.textMuted),
        const SizedBox(height: V2Spacing.md),
        Text('データを読み込めませんでした',
            style: V2Typography.h2, textAlign: TextAlign.center),
        const SizedBox(height: V2Spacing.xs),
        Text(
          '通信が不安定なときに起きやすいです。電波の良い場所で'
          '「再読み込み」をお試しください。',
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: V2Spacing.md),
          // 原因切り分け用の生エラー（小さめ・常時表示）。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(V2Spacing.sm),
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            ),
            child: Text(message!,
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textSecondary)),
          ),
        ],
        const SizedBox(height: V2Spacing.lg),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再読み込み'),
            style: FilledButton.styleFrom(
              backgroundColor: V2Colors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(V2Spacing.radiusMd),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

