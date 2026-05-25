import 'package:flutter/material.dart';

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
