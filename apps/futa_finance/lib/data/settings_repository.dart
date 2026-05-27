import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 設定（カテゴリ・支払方法）のローカル永続化レイヤ。
///
/// Dフェーズで Firestore + Auth に置き換える前提。
/// AppMode (事業/個人) ごとにキーが分かれる。
class SettingsRepository {
  String get _kCategories =>
      'futa.${AppModeManager.instance.current.keyPrefix}.categories';
  String get _kPayments =>
      'futa.${AppModeManager.instance.current.keyPrefix}.payments';

  /// モード別のデフォルトカテゴリを返す。
  CategoryConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? CategoryConfig.businessDefaults()
        : CategoryConfig.personalDefaults();
  }

  Future<CategoryConfig> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCategories);
    if (raw == null) return _defaultsForCurrentMode();
    try {
      return CategoryConfig.fromJsonString(raw);
    } catch (_) {
      return _defaultsForCurrentMode();
    }
  }

  Future<void> saveCategories(CategoryConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCategories, config.toJsonString());
  }

  Future<PaymentMethodsConfig> loadPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPayments);
    if (raw == null) return PaymentMethodsConfig.empty();
    try {
      return PaymentMethodsConfig.fromJsonString(raw);
    } catch (_) {
      return PaymentMethodsConfig.empty();
    }
  }

  Future<void> savePayments(PaymentMethodsConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPayments, config.toJsonString());
  }
}
