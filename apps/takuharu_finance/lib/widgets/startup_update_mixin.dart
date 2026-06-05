import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/update_checker.dart';
import '../data/update_flow.dart';

/// 起動時のアプリ内アップデート（APK配信）チェック＋通知ダイアログを提供する mixin。
/// MainShell の State に `with StartupUpdateMixin` して initState から
/// [scheduleStartupUpdateCheck] を呼ぶ。Web では何もしない。
mixin StartupUpdateMixin<T extends StatefulWidget> on State<T> {
  void scheduleStartupUpdateCheck() {
    if (kIsWeb) return;
    Future.delayed(const Duration(seconds: 2), _checkForUpdateAtStartup);
  }

  Future<void> _checkForUpdateAtStartup() async {
    final r = await UpdateChecker.instance.check();
    if (!mounted) return;
    if (!r.hasUpdate) return;
    if (r.fetchFailed) return;

    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getString(UpdateFlow.skipVersionKey);
    if (skipped != null && skipped == r.latestFull) return;
    if (!mounted) return;

    await UpdateFlow.handleAvailable(context, r, allowSkip: true);
  }
}
