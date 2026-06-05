import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/update_checker.dart';
import '../data/update_flow.dart';

/// 起動時のアプリ内アップデート（APK配信）チェック＋通知ダイアログを提供する mixin。
/// MainShell の State に `with StartupUpdateMixin` して initState から
/// [scheduleStartupUpdateCheck] を呼ぶ。Web では何もしない。
mixin StartupUpdateMixin<T extends StatefulWidget> on State<T> {
  DateTime? _lastCheck;

  void scheduleStartupUpdateCheck() {
    if (kIsWeb) return;
    Future.delayed(const Duration(seconds: 2), runUpdateCheck);
  }

  /// 更新チェック（起動時・アプリ復帰時で共用）。
  /// 短時間の連打は 90 秒スロットルでスキップ。
  Future<void> runUpdateCheck() async {
    if (kIsWeb || !mounted) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!).inSeconds < 90) {
      return;
    }
    _lastCheck = now;

    final r = await UpdateChecker.instance.check();
    if (!mounted || !r.hasUpdate || r.fetchFailed) return;

    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getString(UpdateFlow.skipVersionKey);
    if (skipped != null && skipped == r.latestFull) return;
    if (!mounted) return;

    await UpdateFlow.handleAvailable(context, r, allowSkip: true);
  }
}
