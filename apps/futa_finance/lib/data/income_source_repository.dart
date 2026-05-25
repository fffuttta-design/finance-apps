import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 収入マスタのローカル永続化。シングルトン。
class IncomeSourceRepository {
  IncomeSourceRepository._();
  static final IncomeSourceRepository instance = IncomeSourceRepository._();

  static const _key = 'futa.income_sources';

  Future<IncomeSourceConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return IncomeSourceConfig.empty();
    try {
      return IncomeSourceConfig.fromJsonString(raw);
    } catch (_) {
      return IncomeSourceConfig.empty();
    }
  }

  Future<void> save(IncomeSourceConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}
