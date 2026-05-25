import 'package:flutter/material.dart';

import '../data/update_checker.dart';
import 'calendar_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

/// アプリのルートシェル。下部タブで5画面を切り替える。
/// 状態はIndexedStackで保持（タブ遷移してもスクロール位置や入力中の値が残る）。
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  static const _tabs = <Widget>[
    HomeScreen(),
    ExpensesScreen(),
    CalendarScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  static const int _settingsTabIndex = 4;

  @override
  void initState() {
    super.initState();
    // 起動後にバージョンチェック（UI構築の邪魔をしないよう少し遅らせる）
    Future.delayed(const Duration(seconds: 2), _checkForUpdateAtStartup);
  }

  Future<void> _checkForUpdateAtStartup() async {
    final r = await UpdateChecker.instance.check();
    if (!mounted) return;
    if (!r.hasUpdate) return; // 新版が無ければ何もしない（失敗時も静かに）

    final goToSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFFEA580C)),
            SizedBox(width: 8),
            Text('新しいバージョン'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('現在: ${r.currentFull}'),
            Text('最新: ${r.latestFull}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (r.releaseNotes != null) ...[
              const SizedBox(height: 8),
              Text(r.releaseNotes!,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('後で')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('設定で更新')),
        ],
      ),
    );

    if (goToSettings == true && mounted) {
      setState(() => _index = _settingsTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE0E7FF),
        surfaceTintColor: Colors.white,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Color(0xFF1A237E)),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF1A237E)),
            label: '支出',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon:
                Icon(Icons.calendar_month, color: Color(0xFF1A237E)),
            label: 'カレンダー',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: Color(0xFF1A237E)),
            label: 'レポート',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF1A237E)),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
