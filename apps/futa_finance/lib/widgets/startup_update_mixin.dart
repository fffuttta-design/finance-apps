import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/update_checker.dart';
import '../data/update_flow.dart';
import '../data/windows_update.dart';

/// 起動時のアプリ内アップデート（APK配信）チェック＋通知ダイアログを提供する mixin。
///
/// v1 (RootScreen) と v2 (V2Root) の両方の State に `with StartupUpdateMixin` して使う。
/// initState から [scheduleStartupUpdateCheck] を呼べば、起動少し後に
/// リモート version.json を確認し、新バージョンがあれば更新ダイアログを出す。
///
/// 実際の更新ダイアログ／DL／インストールは [UpdateFlow] に一本化してあり、
/// 設定画面からの手動チェック（[UpdateFlow.checkManually]）と同じ処理を使う。
///
/// Web では APK 更新は無意味なので何もしない。
mixin StartupUpdateMixin<T extends StatefulWidget> on State<T> {
  DateTime? _lastUpdateCheck;

  /// 起動時に呼ぶ。起動直後の初期化と競合しないよう少し遅延させてチェックする。
  void scheduleStartupUpdateCheck() {
    // Web ではアプリ内アップデート確認（APK配信）は無意味なのでスキップ。
    if (kIsWeb) return;
    Future.delayed(const Duration(seconds: 2), () {
      _lastUpdateCheck = DateTime.now();
      _checkForUpdateAtStartup();
    });
  }

  /// アプリ復帰時などに呼ぶ。連打を避けるため60秒スロットル。
  Future<void> runUpdateCheckThrottled() async {
    if (kIsWeb) return;
    final now = DateTime.now();
    if (_lastUpdateCheck != null &&
        now.difference(_lastUpdateCheck!).inSeconds < 60) {
      return;
    }
    _lastUpdateCheck = now;
    await _checkForUpdateAtStartup();
  }

  Future<void> _checkForUpdateAtStartup() async {
    // Windows ネイティブは zip 自己置換方式の専用フローへ。
    if (WindowsUpdateService.isTarget) {
      if (mounted) await WindowsUpdateService.instance.checkAtStartup(context);
      return;
    }
    final r = await UpdateChecker.instance.check();
    if (!mounted) return;
    if (!r.hasUpdate) return;
    if (r.fetchFailed) return;

    // 「このバージョンはスキップ」したことがあれば通知しない
    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getString(UpdateFlow.skipVersionKey);
    if (skipped != null && skipped == r.latestFull) return;
    if (!mounted) return;

    // 起動時は「このバージョンは飛ばす」も選べる（allowSkip: true）。
    await UpdateFlow.handleAvailable(context, r, allowSkip: true);
  }
}
