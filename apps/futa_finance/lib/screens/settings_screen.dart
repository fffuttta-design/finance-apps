import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/auth_service.dart';
import '../data/backup_repository.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/ui_preferences.dart';
import '../data/update_checker.dart';
import '../data/update_installer.dart';
import '../mock/mock_data.dart';
import '../utils/web_reload_stub.dart'
    if (dart.library.html) '../utils/web_reload_web.dart';
import 'account_editor_screen.dart';
import 'card_editor_screen.dart';
import 'category_editor_screen.dart';
import 'checklist_editor_screen.dart';
import 'income_master_screen.dart';
import 'subscription_list_screen.dart';

/// 設定のトップ画面。各サブ設定への入り口を並べる。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UpdateCheckResult? _versionResult;
  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final c = await UpdateChecker.instance.getCurrent();
    if (!mounted) return;
    setState(() {
      _versionResult = UpdateCheckResult(
        currentVersion: c.version,
        currentBuildNumber: c.buildNumber,
        hasUpdate: false,
      );
    });
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final r = await UpdateChecker.instance.check();
    if (!mounted) return;
    setState(() {
      _versionResult = r;
      _checking = false;
    });
    final msg = r.fetchFailed
        ? '最新バージョン情報の取得に失敗しました'
        : r.hasUpdate
            ? '新しいバージョン ${r.latestFull} が利用可能です'
            : '最新版です（${r.currentFull}）';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _downloadAndInstall() async {
    final url = _versionResult?.downloadUrl;
    if (url == null) return;

    // インストール権限チェック
    final permStatus =
        await UpdateInstaller.instance.ensureInstallPermission();
    if (!mounted) return;
    if (permStatus != InstallPermissionStatus.granted) {
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('インストール許可が必要'),
          content: const Text(
              'アプリの更新版を自動インストールするには、'
              '「不明なソースからのアプリのインストール」を許可する必要があります。\n\n'
              '設定画面を開きますか？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('後で')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('設定を開く')),
          ],
        ),
      );
      if (goSettings == true) {
        await UpdateInstaller.instance.openInstallSettings();
      }
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      final file = await UpdateInstaller.instance.downloadApk(
        url,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      setState(() => _downloading = false);

      // OSのインストーラを起動
      final ok = await UpdateInstaller.instance.installApk(file.path);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('インストーラの起動に失敗しました')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新版の取得に失敗: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '設定',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('お金の項目'),
            _tile(
              icon: Icons.category,
              title: 'カテゴリ編集',
              subtitle: '大カテゴリ・小カテゴリ・アイコンの追加と編集',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CategoryEditorScreen()),
              ),
            ),
            _tile(
              icon: Icons.account_balance,
              title: 'ウォレット',
              subtitle: '銀行口座・現金（財布）・電子マネー(PayPay等)の登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AccountEditorScreen()),
              ),
            ),
            _tile(
              icon: Icons.credit_card,
              title: 'クレジットカード',
              subtitle: '取引で選択するカードの登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CardEditorScreen()),
              ),
            ),
            _tile(
              icon: Icons.attach_money,
              title: '収入マスタ',
              subtitle: '継続収入・単発収入のテンプレート登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const IncomeMasterScreen()),
              ),
            ),
            _tile(
              icon: Icons.subscriptions,
              title: '固定費一覧',
              subtitle: '月払い/年払い・定額/変動の継続支払いを一覧管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionListScreen()),
              ),
            ),
            _tile(
              icon: Icons.checklist,
              title: '月末締めチェックリスト',
              subtitle: '締め前に確認するサイト・項目を登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ChecklistEditorScreen()),
              ),
            ),
            const SizedBox(height: 8),

            _section('表示'),
            _hideInactiveTile(),

            const SizedBox(height: 8),

            _section('アプリ情報'),
            _versionCard(),

            const SizedBox(height: 8),
            _section('データ管理'),
            _tile(
              icon: Icons.cloud_upload,
              title: 'バックアップを書き出す',
              subtitle: '全データを1つのJSONファイルとして共有（Drive等へ保存）',
              onTap: () => _exportBackup(context),
            ),
            _tile(
              icon: Icons.cloud_download,
              title: 'バックアップから復元',
              subtitle: 'JSONファイルを取り込んで既存データを上書き',
              onTap: () => _importBackup(context),
            ),
            // Web 専用: D&D で取り込めるゾーン。
            // ブラウザの仕様上、ファイルピッカーに絶対パスを指定できないため
            // 「H:\マイドライブ\ツール開発\FutaFinance\」 をエクスプローラで
            // 開いておき、JSONファイルをここにドロップしてもらう運用。
            if (kIsWeb) _importDropZone(context),
            _tile(
              icon: Icons.restore,
              title: '直前の状態に戻す（自動スナップショット）',
              subtitle: '取り込み実行の直前に自動保存された状態を一覧から復元',
              onTap: () => _showAutoSnapshots(context),
            ),
            _tile(
              icon: Icons.upload_file,
              title: 'サンプルデータを投入（全置換）',
              subtitle: '既存の取引を全削除し、5月実データ30件 + 住信SBI口座をセット',
              onTap: () => _seedSampleData(context),
            ),
            _tile(
              icon: Icons.delete_sweep,
              title: '全取引を削除',
              subtitle: '入力済みの取引を全て消去（自動スナップショットから復元可）',
              onTap: () => _clearAll(context),
              danger: true,
            ),

            const SizedBox(height: 8),
            _section('アカウント'),
            _accountTile(),
          ],
        ),
      ),
    );
  }

  /// アカウント情報＋サインアウトボタン。
  Widget _accountTile() {
    final user = AuthService.instance.currentUser;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          // アバター
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: user?.photoURL != null
                ? ClipOval(
                    child: Image.network(
                      user!.photoURL!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.person, color: Color(0xFF1A237E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? user?.email ?? '未ログイン',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (user?.email != null)
                  Text(
                    user!.email!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('サインアウト',
                style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('サインアウト'),
        content: const Text(
            'サインアウトすると、サインインするまでアプリが使えなくなります。\n'
            'クラウドのデータはそのまま保持されます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('サインアウト')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.instance.signOut();
      // authStateChanges 発火 → AuthGate が自動で AuthScreen に切替
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('サインアウトに失敗: $e')),
      );
    }
  }

  Widget _versionCard() {
    final r = _versionResult;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: r?.hasUpdate == true
              ? const Color(0xFF1A237E)
              : const Color(0xFFE5E7EB),
          width: r?.hasUpdate == true ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFF1A237E), size: 22),
              const SizedBox(width: 8),
              const Text('現在のバージョン',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              const Spacer(),
              Text(
                r?.currentFull ?? '取得中…',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A237E),
                    letterSpacing: 0.5),
              ),
            ],
          ),
          if (r?.latestVersion != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  r!.hasUpdate ? Icons.system_update : Icons.check_circle,
                  size: 16,
                  color: r.hasUpdate
                      ? const Color(0xFFEA580C)
                      : const Color(0xFF16A34A),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.hasUpdate
                        ? '新しいバージョンあり: ${r.latestFull}'
                        : '最新版です',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: r.hasUpdate
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ),
            if (r.releaseNotes != null) ...[
              const SizedBox(height: 4),
              Text(r.releaseNotes!,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280))),
            ],
          ],
          const SizedBox(height: 12),
          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 6,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF1A237E)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ダウンロード中… ${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checking ? null : _checkUpdate,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_checking ? '確認中…' : '最新バージョンを確認'),
                  ),
                ),
                if (r?.hasUpdate == true && r?.downloadUrl != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _downloadAndInstall,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('更新版を入手'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _seedSampleData(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('サンプルデータを投入'),
        content: const Text(
            '現在の取引を全て削除し、2026年5月の実データ30件で置換します。\n'
            '住信SBI口座（月初¥10,652,701）が未登録なら同時に追加します。\n\n'
            '※ 実行直前の状態は自動スナップショットとして保存されます。\n'
            '「設定 → 直前の状態に戻す」でいつでも復元可能です。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('投入')),
        ],
      ),
    );
    if (ok != true) return;

    // 破壊的操作前に自動スナップショット（誤実行からの一発復旧用）
    await BackupRepository.instance
        .savePreImportSnapshot(reason: 'pre-sample');

    await TransactionRepository.instance
        .replaceAll(MockData.sampleTransactions());

    final settings = SettingsRepository();
    final payments = await settings.loadPayments();
    final hasSbi = payments.bankAccounts.any((b) => b.name == '住信SBI');
    if (!hasSbi) {
      await settings.savePayments(payments.copyWith(
        bankAccounts: [...payments.bankAccounts, MockData.sampleBank],
      ));
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(hasSbi
              ? 'サンプル30件で置換しました'
              : 'サンプル30件 + 住信SBI口座を投入しました')),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('全取引を削除'),
        content: const Text(
            '登録されている全ての取引を削除します。\n\n'
            '※ 実行直前の状態は自動スナップショットとして保存されます。\n'
            '「設定 → 直前の状態に戻す」でいつでも復元可能です。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;

    // 破壊的操作前に自動スナップショット
    await BackupRepository.instance
        .savePreImportSnapshot(reason: 'pre-wipe');

    await TransactionRepository.instance.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全取引を削除しました（直前の状態に戻せます）')),
    );
  }

  /// バックアップ書き出し: 全データを一時ファイルに保存して共有シートで送信。
  Future<void> _exportBackup(BuildContext context) async {
    try {
      final json = await BackupRepository.instance.exportAll();

      // 端末の一時ディレクトリに書き出し → 共有
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'futa-finance-backup-$stamp.json';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'FutaFinance バックアップ ($stamp)',
          text:
              'FutaFinance のデータバックアップ ($stamp)。\n'
              '保存先推奨: マイドライブ/ツール開発/FutaFinance/backups/',
        ),
      );
      // 「最後の手動バックアップ日時」を記録 → 14日リマインダーの基準になる。
      await BackupRepository.instance.markManualBackupDone();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('書き出しに失敗しました: $e')),
      );
    }
  }

  /// インポート完了画面: note + モード別の件数前後差分を見やすく表示。
  /// 件数比較なのでデータ量が増えても表示は一定（軽量）。
  Future<void> _showImportSuccessDialog(
      BuildContext context, BackupImportResult r) async {
    String labelForKey(String key) {
      switch (key) {
        case 'transactions':
          return '取引';
        case 'payments':
          return '銀行/カード';
        case 'categories':
          return 'カテゴリ';
        case 'subscriptions':
          return '固定費';
        case 'checklist':
          return 'チェックリスト';
        case 'income_sources':
          return '収入マスタ';
        case 'monthly_snapshots':
          return '月初残高';
        case 'month_closing':
          return '月末締め';
      }
      return key;
    }

    String labelForMode(String mode) =>
        mode == 'business' ? '事業モード' : '個人モード';

    /// 1モード分の件数差分行リスト。変化があるキーは強調表示。
    List<Widget> rowsForMode(String modeLabel) {
      final before = r.beforeCounts[modeLabel] ?? const <String, int>{};
      final after = r.afterCounts[modeLabel] ?? const <String, int>{};
      final keys = {...before.keys, ...after.keys}.toList()..sort();
      final rows = <Widget>[];
      for (final k in keys) {
        final b = before[k] ?? 0;
        final a = after[k] ?? 0;
        final diff = a - b;
        final changed = diff != 0;
        final color = changed
            ? (diff > 0
                ? const Color(0xFF16A34A) // 増加=緑
                : const Color(0xFFDC2626)) // 減少=赤
            : const Color(0xFF6B7280);
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(labelForKey(k),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
              ),
              Expanded(
                child: Text(
                  changed
                      ? '$b → $a (${diff > 0 ? "+" : ""}$diff)'
                      : '$a (変化なし)',
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontFamily: 'monospace',
                      fontWeight:
                          changed ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
            ],
          ),
        ));
      }
      return rows;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
            const SizedBox(width: 8),
            const Text('復元完了'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // メモ表示（スクリプトの --note フィールド）
              if (r.note != null && r.note!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sticky_note_2,
                          size: 16, color: Color(0xFF92400E)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r.note!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // バージョン/書出日時
              Text(
                '取り込み元: ${r.appVersion.isEmpty ? "（不明）" : "v${r.appVersion}"}',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
              if (r.exportedAt.isNotEmpty)
                Text('書出: ${r.exportedAt}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 8),
              // 各モードの件数差分
              for (final mode in r.afterCounts.keys) ...[
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 14,
                      decoration: BoxDecoration(
                        color: mode == 'business'
                            ? const Color(0xFF1A237E)
                            : const Color(0xFFEA580C),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      labelForMode(mode),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...rowsForMode(mode),
                const SizedBox(height: 12),
              ],
              const Text(
                'アプリを一度再起動すると、画面に反映されます。',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// 自動スナップショット一覧を BottomSheet で表示し、選択して復元。
  /// 「直前の状態に戻す」ボタン。インポート前に自動保存されたものを利用する。
  Future<void> _showAutoSnapshots(BuildContext context) async {
    final snapshots =
        await BackupRepository.instance.listAutoSnapshots();
    if (!context.mounted) return;

    if (snapshots.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('自動スナップショット'),
          content: const Text(
              '自動保存された状態はまだありません。\n'
              'バックアップ取り込みを実行すると、その直前の状態が自動的にここに保存されます。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<AutoSnapshotInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.history, color: Color(0xFF1A237E)),
                    SizedBox(width: 8),
                    Text(
                      '自動スナップショット一覧',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '取り込み直前に自動保存されたデータです。新しい順に表示しています（最大10件）。',
                  style:
                      TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: ListView.builder(
                  itemCount: snapshots.length,
                  itemBuilder: (_, i) {
                    final s = snapshots[i];
                    final isLatest = i == 0;
                    return ListTile(
                      leading: Icon(
                        isLatest ? Icons.bookmark : Icons.bookmark_border,
                        color: isLatest
                            ? const Color(0xFF1A237E)
                            : const Color(0xFF9CA3AF),
                      ),
                      title: Row(
                        children: [
                          Text(
                            s.displayLabel,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace'),
                          ),
                          if (isLatest) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0E7FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '最新',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF1A237E),
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          if (s.reasonLabel != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                s.reasonLabel!,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(s.displaySize,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9CA3AF))),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Color(0xFF9CA3AF)),
                      onTap: () => Navigator.pop(sheet, s),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null || !context.mounted) return;

    // 確認ダイアログ
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('この状態に戻しますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日時: ${selected.displayLabel}'),
            Text('サイズ: ${selected.displaySize}'),
            const SizedBox(height: 12),
            const Text(
              '現在のデータは上書きされます。\n（念のため、この復元の直前にも自動スナップショットが取られます）',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEA580C)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('戻す'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final result = await BackupRepository.instance
          .restoreFromSnapshot(selected.file);
      if (!context.mounted) return;
      await _showImportSuccessDialog(context, result);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.history, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('自動スナップショットから復元しました'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1A237E),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('復元に失敗しました: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  /// バックアップ取り込み: ファイル選択 → 確認 → 全データ上書き。
  Future<void> _importBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      String? jsonString;
      // 優先順: path > bytes
      // Android の file_picker は path が確実に取れる場合が多い。
      // File.readAsString(encoding: utf8) は明示的に UTF-8 でデコードする。
      // Web では path が null になり bytes 経路に入る。
      if (!kIsWeb && picked.path != null) {
        jsonString = await File(picked.path!).readAsString(encoding: utf8);
      } else if (picked.bytes != null) {
        jsonString = utf8.decode(picked.bytes!);
      }
      if (jsonString == null || jsonString.isEmpty) {
        throw const BackupException('ファイルを読み込めませんでした');
      }
      if (!context.mounted) return;
      await _performBackupImport(context, jsonString, picked.name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('取り込みに失敗しました: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  /// 取り込みドロップゾーン（Web専用）。
  /// JSON ファイルをこのエリアにドラッグ&ドロップで取り込む。
  /// `H:\マイドライブ\ツール開発\FutaFinance\` をエクスプローラで
  /// 開いておけば、そのままドラッグして即時取り込める。
  bool _isDragHover = false;

  Widget _importDropZone(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: DropTarget(
        onDragEntered: (_) => setState(() => _isDragHover = true),
        onDragExited: (_) => setState(() => _isDragHover = false),
        onDragDone: (details) async {
          setState(() => _isDragHover = false);
          if (details.files.isEmpty) return;
          final f = details.files.first;
          // 拡張子チェック（.json のみ受け付ける）
          if (!f.name.toLowerCase().endsWith('.json')) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('JSONファイルをドロップしてください'),
                backgroundColor: Color(0xFFDC2626),
              ),
            );
            return;
          }
          try {
            final bytes = await f.readAsBytes();
            String jsonString = utf8.decode(bytes);
            if (jsonString.startsWith('﻿')) {
              jsonString = jsonString.substring(1);
            }
            if (!context.mounted) return;
            await _performBackupImport(context, jsonString, f.name);
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('取り込みに失敗しました: $e'),
                backgroundColor: const Color(0xFFDC2626),
              ),
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: _isDragHover
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isDragHover
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFD1D5DB),
              width: _isDragHover ? 2 : 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.file_download_outlined,
                size: 28,
                color: _isDragHover
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDragHover
                          ? 'ここでドロップ'
                          : 'JSONをここにドラッグ&ドロップで取り込み',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isDragHover
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      r'推奨フォルダ: H:\マイドライブ\ツール開発\FutaFinance\',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 取り込みの共通フロー（確認ダイアログ → importAll → 成功通知）。
  /// ファイル選択経由と D&D 経由の両方からここを呼ぶ。
  Future<void> _performBackupImport(
      BuildContext context, String jsonString, String fileName) async {
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('バックアップから復元'),
          content: Text(
            '「$fileName」を取り込みます。\n'
            '現在のデータは上書きされ、元に戻せません。\n\n'
            '※ 念のため事前に「バックアップを書き出す」で現状を保存しておくと安全です。',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('取り込む'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      final importResult =
          await BackupRepository.instance.importAll(jsonString);

      if (!context.mounted) return;
      await _showImportSuccessDialog(context, importResult);

      // ダイアログを閉じた後にも SnackBar で「完了」を明示。
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(kIsWeb
                    ? 'バックアップから復元しました（自動でリロードします）'
                    : 'バックアップから復元しました'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Web は自動でリロードして取り込み内容を完全反映する。
      // モバイルは Firestore Stream で各画面が自動更新されるため何もしない。
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 1500));
        reloadApp();
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('取り込みに失敗しました: $e'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1),
        ),
      );

  /// 「未使用のウォレット/口座/クレカを隠す」スイッチ。
  /// 各ウォレット/カード編集で「未使用」フラグを立てた項目だけが対象。
  /// UiPreferences の変更を listen している各画面が自動でフィルタを再適用する。
  Widget _hideInactiveTile() {
    return AnimatedBuilder(
      animation: UiPreferences.instance,
      builder: (context, _) {
        final value = UiPreferences.instance.hideInactive;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: SwitchListTile(
            value: value,
            onChanged: (v) => UiPreferences.instance.setHideInactive(v),
            secondary: const Icon(Icons.visibility_off,
                color: Color(0xFF1A237E)),
            title: const Text('未使用のウォレット/カードを隠す',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
            subtitle: const Text(
                '各ウォレット/クレカ編集で「未使用」フラグを立てた項目を非表示にする',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          ),
        );
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final iconColor =
        danger ? const Color(0xFFDC2626) : const Color(0xFF1A237E);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827))),
        subtitle: Text(subtitle,
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        trailing: const Icon(Icons.chevron_right,
            color: Color(0xFF9CA3AF), size: 20),
        onTap: onTap,
      ),
    );
  }
}
