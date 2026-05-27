import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_mode.dart';
import '../data/update_checker.dart';
import '../data/update_installer.dart';
import 'asset_screen.dart';
import 'expense_input_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'income_input_screen.dart';
import 'income_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'table_view_screen.dart';
import 'transfer_input_screen.dart';

/// アプリのルートシェル。下部タブで6画面を切り替える + 上部にモード切替ストリップ。
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

/// 広い画面で開く記録パネルの種類。
enum _RecordPanelKind { expense, income, transfer }

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  /// 広い画面で開いている記録パネル。null=閉じている。
  _RecordPanelKind? _recordPanel;

  // インデックス対応:
  //   0=Home, 1=Expenses, 2=Income, 3=Report, 4=Settings,
  //   5=TableView (Web専用), 6=Asset
  // ※ 既存インデックスへの影響を避けるため Asset は末尾に追加。
  //   モバイルナビとサイドナビの表示順は別途マッピング。
  static const _tabs = <Widget>[
    HomeScreen(),
    ExpensesScreen(),
    IncomeScreen(),
    ReportScreen(),
    SettingsScreen(),
    TableViewScreen(),
    AssetScreen(),
  ];

  /// モバイル下タブの表示順 → _tabs インデックスのマッピング。
  /// 「資産」は集計の前に表示（残高 → 詳細集計の流れ）。
  static const _mobileTabOrder = <int>[0, 1, 2, 6, 3, 4];

  /// 広い画面（Web/Tablet/Desktop）かどうかの判定しきい値。
  /// 900px 以上で NavigationRail（サイドバー）レイアウトに切替。
  static const double _wideBreakpoint = 900;

  @override
  void initState() {
    super.initState();
    // Web ではアプリ内アップデート確認（APK配信）は無意味なのでスキップ。
    if (!kIsWeb) {
      Future.delayed(const Duration(seconds: 2), _checkForUpdateAtStartup);
    }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        return wide ? _buildWideLayout() : _buildMobileLayout();
      },
    );
  }

  // ── モバイル/狭い画面（既存のレイアウト） ──
  Widget _buildMobileLayout() {
    return Scaffold(
      body: Column(
        children: [
          const _ModeStrip(),
          Expanded(child: IndexedStack(index: _index, children: _tabs)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        // _index は _tabs のインデックス。NavigationBar には mobileTabOrder
        // 上の位置を渡し、選択時は逆引きして _tabs のインデックスに戻す。
        selectedIndex: _mobileTabOrder.indexOf(_index).clamp(0, _mobileTabOrder.length - 1),
        onDestinationSelected: (i) =>
            setState(() => _index = _mobileTabOrder[i]),
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet,
                color: Color(0xFF1A237E)),
            label: '資産',
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

  // ── 広い画面（Web/Desktop） サイドバー固定レイアウト ──
  /// メインコンテンツの最大幅。これ以上はサイドバーとの間に余白を作る。
  /// 画面が広くてもコンテンツが横にダラっと伸びないようにする。
  static const double _wideContentMaxWidth = 1080;

  Widget _buildWideLayout() {
    return Scaffold(
      body: Row(
        children: [
          _SideNav(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            onRecord: (kind) {
              setState(() {
                // 同じパネルを押したら閉じる、違う種類なら切替
                _recordPanel = _recordPanel == kind ? null : kind;
              });
            },
            recordPanelKind: _recordPanel,
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _wideContentMaxWidth),
                child: IndexedStack(index: _index, children: _tabs),
              ),
            ),
          ),
          if (_recordPanel != null) ...[
            const VerticalDivider(width: 1, thickness: 1),
            _RecordPanel(
              kind: _recordPanel!,
              onClose: () => setState(() => _recordPanel = null),
            ),
          ],
        ],
      ),
    );
  }
}

/// 広い画面用、右側にスライドする記録パネル。
/// 中身は ExpenseInputScreen / IncomeInputScreen をそのまま埋め込み、
/// 内部 Navigator の pop（保存完了 or キャンセル）でパネルを閉じる。
class _RecordPanel extends StatelessWidget {
  const _RecordPanel({required this.kind, required this.onClose});

