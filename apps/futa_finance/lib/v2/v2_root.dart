import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_mode.dart';
import '../data/ui_preferences.dart';
import 'layout/shell.dart';
import 'screens/v2_home.dart';
import 'screens/v2_placeholder.dart';
import 'theme/colors.dart';
import 'theme/spacing.dart';
import 'theme/typography.dart';
import 'widgets/v2_mode_switcher.dart';
import 'widgets/v2_sidebar.dart';
import 'widgets/v2_topbar.dart';

/// v2 のルート。サイドバーのナビ選択を保持し、メイン領域を切り替える。
class V2Root extends StatefulWidget {
  const V2Root({super.key});

  @override
  State<V2Root> createState() => _V2RootState();
}

class _V2RootState extends State<V2Root> {
  String _currentId = 'home';
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    AppModeManager.instance.addListener(_onChange);
    UiPreferences.instance.addListener(_onChange);
    _loadVersion();
  }

  @override
  void dispose() {
    AppModeManager.instance.removeListener(_onChange);
    UiPreferences.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
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
          id: 'asset',
          label: '資産',
          icon: Icons.account_balance_wallet_outlined),
      const V2NavItem(
          id: 'cards',
          label: 'クレカ',
          icon: Icons.credit_card_outlined),
      const V2NavItem(
          id: 'report',
          label: '集計',
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

  Widget _bodyFor(String id) {
    switch (id) {
      case 'home':
        return const V2HomeScreen();
      case 'expenses':
        return const V2PlaceholderScreen(
            title: '支出',
            subtitle: '取引一覧 / 毎月引落予定 / カテゴリ別 / グラフ',
            icon: Icons.receipt_long_outlined,
            phaseLabel: 'Phase 4 で実装');
      case 'income':
        return const V2PlaceholderScreen(
            title: '収入',
            subtitle: '収入記録 / 見込み売上の管理',
            icon: Icons.savings_outlined,
            phaseLabel: 'Phase 4 で実装');
      case 'asset':
        return const V2PlaceholderScreen(
            title: '資産',
            subtitle: 'ウォレット一覧 / 通帳 / 入出金',
            icon: Icons.account_balance_wallet_outlined,
            phaseLabel: 'Phase 2 で実装');
      case 'cards':
        return const V2PlaceholderScreen(
            title: 'クレカ',
            subtitle: 'クレジットカード一覧 / 月別請求 / 引落予定',
            icon: Icons.credit_card_outlined,
            phaseLabel: 'Phase 5 で実装');
      case 'report':
        return const V2PlaceholderScreen(
            title: '集計',
            subtitle: 'PL / カテゴリ別 / テーブル / 月末締め',
            icon: Icons.bar_chart_outlined,
            phaseLabel: 'Phase 3 で実装');
      case 'settings':
        return const V2PlaceholderScreen(
            title: '設定',
            subtitle: 'カテゴリ / 支払方法 / バックアップ / 表示',
            icon: Icons.settings_outlined,
            phaseLabel: 'Phase 6 で実装');
      case 'devLab':
        return const V2PlaceholderScreen(
            title: '開発中',
            subtitle: 'PL / BS / 予算管理のプロトタイプ',
            icon: Icons.science_outlined,
            phaseLabel: 'v1 から移植予定');
      default:
        return const V2HomeScreen();
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
          OutlinedButton.icon(
            onPressed: () {
              // Phase 0 ではダミー。Phase 1+ で記録モーダル実装。
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('記録ボタン: Phase 1 以降で実装'),
                ),
              );
            },
            icon: const Icon(Icons.add, size: 14),
            label: const Text('記録'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              // v1 に戻す（手動切替の出口）
              await UiPreferences.instance.setUseV2Ui(false);
            },
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: const Text('v1 に戻す'),
          ),
        ],
      ),
      content: _bodyFor(_currentId),
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
