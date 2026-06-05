import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'analysis_screen.dart';
import 'home_screen.dart';
import 'planning_screen.dart';

/// ホームとプランニングを下部ナビで切り替えるメインシェル。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          AnalysisScreen(),
          PlanningScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: AppColors.pinkSoft,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.pinkDark),
            label: 'ホーム',
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
            label: 'プランニング',
          ),
        ],
      ),
    );
  }
}
