import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 設定（カテゴリ・支払方法）のローカル永続化レイヤ。
///
/// Dフェーズで Firestore + Auth に置き換える前提。
class SettingsRepository {
  static const _kCategories = 'futa.categories';
  static const _kPayments = 'futa.payments';

  Future<CategoryConfig> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCategories);
    if (raw == null) return CategoryConfig.futaDefaults();
    try {
      return CategoryConfig.fromJsonString(raw);
    } catch (_) {
      return CategoryConfig.futaDefaults();
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
