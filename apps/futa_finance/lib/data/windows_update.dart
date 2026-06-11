import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_checker.dart';
import 'update_flow.dart';

/// Windows デスクトップ版のアプリ内アップデート。
///
/// Android の APK 自動更新（[UpdateFlow]）に相当する Windows 版。
/// リモートの futa-windows-version.json を見て新バージョンがあれば、
/// zip をダウンロード → 終了を待って差し替えるバッチを起動 → 自身を終了する
/// （ポータブル自己置換方式）。
class WindowsUpdateService {
  WindowsUpdateService._();
  static final WindowsUpdateService instance = WindowsUpdateService._();

  /// Windows 用 version.json（zip の downloadUrl を持つ）。
  static const String versionUrl =
      'https://raw.githubusercontent.com/fffuttta-design/finance-apps/main/release/futa-windows-version.json';

  static const _accent = Color(0xFFEA580C);

  /// このプラットフォームが対象か（Windows ネイティブのみ）。
  static bool get isTarget => !kIsWeb && Platform.isWindows;

  final _dio = Dio();

  Future<UpdateCheckResult> check() =>
      UpdateChecker.instance.check(overrideVersionUrl: versionUrl);

  // ───────── 起動時チェック（スキップ記憶あり）─────────
  Future<void> checkAtStartup(BuildContext context) async {
    final r = await check();
    if (!context.mounted) return;
    if (!r.hasUpdate || r.fetchFailed) return;
    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getString(UpdateFlow.skipVersionKey);
    if (skipped != null && skipped == r.latestFull) return;
    if (!context.mounted) return;
    await _promptAvailable(context, r, allowSkip: true);
  }

  // ───────── 手動チェック（設定画面）─────────
  Future<void> checkManually(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
          SizedBox(width: 16),
          Text('最新バージョンを確認中…'),
        ]),
      ),
    );
    final r = await check();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // スピナーを閉じる
    if (!context.mounted) return;

    if (r.fetchFailed) {
      _info(context, '確認できませんでした',
          'ネットワークに繋がっているか確認して、もう一度お試しください。');
      return;
    }
    if (!r.hasUpdate) {
      _info(context, '最新です', '現在 ${r.currentFull} で、最新版です。');
      return;
    }
    await _promptAvailable(context, r, allowSkip: false);
  }

  // ───────── 更新ありダイアログ ─────────
  Future<void> _promptAvailable(
    BuildContext context,
    UpdateCheckResult r, {
    required bool allowSkip,
  }) async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいバージョンがあります',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.currentFull}  →  ${r.latestFull}'),
            if ((r.releaseNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(r.releaseNotes!.trim(),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280))),
            ],
            const SizedBox(height: 10),
            const Text(
              '更新するとアプリが一度閉じ、自動で最新版が立ち上がります。',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          if (allowSkip)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('skip'),
              child: const Text('このバージョンは飛ばす',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('later'),
            child: const Text('あとで'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.of(ctx).pop('update'),
            child: const Text('今すぐ更新'),
          ),
        ],
      ),
    );
    if (action == 'skip') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(UpdateFlow.skipVersionKey, r.latestFull);
      return;
    }
    if (action != 'update') return;
    if (!context.mounted) return;
    final url = r.downloadUrl;
    if (url == null || url.isEmpty) {
      _info(context, '更新できません', 'ダウンロード先が見つかりませんでした。');
      return;
    }
    await _downloadAndApply(context, url, r.latestFull);
  }

  // ───────── ダウンロード → 差し替えバッチ起動 → 自身終了 ─────────
  Future<void> _downloadAndApply(
      BuildContext context, String url, String label) async {
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('更新をダウンロード中…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: v > 0 ? v : null, color: _accent),
              const SizedBox(height: 10),
              Text(v > 0 ? '${(v * 100).toStringAsFixed(0)} %' : '準備中…'),
            ],
          ),
        ),
      ),
    );

    try {
      final tmp = await getTemporaryDirectory();
      final zipPath =
          '${tmp.path}\\futa_finance_update_${DateTime.now().millisecondsSinceEpoch}.zip';
      await _dio.download(
        url,
        zipPath,
        onReceiveProgress: (rec, total) {
          if (total > 0) progress.value = rec / total;
        },
      );

      // インストール先＝今動いている exe のあるフォルダ。
      final installDir = File(Platform.resolvedExecutable).parent.path;
      final extractDir =
          '${tmp.path}\\futa_finance_update_${DateTime.now().millisecondsSinceEpoch}_x';
      final batPath =
          '${tmp.path}\\futa_finance_update_${DateTime.now().millisecondsSinceEpoch}.bat';

      final bat = _updaterBat(
        currentPid: pid,
        zipPath: zipPath,
        extractDir: extractDir,
        installDir: installDir,
      );
      await File(batPath).writeAsString(bat);

      // 別プロセスでバッチを起動（本体終了を待って差し替え→再起動）。
      await Process.start(
        'cmd.exe',
        ['/c', batPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      if (context.mounted) Navigator.of(context).pop();
      // 自身を終了。バッチが差し替え後に再起動する。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(0);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _info(context, '更新に失敗しました', '$e');
      }
    }
  }

  /// 差し替えバッチ。
  /// 1) 本体プロセス(PID)の終了を待つ
  /// 2) zip を展開
  /// 3) robocopy /MIR で install へ反映（VERSION.txt は除外）
  /// 4) 再起動して後始末
  String _updaterBat({
    required int currentPid,
    required String zipPath,
    required String extractDir,
    required String installDir,
  }) {
    return '''@echo off
chcp 65001 >nul
:waitloop
tasklist /FI "PID eq $currentPid" 2>nul | find "$currentPid" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto waitloop
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$extractDir' -Force"
robocopy "$extractDir" "$installDir" /MIR /XF VERSION.txt /NFL /NDL /NJH /NJS /NP >nul
start "" "$installDir\\futa_finance.exe"
del "$zipPath" >nul 2>&1
rmdir /S /Q "$extractDir" >nul 2>&1
(goto) 2>nul & del "%~f0"
''';
  }

  void _info(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
