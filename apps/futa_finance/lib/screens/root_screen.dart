import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_mode.dart';
import '../data/update_checker.dart';
import '../data/update_installer.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'income_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

/// アプリのルートシェル。下部タブで6画面を切り替える + 上部にモード切替ストリップ。
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
    IncomeScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _checkForUpdateAtStartup);
  }

  // ユーザーが「スキップ」したバージョンを覚えるキー。
  // ここに保存されたバージョンが最新と一致したらダイアログを出さない。
  static const _skipVersionKey = 'futa.update.skip_version';

  Future<void> _checkForUpdateAtStartup() async {
    final r = await UpdateChecker.instance.check();
    if (!mounted) return;
    if (!r.hasUpdate) return;
    if (r.fetchFailed) return;

    // 「このバージョンはスキップ」したことがあれば通知しない
    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getString(_skipVersionKey);
    if (skipped != null && skipped == r.latestFull) return;
    if (!mounted) return;

    // 既に DL 済みなら「インストール再開」専用ダイアログを出す
    final url = r.downloadUrl;
    if (url != null) {
      final cached = await UpdateInstaller.instance.getCachedApk(url);
      if (!mounted) return;
      if (cached != null) {
        await _showResumeInstallDialog(r, cached);
        return;
      }
    }

    final action = await showDialog<String>(
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
              onPressed: () => Navigator.pop(context, 'skip'),
              child: const Text('このバージョンは飛ばす')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'later'),
              child: const Text('後で')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'update'),
              child: const Text('更新する')),
        ],
      ),
    );

    if (action == 'skip') {
      await prefs.setString(_skipVersionKey, r.latestFull);
    } else if (action == 'update') {
      await _downloadAndInstall(r);
    }
    // 'later' or null は何もしない（次回起動時に再度通知）
  }

  /// DL 済み APK が見つかった時の「インストール再開」専用ダイアログ。
  /// ユーザーが前回インストール画面を閉じてしまった、起動時など。
  Future<void> _showResumeInstallDialog(
      UpdateCheckResult r, File cachedApk) async {
    final sizeMb = (await cachedApk.length()) / 1024 / 1024;
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download_done, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Text('ダウンロード済み'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.latestFull} は既にダウンロード済みです',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'サイズ: ${sizeMb.toStringAsFixed(1)} MB\n'
              'そのままインストール画面を開きますか？',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'skip'),
              child: const Text('このバージョンは飛ばす')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'later'),
              child: const Text('後で')),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'install'),
            child: const Text('インストール'),
          ),
        ],
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    if (action == 'skip') {
      await prefs.setString(_skipVersionKey, r.latestFull);
      // スキップしたバージョンの DL ファイルも削除（容量解放）
      try {
        await cachedApk.delete();
      } catch (_) {}
    } else if (action == 'install') {
      // インストール権限チェックして即起動
      final perm =
          await UpdateInstaller.instance.ensureInstallPermission();
      if (!mounted) return;
      if (perm != InstallPermissionStatus.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('インストール権限が必要です')),
        );
        return;
      }
      await UpdateInstaller.instance.installApk(cachedApk.path);
    }
    // 'later' or null は何もしない
  }

  /// ダウンロード進捗ダイアログを開き、APKをDL→インストールフローまで実行。
  Future<void> _downloadAndInstall(UpdateCheckResult r) async {
    final url = r.downloadUrl;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ダウンロードURLが取得できませんでした')),
      );
      return;
    }

    // インストール許可のチェック（Android: 不明なソースからのインストール）
    final permStatus =
        await UpdateInstaller.instance.ensureInstallPermission();
    if (!mounted) return;
    if (permStatus != InstallPermissionStatus.granted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('インストール許可が必要'),
          content: const Text(
              'アプリ更新を自動インストールするには「不明なソースからのアプリのインストール」を許可する必要があります。\n\n'
              '設定画面を開きますか？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('設定を開く')),
          ],
        ),
      );
      if (ok == true) await UpdateInstaller.instance.openInstallSettings();
      return;
    }

    // 進捗ダイアログ（StatefulBuilder で進捗値だけ再描画）
    double progress = 0;
    final progressKey = GlobalKey<State<StatefulBuilder>>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          key: progressKey,
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('ダウンロード中...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)} %',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      final file = await UpdateInstaller.instance.downloadApk(
        url,
        onProgress: (p) {
          progress = p;
          // ダイアログ内の StatefulBuilder にだけ再描画させる
          progressKey.currentState?.setState(() {});
        },
      );
      if (!mounted) return;
      // 進捗ダイアログを閉じる
      Navigator.of(context, rootNavigator: true).pop();

      // OS のインストーラを起動
      await UpdateInstaller.instance.installApk(file.path);
      // この後 OS のインストール画面が出る。アプリが置換されると再起動。
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ダウンロードに失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _ModeStrip(),
          Expanded(child: IndexedStack(index: _index, children: _tabs)),
        ],
      ),
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
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings, color: Color(0xFF16A34A)),
            label: '収入',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: Color(0xFF1A237E)),
            label: '集計',
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

/// 画面上部に常時表示されるモード切替ストリップ。
class _ModeStrip extends StatefulWidget {
  const _ModeStrip();

  @override
  State<_ModeStrip> createState() => _ModeStripState();
}

class _ModeStripState extends State<_ModeStrip> {
  @override
  void initState() {
    super.initState();
    AppModeManager.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    AppModeManager.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = AppModeManager.instance.current;
    return SafeArea(
      bottom: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          children: [
            _modeButton(AppMode.business, current),
            const SizedBox(width: 6),
            _modeButton(AppMode.personal, current),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(AppMode mode, AppMode current) {
    final selected = mode == current;
    final color = mode.accentColor;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selected
            ? null
            : () => AppModeManager.instance.setMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5E7EB),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mode.icon,
                  size: 16,
                  color: selected ? color : const Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Text(
                '${mode.label}モード',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
