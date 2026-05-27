import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 月末締めチェックリスト設定のローカル永続化。
/// モード(事業/個人)ごとにキーが分かれる。
class ChecklistRepository {
  ChecklistRepository._();
  static final ChecklistRepository instance = ChecklistRepository._();

  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.checklist';

  ChecklistConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? ChecklistConfig.businessDefaults()
        : ChecklistConfig.personalDefaults();
  }

  Future<ChecklistConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return _defaultsForCurrentMode();
    try {
      return ChecklistConfig.fromJsonString(raw);
    } catch (_) {
      return _defaultsForCurrentMode();
    }
  }

  Future<void> save(ChecklistConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}
