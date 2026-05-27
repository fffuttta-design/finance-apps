import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 月末締めの状態（チェック済み項目・締め日時）の永続化。
class MonthClosingRepository {
  MonthClosingRepository._();
  static final MonthClosingRepository instance = MonthClosingRepository._();

  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.month_closing';

  Future<MonthClosingConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return MonthClosingConfig.empty();
    try {
      return MonthClosingConfig.fromJsonString(raw);
    } catch (_) {
      return MonthClosingConfig.empty();
    }
  }

  Future<void> save(MonthClosingConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }

  Future<void> upsert(MonthClosing closing) async {
    final cfg = await load();
    await save(cfg.upsert(closing));
  }
}