  final _RecordPanelKind kind;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Container(
        color: const Color(0xFFFAFAFA),
        child: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: const RouteSettings(name: '/record'),
            builder: (_) {
              switch (kind) {
                case _RecordPanelKind.expense:
                  return const ExpenseInputScreen();
                case _RecordPanelKind.income:
                  return const IncomeInputScreen();
                case _RecordPanelKind.transfer:
                  return const TransferInputScreen();
              }
            },
          ),
          // onGenerateRoute と組み合わせる場合は onPopPage を使う必要がある。
          // ignore: deprecated_member_use
          onPopPage: (route, result) {
            // 内側 Navigator が pop した（保存 or AppBar の戻る）
            // パネルごと閉じる。リストは Stream で自動同期されるので明示更新不要。
            WidgetsBinding.instance.addPostFrameCallback((_) => onClose());
            return route.didPop(result);
          },
        ),
      ),
    );
  }
}

/// 広い画面用のサイドナビ。
/// アプリ名 + モード切替 + 5タブを縦に並べる。
class _SideNav extends StatefulWidget {
  const _SideNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onRecord,
    required this.recordPanelKind,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<_RecordPanelKind> onRecord;
  final _RecordPanelKind? recordPanelKind;

  @override
  State<_SideNav> createState() => _SideNavState();
}

class _SideNavState extends State<_SideNav> {
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
    return Container(
      width: 240,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── アプリヘッダー ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: current.accentColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        '財',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'FutaFinance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── モード切替 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _modeButton(AppMode.business, current),
                  const SizedBox(height: 6),
                  _modeButton(AppMode.personal, current),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Divider(height: 1),
            ),

            // ── ナビアイテム ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _navItem(0, Icons.home_outlined, Icons.home, 'ホーム'),
                  _navItem(1, Icons.receipt_long_outlined,
                      Icons.receipt_long, '支出'),
                  _navItem(2, Icons.savings_outlined, Icons.savings, '収入',
                      selectedColor: const Color(0xFF16A34A)),
                  _navItem(6, Icons.account_balance_wallet_outlined,
                      Icons.account_balance_wallet, '資産'),
                  _navItem(3, Icons.bar_chart_outlined, Icons.bar_chart,
                      '集計'),
                  _navItem(5, Icons.table_chart_outlined,
                      Icons.table_chart, 'テーブル'),
                  _navItem(4, Icons.settings_outlined, Icons.settings,
                      '設定'),
                ],
              ),
            ),

            // ── 記録ボタン（広い画面専用、右側パネルをトグル） ──
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.edit_note,
                      size: 14, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 6),
                  Text(
                    '記録',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Column(
                children: [
                  _recordButton(
                    _RecordPanelKind.expense,
                    Icons.remove_circle_outline,
                    '支出を記録',
                    const Color(0xFF1A237E),
                  ),
                  const SizedBox(height: 6),
                  _recordButton(
                    _RecordPanelKind.income,
                    Icons.add_circle_outline,
                    '収入を記録',
                    const Color(0xFF16A34A),
                  ),
                  const SizedBox(height: 6),
                  _recordButton(
                    _RecordPanelKind.transfer,
                    Icons.swap_horiz,
                    '振替を記録',
                    const Color(0xFFEA580C),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordButton(
    _RecordPanelKind kind,
    IconData icon,
    String label,
    Color color,
  ) {
    final active = widget.recordPanelKind == kind;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onRecord(kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : color,
                ),
              ),
            ),
            if (active)
              const Icon(Icons.close, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(AppMode mode, AppMode current) {
    final selected = mode == current;
    final color = mode.accentColor;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: selected ? null : () => AppModeManager.instance.setMode(mode),
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
          children: [
            Icon(mode.icon,
                size: 16, color: selected ? color : const Color(0xFF9CA3AF)),
            const SizedBox(width: 8),
            Text(
              '${mode.label}モード',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData iconOutlined,
    IconData iconFilled,
    String label, {
    Color selectedColor = const Color(0xFF1A237E),
  }) {
    final selected = widget.selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onDestinationSelected(index),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE0E7FF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                selected ? iconFilled : iconOutlined,
                size: 20,
                color: selected ? selectedColor : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? selectedColor
                      : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
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
