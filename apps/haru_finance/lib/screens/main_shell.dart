import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/account_repository.dart';
import '../data/household_service.dart';
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
    // 過去の「消費税・調整／値引き・調整」のカテゴリ直し（一度きり・裏で静かに）。
    _repairAdjustmentCategoriesOnce();
    // 支払元を「クレカ」に寄せ、初期に自動作成された口座を消す（一度きり）。
    _migratePaymentAndSeedAccountsOnce();
  }

  /// v1.0.6 の後片づけ（端末ごとに一度だけ・裏で静かに）。
  ///
  /// - 支払元が、初期に自動作成された口座名（ワンバンク / UFJ銀行）のままの
  ///   記録を「クレカ」に付け替える。
  /// - その自動作成された口座（id が seed_ で始まるもの）を削除する。
  ///   資産タブは v1.0.6 から口座ではなく「ためた合計」を主役にしたので、
  ///   使っていない口座が残っていると総額が合わなくなるため。
  Future<void> _migratePaymentAndSeedAccountsOnce() async {
    const key = 'haru.pay_migrated.v1'; // gitleaks:allow（保存済みフラグ名）
    const seedNames = ['ワンバンク', 'UFJ銀行'];
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) return;
      final hid = HouseholdService.instance.householdId;
      if (hid == null) return;
      await TxRepository.instance
          .replacePaymentMethod(hid, seedNames, 'クレカ');
      for (final a in await AccountRepository.instance.loadAll(hid)) {
        if (a.id.startsWith('seed_')) {
          await AccountRepository.instance.delete(hid, a.id);
        }
      }
      await prefs.setBool(key, true);
    } catch (_) {/* 次の起動で再挑戦 */}
  }

  /// 差額調整の行が「その他」で入っていた過去分を、そのレシートの主なカテゴリへ
  /// 付け替える。端末ごとに一度だけ実行し、失敗しても黙って諦める。
  Future<void> _repairAdjustmentCategoriesOnce() async {
    const key = 'haru.adjcat_repaired.v1';
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

/// PageView の各ページを生かしたまま保持する。
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
