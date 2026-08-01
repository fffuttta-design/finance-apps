import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'update_checker.dart';
import 'update_installer.dart';

/// アプリ内アップデート（APK配信）の共通フロー（FutaFinanceと同方式）。
class UpdateFlow {
  UpdateFlow._();

  static const skipVersionKey = 'takuharu.update.skip_version';
  static const _accent = AppColors.pinkDark;

  /// 設定画面から呼ぶ手動チェック。
  static Future<void> checkManually(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Text('最新バージョンを確認中...'),
          ],
        ),
      ),
    );

    final r = await UpdateChecker.instance.check();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (r.fetchFailed) {
      _snack(context, '最新バージョンを確認できませんでした（通信エラー）');
      return;
    }
    if (!r.hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Text('最新です'),
            ],
          ),
          content: Text('現在 ${r.currentFull} が最新バージョンです。'),
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

    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update, color: _accent),
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
              const SizedBox(height: 8),
              const Text(
                'ページを再読み込みすると最新になります。',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
            ],
          ),
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

    await handleAvailable(context, r, allowSkip: false);
  }

  static Future<void> handleAvailable(
    BuildContext context,
    UpdateCheckResult r, {
    required bool allowSkip,
  }) async {
    final url = r.downloadUrl;
    if (url != null) {
      final cached = await UpdateInstaller.instance.getCachedApk(url);
      if (!context.mounted) return;
      if (cached != null) {
        await _showResumeInstallDialog(context, r, cached,
            allowSkip: allowSkip);
        return;
      }
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: _accent),
            SizedBox(width: 8),
            Text('新しいバージョン ♡'),
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
                      fontSize: 12, color: AppColors.textSub)),
            ],
          ],
        ),
        actions: [
          if (allowSkip)
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(skipVersionKey, r.latestFull);
    } else if (action == 'update') {
      if (!context.mounted) return;
      await _downloadAndInstall(context, r);
    }
  }

  static Future<void> _showResumeInstallDialog(
    BuildContext context,
    UpdateCheckResult r,
    File cachedApk, {
    required bool allowSkip,
  }) async {
    final sizeMb = (await cachedApk.length()) / 1024 / 1024;
    if (!context.mounted) return;

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
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ],
        ),
        actions: [
          if (allowSkip)
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
      await prefs.setString(skipVersionKey, r.latestFull);
      try {
        await cachedApk.delete();
      } catch (_) {}
    } else if (action == 'install') {
      if (!context.mounted) return;
      final perm = await UpdateInstaller.instance.ensureInstallPermission();
      if (!context.mounted) return;
      if (perm != InstallPermissionStatus.granted) {
        _snack(context, 'インストール権限が必要です');
        return;
      }
      await UpdateInstaller.instance.installApk(cachedApk.path);
    }
  }

  static Future<void> _downloadAndInstall(
      BuildContext context, UpdateCheckResult r) async {
    final url = r.downloadUrl;
    if (url == null) {
      _snack(context, 'ダウンロードURLが取得できませんでした');
      return;
    }

    final permStatus =
        await UpdateInstaller.instance.ensureInstallPermission();
    if (!context.mounted) return;
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

    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('ダウンロード中...'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (ctx, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value),
                  const SizedBox(height: 12),
                  Text(
                    '${(value * 100).toStringAsFixed(0)} %',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      final file = await UpdateInstaller.instance.downloadApk(
        url,
        onProgress: (p) => progress.value = p,
      );
      progress.dispose();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await UpdateInstaller.instance.installApk(file.path);
    } catch (e) {
      progress.dispose();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack(context, 'ダウンロードに失敗しました: $e');
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
