import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/household_service.dart';
import '../data/push_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/startup_update_mixin.dart';
import 'analysis_screen.dart';
import 'asset_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'income_screen.dart';

/// ホーム・支出・収入・資産・分析を下部ナビで切り替えるメインシェル。
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
    // 過去の「消費税・調整／値引き・調整」のカテゴリ直し（一度きり・裏で静かに）。
    _repairAdjustmentCategoriesOnce();
  }

  /// 差額調整の行が「その他」で入っていた過去分を、そのレシートの主なカテゴリへ
  /// 付け替える（v0.2.97）。端末ごとに一度だけ実行し、失敗しても黙って諦める
  /// （次の起動でまた試す）。金額・日付・品名は変えない。
  Future<void> _repairAdjustmentCategoriesOnce() async {
    const key = 'takuharu.adjcat_repaired.v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) return;
      final hid = HouseholdService.instance.householdId;
      if (hid == null) return;
      await TxRepository.instance.repairAdjustmentCategories(hid);
      await prefs.setBool(key, true);
    } catch (_) {/* 次の起動で再挑戦 */}
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
          const _KeepAlivePage(child: AssetScreen()),
          const _KeepAlivePage(child: AnalysisScreen()),
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
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon:
                Icon(Icons.account_balance_rounded, color: AppColors.pinkDark),
            label: '資産',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon:
                Icon(Icons.bar_chart_rounded, color: AppColors.pinkDark),
            label: '分析',
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
