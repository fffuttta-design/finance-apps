import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/formatters.dart';

import '../data/app_mode.dart';
import '../data/card_settlement_service.dart';
import '../data/data_migration_service.dart';
import '../data/fixed_cost_materializer.dart';
import '../data/receipt_ocr_cloud.dart';
import '../data/receipt_ocr_flow.dart';
import '../data/repository_provider.dart';
import '../data/ui_preferences.dart';
import '../screens/expense_input_screen.dart';
import '../utils/modal_input.dart';
import '../utils/pwa_theme.dart';
import '../screens/income_input_screen.dart';
import '../screens/receipt_split_screen.dart';
import '../screens/transfer_input_screen.dart';
import 'layout/rich_sidebar_shell.dart';
import 'layout/topnav_shell.dart';
import 'widgets/global_month_nav.dart';
import 'screens/rich_expenses.dart';
import 'screens/rich_home.dart';
import 'screens/rich_income.dart';
import 'screens/v2_devlab.dart';
import 'screens/v2_home_topnav.dart';
import 'screens/v2_report.dart';
import 'screens/v2_settings.dart';
import 'theme/mode_accent.dart';
import '../widgets/startup_update_mixin.dart';
import 'widgets/v2_bottom_nav.dart';
import 'widgets/v2_mode_switcher.dart';
import 'widgets/v2_top_header.dart';
import 'widgets/v2_top_nav.dart';

/// v2 のルート。サイドバーのナビ選択を保持し、メイン領域を切り替える。
class V2Root extends StatefulWidget {
  const V2Root({super.key});

  @override
  State<V2Root> createState() => _V2RootState();
}

