import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_mode.dart';
import '../data/data_migration_service.dart';
import '../data/repository_provider.dart';
import '../data/ui_preferences.dart';
import '../screens/expense_input_screen.dart';
import '../screens/income_input_screen.dart';
import '../screens/transfer_input_screen.dart';
import 'layout/shell.dart';
import 'layout/topnav_shell.dart';
import 'screens/v2_devlab.dart';
import 'screens/v2_expenses.dart';
import 'screens/v2_home.dart';
import 'screens/v2_home_topnav.dart';
import 'screens/v2_income.dart';
import 'screens/v2_report.dart';
import 'screens/v2_settings.dart';
import 'theme/colors.dart';
import 'theme/mode_accent.dart';
import 'theme/spacing.dart';
import 'theme/typography.dart';
import '../widgets/startup_update_mixin.dart';
import 'widgets/v2_mode_switcher.dart';
import 'widgets/v2_sidebar.dart';
import 'widgets/v2_top_header.dart';
import 'widgets/v2_top_nav.dart';
import 'widgets/v2_topbar.dart';

/// v2 のルート。サイドバーのナビ選択を保持し、メイン領域を切り替える。
class V2Root extends StatefulWidget {
  const V2Root({super.key});

  @override
  State<V2Root> createState() => _V2RootState();
}

