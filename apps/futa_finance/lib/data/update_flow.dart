import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_checker.dart';
import 'update_installer.dart';

/// アプリ内アップデート（APK 配信）の共通フロー。
///
/// - 起動時の自動チェック（[StartupUpdateMixin]）
/// - 設定画面からの手動チェック（[checkManually]）
///
/// の両方が同じ「更新ダイアログ → DL → インストール」を使えるよう、
/// ダイアログ／ダウンロード処理をここに一本化する。
class UpdateFlow {
  UpdateFlow._();

  /// ユーザーが「このバージョンは飛ばす」を選んだバージョンを覚えるキー。
  /// 起動時の自動チェックでのみ参照する（手動チェックでは無視）。
  static const skipVersionKey = 'futa.update.skip_version';

  static const _accent = Color(0xFFEA580C);

  // ───────────────────────────────────────────
  // 手動チェック（設定画面の「最新バージョンを確認」ボタン）
  // ───────────────────────────────────────────

  /// 設定画面から呼ぶ手動チェック。
  /// 自動チェックと違い、「最新です」「確認できませんでした」も明示的に伝える。
  static Future<void> checkManually(BuildContext context) async {
    // 確認中のスピナー
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
    // スピナーを閉じる
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

    // 新版あり → 共通フロー（手動なので skip ボタンは出さない）
    await handleAvailable(context, r, allowSkip: false);
  }

  // ───────────────────────────────────────────
  // 新版あり時の共通処理（起動時・手動 共用）
  // ───────────────────────────────────────────

  /// 「新しいバージョンがある」と分かった後の共通処理。
  /// DL 済みなら「インストール再開」、無ければ更新ダイアログ → DL → インストール。
  ///
  /// [allowSkip] が true のときだけ「このバージョンは飛ばす」を表示する
  /// （起動時の自動チェック用。手動チェックでは false）。
  static Future<void> handleAvailable(
    BuildContext context,
    UpdateCheckResult r, {
    required bool allowSkip,
  }) async {
    // 既に DL 済みなら「インストール再開」専用ダイアログ
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
    // 'later' or null は何もしない
  }

  /// DL 済み APK が見つかった時の「インストール再開」専用ダイアログ。
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
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
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
      // スキップしたバージョンの DL ファイルも削除（容量解放）
      try {
        await cachedApk.delete();
      } catch (_) {}
    } else if (action == 'install') {
      if (!context.mounted) return;
      final perm =
          await UpdateInstaller.instance.ensureInstallPermission();
      if (!context.mounted) return;
      if (perm != InstallPermissionStatus.granted) {
        _snack(context, 'インストール権限が必要です');
        return;
      }
      await UpdateInstaller.instance.installApk(cachedApk.path);
    }
    // 'later' or null は何もしない
  }

  /// ダウンロード進捗ダイアログを開き、APK を DL → インストールフローまで実行。
  static Future<void> _downloadAndInstall(
      BuildContext context, UpdateCheckResult r) async {
    final url = r.downloadUrl;
    if (url == null) {
      _snack(context, 'ダウンロードURLが取得できませんでした');
      return;
    }

    // インストール許可のチェック（Android: 不明なソースからのインストール）
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

    // 進捗ダイアログ（ValueNotifier で進捗値だけ再描画）
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
      // 進捗ダイアログを閉じる
      Navigator.of(context, rootNavigator: true).pop();

      // OS のインストーラを起動
      await UpdateInstaller.instance.installApk(file.path);
      // この後 OS のインストール画面が出る。アプリが置換されると再起動。
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