class _V2RootState extends State<V2Root>
    with StartupUpdateMixin, WidgetsBindingObserver {
  String _currentId = 'home';
  // 本文を左右スワイプでタブ切替（PageView・指追従）。たくはると同じ操作感。
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final items = _navItems;
    final idx = items.indexWhere((e) => e.id == _currentId);
    _pageController = PageController(initialPage: idx < 0 ? 0 : idx);
    WidgetsBinding.instance.addObserver(this);
    AppModeManager.instance.addListener(_onChange);
    UiPreferences.instance.addListener(_onChange);
    _syncPwaThemeColor(); // 起動時に現モードの色でブラウザ枠を塗る（Webのみ）
    // 起動時にアプリ内アップデート（APK配信）をチェックして通知（v1と共通）。
    scheduleStartupUpdateCheck();
    // 事業用カテゴリをPL構成へ一度だけ移行（業務モード時のみ・idempotent）。
    DataMigrationService.migratePLCategoriesIfNeeded();
    // 起動が落ち着いた頃に逆モードのデータを裏で先読み（初回切替を速く）。
    Future.delayed(const Duration(milliseconds: 1200), () {
      RepositoryProvider.prefetchOtherMode();
      _runCardSettlement(); // クレカ自動引落（引落日を過ぎた分を生成）
      _runFixedCostMaterialize(); // 固定費：請求日を過ぎた分を実明細化
    });
  }

  /// 自動生成した明細のうち「まだ知らせていないID」だけを返す。
  /// 生成が毎回走っても、同じ明細のメッセージは二度と出さない
  /// （＝「同じお知らせが毎回出る」問題の対策）。
  Future<Set<String>> _unnotifiedIds(String key, Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final notified = (prefs.getStringList(key) ?? <String>[]).toSet();
    final fresh = ids.where((id) => !notified.contains(id)).toSet();
    if (fresh.isEmpty) return fresh;
    notified.addAll(fresh);
    final list = notified.toList();
    // 肥大化防止に直近500件だけ保持。
    await prefs.setStringList(
        key, list.length > 500 ? list.sublist(list.length - 500) : list);
    return fresh;
  }

  /// 固定費（サブスク）の請求日を過ぎた月を実明細化し、初回だけ知らせる。
  Future<void> _runFixedCostMaterialize() async {
    final created = await FixedCostMaterializer.runOncePerMode(
        AppModeManager.instance.current.name);
    if (created.isEmpty) return;
    final fresh =
        await _unnotifiedIds('futa.fixedcost.notified', created.map((t) => t.id));
    if (!mounted || fresh.isEmpty) return;
    // 「何を・いくら」実明細化したのかポップアップで一覧表示する（要望）。
    final items = created.where((t) => fresh.contains(t.id)).toList();
    await _showMaterializedDialog(
      emoji: '🧾',
      title: '固定費を実明細として記録しました',
      subtitle: '請求日を過ぎた固定費（サブスク）を、明細に自動で追加しました。',
      items: items,
    );
  }

  /// クレカの自動引き落としを生成し、初回だけポップアップで知らせる。
  /// モードごとに1セッション1回（frequentな _onChange で呼んでも短絡する）。
  Future<void> _runCardSettlement() async {
    final created = await CardSettlementService.runOncePerMode(
        AppModeManager.instance.current.name);
    if (created.isEmpty) return;
    final fresh = await _unnotifiedIds(
        'futa.cardsettle.notified', created.map((t) => t.id));
    if (!mounted || fresh.isEmpty) return;
    final items = created.where((t) => fresh.contains(t.id)).toList();
    await _showMaterializedDialog(
      emoji: '💳',
      title: 'クレカ引落を自動で記録しました',
      subtitle: '引落日を過ぎたクレジットカードの請求を、明細に自動で追加しました。',
      items: items,
    );
  }

  /// 「何を・いくら」自動記録したのかを一覧表示するポップアップ。
  /// 固定費／クレカ引落の自動記録で共通利用する。
  Future<void> _showMaterializedDialog({
    required String emoji,
    required String title,
    required String subtitle,
    required List<core.Transaction> items,
  }) async {
    if (!mounted || items.isEmpty) return;
    final total = items.fold<int>(0, (s, t) => s + t.amount);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$title（${items.length}件）',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1, color: Colors.grey.shade200),
                  itemBuilder: (_, i) {
                    final t = items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        // 日付（M/D）
                        SizedBox(
                          width: 48,
                          child: Text(monthDayOnly(t.date),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        ),
                        // 名前（取引内容）
                        Expanded(
                          child: Text(
                            t.description.isEmpty ? '（無題）' : t.description,
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 金額
                        Text('-${formatYen(t.amount)}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    );
                  },
                ),
              ),
              const Divider(height: 20),
              Row(children: [
                const Text('合計',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('-${formatYen(total)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// 月（YYYY年M月）を使うタブか。ホーム/支出/収入だけ共有月ナビを出す。
  /// 業績(report)は月/年の切替＋独自ナビを持つので対象外（タブ内のナビを使う）。
  static bool _isMonthTab(String id) =>
      id == 'home' || id == 'expenses' || id == 'income';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppModeManager.instance.removeListener(_onChange);
    UiPreferences.instance.removeListener(_onChange);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // アプリ復帰時にも新バージョンを確認（スロットルで連打抑制）。
    if (state == AppLifecycleState.resumed) {
      runUpdateCheckThrottled();
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
    _syncPwaThemeColor(); // モード切替でブラウザ枠の色も切替（Webのみ）
    // 事業モードへ切替時にも移行を試行（個人で起動→事業に切替えた場合に対応）。
    DataMigrationService.migratePLCategoriesIfNeeded();
    _runCardSettlement(); // 切替先モードの自動引落も生成（モード別に1回）
    _runFixedCostMaterialize(); // 切替先モードの固定費も実明細化（モード別に1回）
  }

  /// PWA（Web）のタイトルバー色を現モードに合わせて切替える。
  /// 事業＝ニュートラルなグレー（事業の青/個人のオレンジと紛れない）、
  /// 個人＝見やすいオレンジ。非Webでは何もしない。
  void _syncPwaThemeColor() {
    final personal = AppModeManager.instance.current == AppMode.personal;
    setPwaThemeColor(personal ? '#C2410C' : '#3F3F46');
  }

  /// 現在のモードに応じて表示するナビ一覧。
  /// 「設定→上タブの並び順」(UiPreferences.sidebarOrder)で並びを反映する。
  List<V2NavItem> get _navItems {
    final isBusiness = AppModeManager.instance.current == AppMode.business;
    final all = <String, V2NavItem>{
      'home': const V2NavItem(
          id: 'home', label: 'ホーム', icon: Icons.dashboard_outlined),
      'expenses': V2NavItem(
          id: 'expenses',
          label: isBusiness ? '経費' : '支出',
          icon: Icons.receipt_long_outlined),
      'income': V2NavItem(
          id: 'income',
          label: isBusiness ? '売上' : '収入',
          icon: Icons.savings_outlined),
      // 事業も個人も「業績」に統一（個人＝資産を増やす業績）。
      'report': V2NavItem(
          id: 'report',
          label: '業績',
          icon: Icons.bar_chart_outlined),
      'assets': const V2NavItem(
          id: 'assets',
          label: '資産',
          icon: Icons.account_balance_wallet_outlined),
      'settings': const V2NavItem(
          id: 'settings', label: '設定', icon: Icons.settings_outlined),
      // 「開発中/取込」タブは廃止し、設定画面（明細の貼り付け取込・開発ラボ）へ移設。
    };
    final result = <V2NavItem>[];
    for (final id in UiPreferences.instance.sidebarOrder) {
      final item = all.remove(id);
      if (item != null) result.add(item);
    }
    result.addAll(all.values); // 念のため残り（順序未登録のもの）
    return result;
  }

  Widget _bodyFor(String id, {required Color accent}) {
    // 本文は rich 版に一本化（`UiPreferences.richUi` は常に true で、
    // 旧版（V2ExpensesScreen/V2IncomeScreen）は到達不能な死にコードだったので削除した）。
    // ※業績タブは詳細PL（V2ReportScreen）を維持する（PLを消さない）。
    // ※V2HomeTopNavScreen は資産一覧（assetsOnly）でまだ現役なので残す。
    switch (id) {
      case 'home':
        return RichHomeScreen(accent: accent);
      case 'expenses':
        return RichExpensesScreen(accent: accent);
      case 'income':
        return RichIncomeScreen(accent: accent);
      // 資産タブは廃止。口座/カードはホームの総資産や支出の「ウォレット一覧」から。
      // クレカタブも廃止。カード一覧は支出タブ上部の「ウォレット一覧」ボタンから開く。
      // 集計: v2.1 ネイティブ実装（会計風 PL 月次表 + v1 集計画面へのリンク）
      case 'report':
        // 業績は詳細PL（損益計算書）を常に維持。ダッシュボード化で
        // PL が消えないよう、リッチ時も従来の V2ReportScreen を使う。
        // リッチ時はサイド見切れ防止に中央寄せ＋左右余白を付ける。
        // リッチ時は他タブと同じ密度に揃える（中央寄せ・最大幅960・上部に
        // ダッシュボード帯を表示）。PL（詳細表）はそのまま下に残す。
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: V2ReportScreen(accent: accent, richBand: true),
            ),
          ),
        );
      // 資産: 総資産（口座/カード/月初残高）。ホームから移動。
      case 'assets':
        // 資産は単一カラムなので、リッチ時は細めに中央寄せ（横伸び防止）。
        final assets =
            V2HomeTopNavScreen(accent: accent, assetsOnly: true);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: assets,
          ),
        );
      // 設定: v2.1 ネイティブ（マスター/ディテール、左メニュー + 右パネル）
      case 'settings':
        // 二重サイドバーを避け、1カラム（カード一覧→パネル）に。
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: V2SettingsScreen(accent: accent, singlePane: true),
          ),
        );
      // 開発中: v2.1 風バナー + v1 DevLab を埋め込み（事業モード専用）
      case 'devLab':
        return V2DevLabScreen(accent: accent);
      default:
        return V2HomeTopNavScreen(accent: accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI は上タブ版（v2.1）に一本化。サイドバー版・v1 への切替は廃止。
    final accent = V2ModeAccent.of(AppModeManager.instance.current);
    Widget shell = _buildTopNav(context, accent);
    // Web（キーボードのある環境）向けショートカット。
    //  ・← / →            タブ切替
    //  ・Alt + ← / →       モード切替（← 事業 / → 個人）
    // テキスト入力中は矢印がフィールドに消費されるため誤爆しない。
    if (kIsWeb) {
      shell = CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _shiftTab(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _shiftTab(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
              () => _setMode(AppMode.personal),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
              _setMode(AppMode.business),
        },
        child: Focus(autofocus: true, child: shell),
      );
    }
    return shell;
  }

  /// モードを直接指定して切替（同じモードなら何もしない）。
  void _setMode(AppMode m) {
    if (AppModeManager.instance.current == m) return;
    AppModeManager.instance.setMode(m);
  }

  /// タブを delta 個ぶん送る（範囲外は何もしない）。Webの ←/→ ショートカット用。
  void _shiftTab(int delta) {
    final items = _navItems;
    final idx = items.indexWhere((e) => e.id == _currentId);
    if (idx < 0) return;
    final next = idx + delta;
    if (next < 0 || next >= items.length) return;
    setState(() => _currentId = items[next].id);
    if (_pageController.hasClients) {
      _pageController.animateToPage(next,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    }
  }

  /// マネフォ ME 風（v2.1）: 上タブ + 中央カラム
  /// 事業モード時はヘッダーがダークネイビー、個人モード時は白
  Widget _buildTopNav(BuildContext context, Color accent) {
    final mode = AppModeManager.instance.current;
    final isBusiness = mode == AppMode.business;
    // モバイル幅（スマホ）はタブを下部に置く（たくはる風）。広い画面は従来の上タブ。
    final isNarrow = MediaQuery.sizeOf(context).width < 700;
    // タブのタップ → そのページへ指追従と同じカーブで移動。
    void selectTab(String id) {
      final items = _navItems;
      final idx = items.indexWhere((e) => e.id == id);
      setState(() => _currentId = id);
      if (idx >= 0 && _pageController.hasClients) {
        _pageController.animateToPage(idx,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
    }
    // 新デザイン（リッチUI）かつ広い画面 → 左サイドバーのダッシュボードシェル。
    // スマホ幅は従来どおり下タブのシェルを使う（本文だけ rich 版に差替え済）。
    if (UiPreferences.instance.richUi && !isNarrow) {
      final items = _navItems;
      final cur = items.firstWhere((e) => e.id == _currentId,
          orElse: () => items.first);
      return RichSidebarShell(
        items: items,
        currentId: _currentId,
        onSelect: selectTab,
        accent: accent,
        personal: mode == AppMode.personal,
        title: cur.label,
        modeSwitcher: V2ModeSwitcher(onDark: false),
        // 月を使うタブ（ホーム/支出/収入/業績）だけトップバーに共有月ナビを出す。
        monthNav: _isMonthTab(_currentId) ? const GlobalMonthNav() : null,
        recordButton: _RecordMenuButton(
          accent: accent,
          mode: mode,
          onDark: false,
          onSelected: _openRecord,
        ),
        content: KeyedSubtree(
          key: ValueKey('rich_${mode}_$_currentId'),
          child: _bodyFor(_currentId, accent: accent),
        ),
      );
    }
    return V2TopNavShell(
      navAtBottom: isNarrow,
      monthNav: _isMonthTab(_currentId) ? const GlobalMonthNav() : null,
      bottomNav: isNarrow
          ? V2BottomNav(
              items: _navItems,
              currentId: _currentId,
              onSelect: selectTab,
              accent: accent,
            )
          : null,
      header: V2TopHeader(
        mode: mode,
        accent: accent,
        modeSwitcher: V2ModeSwitcher(onDark: isBusiness),
        actions: [
          _RecordMenuButton(
            accent: accent,
            mode: mode,
            onDark: isBusiness,
            onSelected: _openRecord,
          ),
        ],
      ),
      topNav: V2TopNav(
        items: _navItems,
        currentId: _currentId,
        onSelect: selectTab,
        accent: accent,
        // Shell の maxContentWidth と揃える（マネフォ ME 寄りに 1040px）
        maxWidth: 1040,
      ),
      // 本文を左右スワイプでタブ切替（PageView・指追従）。たくはると同じ操作感。
      // 各タブは keep-alive で状態を保持。モード切替時はキーが変わり作り直す。
      content: PageView(
        controller: _pageController,
        onPageChanged: (i) {
          final items = _navItems;
          if (i >= 0 && i < items.length && items[i].id != _currentId) {
            setState(() => _currentId = items[i].id);
          }
        },
        children: [
          for (final item in _navItems)
            KeyedSubtree(
              key: ValueKey('${mode}_${item.id}'),
              child: _V2KeepAlivePage(
                child: _bodyFor(item.id, accent: accent),
              ),
            ),
        ],
      ),
    );
  }

  /// 記録メニュー: レシート読取 / 支出 / 収入 / 振替を選んで対応する入力を開く。
  Future<void> _openRecord(String kind) async {
    // レシート読み取り（OCR）→ 記録方法を選んで入力。
    if (kind == 'receipt') {
      await runReceiptOcrFlow(context);
      return;
    }
    // 手入力で明細を分けて記録（レシートと同じく1グループにまとめる）。
    // グループID（receiptId 流用）を発番し、各品目を同じIDで束ねる。
    if (kind == 'split') {
      final gid = 'manual-${DateTime.now().microsecondsSinceEpoch}';
      showInputSheet(
          context, ReceiptSplitScreen(manual: true, receiptId: gid));
      return;
    }
    Widget? page;
    switch (kind) {
      case 'expense':
        page = const ExpenseInputScreen();
        break;
      case 'income':
        page = const IncomeInputScreen();
        break;
      case 'transfer':
        page = const TransferInputScreen();
        break;
    }
    if (page == null) return;
    // 全画面ではなくモーダルシート（ポップアップ風）で表示。
    showInputSheet(context, page);
  }
}

/// 「+ 記録」ボタン（PopupMenu）。支出/収入/振替を選んで入力できる。
/// 事業モードでは「支出/経費」は「経費」、「収入」は「売上」とラベルが切り替わる。
class _RecordMenuButton extends StatelessWidget {
  final Color accent;
  final AppMode mode;
  final bool onDark;
  final void Function(String kind) onSelected;
  const _RecordMenuButton({
    required this.accent,
    required this.mode,
    required this.onDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isBusiness = mode == AppMode.business;
    return PopupMenuButton<String>(
      tooltip: '記録する',
      onSelected: onSelected,
      itemBuilder: (_) => [
        // レシート読み取り（端末カメラで撮る前提のためAndroidのみ表示）。
        // デスクトップ(Electron=中身はWeb)やブラウザでは出さない（kIsWebで除外）。
        if (ReceiptOcrCloud.available && !kIsWeb)
          PopupMenuItem(
            value: 'receipt',
            child: Row(
              children: [
                const Icon(Icons.document_scanner_outlined,
                    size: 16, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                const Text('レシートで記録'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'expense',
          child: Row(
            children: [
              const Icon(Icons.remove_circle_outline,
                  size: 16, color: Color(0xFFEF4444)),
              const SizedBox(width: 8),
              Text(isBusiness ? '経費を記録' : '支出を記録'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'income',
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline,
                  size: 16, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(isBusiness ? '売上を記録' : '収入を記録'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'transfer',
          child: Row(
            children: [
              Icon(Icons.swap_horiz,
                  size: 16, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text('振替を記録'),
            ],
          ),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('記録',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}


/// PageView の各タブを生かしたまま保持する（IndexedStack 同様にタブの
/// スクロール位置・状態を維持するため）。モード切替時は外側の KeyedSubtree の
/// キーが変わるので作り直される（モードごとに正しいデータで再構築）。
class _V2KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _V2KeepAlivePage({required this.child});

  @override
  State<_V2KeepAlivePage> createState() => _V2KeepAlivePageState();
}

class _V2KeepAlivePageState extends State<_V2KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
