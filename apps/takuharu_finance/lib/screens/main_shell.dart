import 'package:flutter/material.dart';

import '../data/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/startup_update_mixin.dart';
import 'analysis_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'income_screen.dart';
import 'planning_screen.dart';

/// ホームとプランニングを下部ナビで切り替えるメインシェル。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with StartupUpdateMixin, WidgetsBindingObserver {
  int _index = 0;
  final _pageController = PageController();

  static const _kPageDuration = Duration(milliseconds: 260);
  static const _kPageCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 起動少し後にアプリ更新を確認（Androidのみ・新版あればダイアログ）。
    scheduleStartupUpdateCheck();
    // プッシュ通知（相手の記録/コメント）の登録。許可ダイアログ→トークン保存。
    PushService.instance.register();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  /// 下部ナビのタップ → そのページへアニメ移動。
  void _goTo(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _pageController.animateToPage(i,
        duration: _kPageDuration, curve: _kPageCurve);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // アプリ復帰時にも更新を確認（スロットルで連打抑制）。
    if (state == AppLifecycleState.resumed) {
      runUpdateCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 横スワイプでタブを切り替え。各タブは keep-alive で状態を保持。
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          // ホームの「支出をすべて見る」から支出タブ(1)へ切替。
          _KeepAlivePage(
              child: HomeScreen(onOpenExpenses: () => _goTo(1))),
          const _KeepAlivePage(child: ExpensesScreen()),
          const _KeepAlivePage(child: IncomeScreen()),
          const _KeepAlivePage(child: AnalysisScreen()),
          const _KeepAlivePage(child: PlanningScreen()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        indicatorColor: AppColors.pinkSoft,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.pinkDark),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon:
                Icon(Icons.shopping_bag_rounded, color: AppColors.pinkDark),
            label: '支出',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon:
                Icon(Icons.savings_rounded, color: AppColors.pinkDark),
            label: '収入',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon:
                Icon(Icons.bar_chart_rounded, color: AppColors.pinkDark),
            label: '分析',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded),
            selectedIcon: Icon(Icons.star_rounded, color: AppColors.pinkDark),
            label: 'プラン',
          ),
        ],
      ),
    );
  }
}

/// PageView の各ページを生かしたまま保持する（IndexedStack 同様にタブの
/// 状態・スクロール位置を維持するため）。
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
