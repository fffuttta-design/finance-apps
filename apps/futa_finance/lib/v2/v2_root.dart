import 'package:flutter/material.dart';

import '../data/app_mode.dart';
import '../data/data_migration_service.dart';
import '../data/repository_provider.dart';
import '../data/ui_preferences.dart';
import '../screens/expense_input_screen.dart';
import '../screens/income_input_screen.dart';
import '../screens/transfer_input_screen.dart';
import 'layout/topnav_shell.dart';
import 'screens/v2_devlab.dart';
import 'screens/v2_expenses.dart';
import 'screens/v2_home_topnav.dart';
import 'screens/v2_income.dart';
import 'screens/v2_report.dart';
import 'screens/v2_settings.dart';
import 'theme/mode_accent.dart';
import '../widgets/startup_update_mixin.dart';
import 'widgets/v2_mode_switcher.dart';
import 'widgets/v2_top_header.dart';
import 'widgets/v2_top_nav.dart';

/// v2 のルート。サイドバーのナビ選択を保持し、メイン領域を切り替える。
class V2Root extends StatefulWidget {
  const V2Root({super.key});

  @override
  State<V2Root> createState() => _V2RootState();
}

class _V2RootState extends State<V2Root> with StartupUpdateMixin {
  String _currentId = 'home';

  @override
  void initState() {
    super.initState();
    AppModeManager.instance.addListener(_onChange);
    UiPreferences.instance.addListener(_onChange);
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
        return V2HomeTopNavScreen(accent: accent);
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

  @override
  Widget build(BuildContext context) {
    // UI は上タブ版（v2.1）に一本化。サイドバー版・v1 への切替は廃止。
    final accent = V2ModeAccent.of(AppModeManager.instance.current);
    return _buildTopNav(context, accent);
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

