import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/update_checker.dart';
import '../data/update_installer.dart';

/// 起動時のアプリ内アップデート（APK配信）チェック＋通知ダイアログを提供する mixin。
///
/// v1 (RootScreen) と v2 (V2Root) の両方の State に `with StartupUpdateMixin` して使う。
/// initState から [scheduleStartupUpdateCheck] を呼べば、起動少し後に
/// リモート version.json を確認し、新バージョンがあれば更新ダイアログを出す。
///
/// Web では APK 更新は無意味なので何もしない。
mixin StartupUpdateMixin<T extends StatefulWidget> on State<T> {
  // ユーザーが「スキップ」したバージョンを覚えるキー。
  // ここに保存されたバージョンが最新と一致したらダイアログを出さない。
  static const _skipVersionKey = 'futa.update.skip_version';

  /// 起動時に呼ぶ。起動直後の初期化と競合しないよう少し遅延させてチェックする。
  void scheduleStartupUpdateCheck() {
    // Web ではアプリ内アップデート確認（APK配信）は無意味なのでスキップ。
    if (kIsWeb) return;
    Future.delayed(const Duration(seconds: 2), _checkForUpdateAtStartup);
  }

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
}
