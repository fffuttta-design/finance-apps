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

  /// 新キー（v1.0.65〜）: 未使用フラグ ON のものを隠す
  static const _kHideInactive = 'futa.ui.hide_inactive';

  /// 旧キー（〜v1.0.64）: 残高 0 のものを隠す。
  /// 起動時に値があれば新キーへ引き継いで削除する。
  static const _kLegacyHideZero = 'futa.ui.hide_zero_balance';

  bool _hideInactive = false;
  bool _loaded = false;

  /// 「未使用」フラグの立っているウォレット・口座・クレカを表示系画面で隠すか。
  /// デフォルトは false（=表示）。
  bool get hideInactive => _hideInactive;
  bool get loaded => _loaded;

  /// 起動時に一度呼ぶ。多重呼び出しは無害（最初の値を保持）。
  /// 旧キー（hide_zero_balance）が残っている場合は新キーへマイグレーション。
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    // 新キー優先、無ければ旧キーをフォールバック + 移行
    if (prefs.containsKey(_kHideInactive)) {
      _hideInactive = prefs.getBool(_kHideInactive) ?? false;
    } else if (prefs.containsKey(_kLegacyHideZero)) {
      _hideInactive = prefs.getBool(_kLegacyHideZero) ?? false;
      await prefs.setBool(_kHideInactive, _hideInactive);
      await prefs.remove(_kLegacyHideZero);
    } else {
      _hideInactive = false;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setHideInactive(bool v) async {
    if (_hideInactive == v) return;
    _hideInactive = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideInactive, v);
    notifyListeners();
  }
}