class _V2RootState extends State<V2Root> with StartupUpdateMixin {
  String _currentId = 'home';
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    AppModeManager.instance.addListener(_onChange);
    UiPreferences.instance.addListener(_onChange);
    _loadVersion();
    // 起動時にアプリ内アップデート（APK配信）をチェックして通知（v1と共通）。
    scheduleStartupUpdateCheck();
    // 事業用カテゴリをPL構成へ一度だけ移行（業務モード時のみ・idempotent）。
    DataMigrationService.migratePLCategoriesIfNeeded();
    // 起動が落ち着いた頃に逆モードのデータを裏で先読み（初回切替を速く）。
    Future.delayed(const Duration(milliseconds: 1200), () {
      RepositoryProvider.prefetchOtherMode();
    });
  }

  @override
  void dispose() {
    AppModeManager.instance.removeListener(_onChange);
    UiPreferences.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
    // 事業モードへ切替時にも移行を試行（個人で起動→事業に切替えた場合に対応）。
    DataMigrationService.migratePLCategoriesIfNeeded();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = 'v${info.version}');
    } catch (_) {/* ignore */}
  }

  /// 現在のモードに応じて表示するナビ一覧。
  List<V2NavItem> get _navItems {
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    return [
      const V2NavItem(
          id: 'home', label: 'ホーム', icon: Icons.dashboard_outlined),
      const V2NavItem(
          id: 'expenses',
          label: '支出',
          icon: Icons.receipt_long_outlined),
      const V2NavItem(
          id: 'income',
          label: '収入',
          icon: Icons.savings_outlined),
      const V2NavItem(
          id: 'report',
          label: '業績',
          icon: Icons.bar_chart_outlined),
      const V2NavItem(
          id: 'settings',
          label: '設定',
          icon: Icons.settings_outlined),
      if (isBusiness)
        const V2NavItem(
            id: 'devLab',
            label: '開発中',
            icon: Icons.science_outlined),
    ];
  }

  Widget _bodyFor(String id, {required Color accent}) {
    switch (id) {
      case 'home':
        // sidebar バリアント = 旧 v2 ホーム、topnav = v2.1 ホーム（実データ）
        final variant = UiPreferences.instance.v2Variant;
        if (variant == UiPreferences.v2VariantTopNav) {
          return V2HomeTopNavScreen(accent: accent);
        }
        return const V2HomeScreen();
      // 支出: v2.1 ネイティブ実装（マネフォクラウド寄りのテーブル中心）
      case 'expenses':
        return V2ExpensesScreen(accent: accent);
      // 収入: v2.1 ネイティブ実装（見込み/確定の状態バッジ付きテーブル）
      case 'income':
        return V2IncomeScreen(accent: accent);
      // 資産タブは廃止。口座/カードはホームの総資産や支出の「ウォレット一覧」から。
      // クレカタブも廃止。カード一覧は支出タブ上部の「ウォレット一覧」ボタンから開く。
      // 集計: v2.1 ネイティブ実装（会計風 PL 月次表 + v1 集計画面へのリンク）
      case 'report':
        return V2ReportScreen(accent: accent);
      // 設定: v2.1 ネイティブ（マスター/ディテール、左メニュー + 右パネル）
      case 'settings':
        return V2SettingsScreen(accent: accent);
      // 開発中: v2.1 風バナー + v1 DevLab を埋め込み（事業モード専用）
      case 'devLab':
        return V2DevLabScreen(accent: accent);
      default:
        return V2HomeTopNavScreen(accent: accent);
    }
  }

  String _titleFor(String id) {
    return _navItems
        .firstWhere((i) => i.id == id,
            orElse: () => _navItems.first)
        .label;
  }

  @override
  Widget build(BuildContext context) {
    // UI は上タブ版（v2.1）に一本化。サイドバー版・v1 への切替は廃止。
    final accent = V2ModeAccent.of(AppModeManager.instance.current);
    return _buildTopNav(context, accent);
  }

  /// マネフォクラウド風: 左サイドバー + メイン。
  /// UI を上タブ版に一本化したため現在は未使用（将来の参照用に残置）。
  // ignore: unused_element
  Widget _buildSidebar(BuildContext context, Color accent) {
    final mode = AppModeManager.instance.current;
    return V2Shell(
      sidebar: V2Sidebar(
        items: _navItems,
        currentId: _currentId,
        onSelect: (id) => setState(() => _currentId = id),
        modeSwitcher: const V2ModeSwitcher(),
        footer: _SidebarFooter(versionLabel: _versionLabel),
      ),
      topBar: V2TopBar(
        title: _titleFor(_currentId),
        breadcrumbs: [
          mode == AppMode.business ? '事業' : '個人',
        ],
        actions: [
          _RecordMenuButton(
            accent: accent,
            mode: mode,
            onDark: false,
            onSelected: _openRecord,
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await UiPreferences.instance.setV2Variant(
                  UiPreferences.v2VariantTopNav);
            },
            icon: const Icon(Icons.view_compact, size: 14),
            label: const Text('上タブ版 (v2.1)'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await UiPreferences.instance.setUseV2Ui(false);
            },
            icon: const Icon(Icons.history, size: 14),
            label: const Text('v1 (旧)'),
          ),
        ],
      ),
      content: _bodyFor(_currentId, accent: accent),
    );
  }

  /// マネフォ ME 風（v2.1）: 上タブ + 中央カラム
  /// 事業モード時はヘッダーがダークネイビー、個人モード時は白
  Widget _buildTopNav(BuildContext context, Color accent) {
    final mode = AppModeManager.instance.current;
    final isBusiness = mode == AppMode.business;
    return V2TopNavShell(
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
        onSelect: (id) => setState(() => _currentId = id),
        accent: accent,
        // Shell の maxContentWidth と揃える（マネフォ ME 寄りに 1040px）
        maxWidth: 1040,
      ),
      content: _bodyFor(_currentId, accent: accent),
    );
  }

  /// 記録メニュー: 支出 / 収入 / 振替を選んで対応する入力モーダルを開く。
  void _openRecord(String kind) {
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page!),
    );
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

class _SidebarFooter extends StatelessWidget {
  final String? versionLabel;
  const _SidebarFooter({required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: V2Colors.accent,
              borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
            ),
            child: const Text(
              'v2 (β)',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const Spacer(),
          if (versionLabel != null)
            Text(versionLabel!,
                style: V2Typography.micro.copyWith(
                    color: V2Colors.sidebarTextMuted,
                    fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}
