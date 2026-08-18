import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deep_link_service.dart';
import '../data/household_service.dart';
import '../data/push_service.dart';
import '../data/subscription_auto_record.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/startup_update_mixin.dart';
import '../widgets/web_layout.dart';
import 'analysis_screen.dart';
import 'asset_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'income_screen.dart';
import 'record_menu.dart';

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
    // 支払日が来た固定費を自動で支出に記帳（裏で静かに・二重計上なし）。
    _autoRecordSubscriptions();
    // 明細共有リンク（takuharu://… / Web の ?r=）で開かれていたら、その明細へ。
    DeepLinkService.instance.init();
  }

  /// 支払日を過ぎた固定費を今月分として自動記帳する（起動時・復帰時）。
  /// 失敗しても黙って諦める（サービス側で二重計上を防止・連打を間引く）。
  Future<void> _autoRecordSubscriptions() async {
    try {
      await SubscriptionAutoRecord.instance.run();
    } catch (_) {/* 次の起動/復帰で再挑戦 */}
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
      // 復帰時にも固定費の自動記帳を確認（サービス側で10分間引き）。
      _autoRecordSubscriptions();
    }
  }

  // 5タブの定義（下ナビ・サイドナビの両方で使う）。
  static const _tabs = <_TabDef>[
    _TabDef('ホーム', Icons.home_outlined, Icons.home_rounded),
    _TabDef('支出', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded),
    _TabDef('収入', Icons.savings_outlined, Icons.savings_rounded),
    _TabDef('資産', Icons.account_balance_outlined, Icons.account_balance_rounded),
    _TabDef('分析', Icons.bar_chart_outlined, Icons.bar_chart_rounded),
  ];

  Widget _pages() => PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          // ホームの「支出をすべて見る」から支出タブ(1)へ切替。
          _KeepAlivePage(child: HomeScreen(onOpenExpenses: () => _goTo(1))),
          const _KeepAlivePage(child: ExpensesScreen()),
          const _KeepAlivePage(child: IncomeScreen()),
          const _KeepAlivePage(child: AssetScreen()),
          const _KeepAlivePage(child: AnalysisScreen()),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // 広い画面（Web/タブレット横）は左サイドナビ、狭い画面は下タブ。
    if (isWideLayout(context)) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _SideNav(
                tabs: _tabs,
                index: _index,
                onSelected: _goTo,
                onRecord: _onRecord,
              ),
              const VerticalDivider(width: 1, color: AppColors.divider),
              Expanded(child: _pages()),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      // 横スワイプでタブを切り替え。各タブは keep-alive で状態を保持。
      body: _pages(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        indicatorColor: AppColors.pinkSoft,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon, color: AppColors.pinkDark),
              label: t.label,
            ),
        ],
      ),
    );
  }

  /// サイドナビの「記録する」から記録メニューを開く。
  Future<void> _onRecord() async {
    await showRecordMenu(context);
  }
}

/// タブ1つ分の定義。
class _TabDef {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _TabDef(this.label, this.icon, this.selectedIcon);
}

/// 広い画面用の左サイドナビ（アプリ名＋タブ＋「記録する」）。
class _SideNav extends StatelessWidget {
  final List<_TabDef> tabs;
  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback onRecord;
  const _SideNav({
    required this.tabs,
    required this.index,
    required this.onSelected,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ロゴ＋アプリ名。
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 18),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.pink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'たくはる\nファイナンス',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pinkDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // タブ。
          for (int i = 0; i < tabs.length; i++)
            _NavItem(
              tab: tabs[i],
              selected: i == index,
              onTap: () => onSelected(i),
            ),
          const Spacer(),
          // 「記録する」ボタン（常設）。
          FilledButton.icon(
            onPressed: onRecord,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('記録する'),
          ),
        ],
      ),
    );
  }
}

/// サイドナビの1項目。
class _NavItem extends StatelessWidget {
  final _TabDef tab;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      {required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.pinkSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 20,
                  color: selected ? AppColors.pinkDark : AppColors.textSub,
                ),
                const SizedBox(width: 12),
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.pinkDark : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
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
