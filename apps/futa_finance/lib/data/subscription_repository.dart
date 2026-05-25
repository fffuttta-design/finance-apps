import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// サブスクリプション設定のローカル永続化。シングルトン。
class SubscriptionRepository {
  SubscriptionRepository._();
  static final SubscriptionRepository instance = SubscriptionRepository._();

  static const _key = 'futa.subscriptions';

  Future<SubscriptionConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return SubscriptionConfig.empty();
    try {
      return SubscriptionConfig.fromJsonString(raw);
    } catch (_) {
      return SubscriptionConfig.empty();
    }
  }

  Future<void> save(SubscriptionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}
