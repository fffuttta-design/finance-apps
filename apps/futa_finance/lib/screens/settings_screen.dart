import 'package:flutter/material.dart';

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/update_checker.dart';
import '../data/update_installer.dart';
import '../mock/mock_data.dart';
import 'account_editor_screen.dart';
import 'card_editor_screen.dart';
import 'category_editor_screen.dart';
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
              title: '銀行口座',
              subtitle: '取引で選択する銀行の登録',
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
              title: 'サブスク一覧',
              subtitle: '月払い/年払いの継続課金を一覧管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionListScreen()),
              ),
            ),
            const SizedBox(height: 8),

            _section('アプリ情報'),
            _versionCard(),

            const SizedBox(height: 8),
            _section('データ管理'),
            _tile(
              icon: Icons.upload_file,
              title: 'サンプルデータを投入（全置換）',
              subtitle: '既存の取引を全削除し、5月実データ30件 + 住信SBI口座をセット',
              onTap: () => _seedSampleData(context),
            ),
            _tile(
              icon: Icons.delete_sweep,
              title: '全取引を削除',
              subtitle: '入力済みの取引を全て消去（戻せません）',
              onTap: () => _clearAll(context),
              danger: true,
            ),
          ],
        ),
      ),
    );
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
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF1A237E)),
              const SizedBox(width: 8),
              const Text('現在のバージョン',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5)),
              const Spacer(),
              Text(
                r?.currentFull ?? '取得中…',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    fontFamily: 'monospace'),
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
            '住信SBI口座（月初¥10,652,701）が未登録なら同時に追加します。\n'
            'よろしいですか？'),
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
        content: const Text('登録されている全ての取引を削除します。\nこの操作は取り消せません。'),
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
    await TransactionRepository.instance.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全取引を削除しました')),
    );
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
