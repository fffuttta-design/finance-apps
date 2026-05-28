import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI 表示まわりのユーザー設定。SharedPreferences で永続化し、
/// 変更を ChangeNotifier で各画面に伝える。
///
/// 既存の SettingsRepository は「カテゴリ・支払方法」用の Firestore/Local
/// 切替が絡む層なので、表示フラグ等の軽量設定はこちらに分離する。
class UiPreferences extends ChangeNotifier {
  UiPreferences._();
  static final UiPreferences instance = UiPreferences._();

  static const _kHideZeroBalance = 'futa.ui.hide_zero_balance';

  bool _hideZeroBalance = false;
  bool _loaded = false;

  /// 残高 / 累積額が 0 のウォレット・口座・クレカを表示系画面で隠すか。
  /// デフォルトは false（=表示）。
  bool get hideZeroBalance => _hideZeroBalance;
  bool get loaded => _loaded;

  /// 起動時に一度呼ぶ。多重呼び出しは無害（最初の値を保持）。
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _hideZeroBalance = prefs.getBool(_kHideZeroBalance) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setHideZeroBalance(bool v) async {
    if (_hideZeroBalance == v) return;
    _hideZeroBalance = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideZeroBalance, v);
    notifyListeners();
  }
}
