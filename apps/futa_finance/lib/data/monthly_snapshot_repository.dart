import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 月初残高スナップショットのローカル永続化。シングルトン。
/// AppMode (事業/個人) ごとにキーが分かれる。
class MonthlySnapshotRepository {
  MonthlySnapshotRepository._();
  static final MonthlySnapshotRepository instance =
      MonthlySnapshotRepository._();

  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.monthly_snapshots';

  Future<MonthlySnapshotConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return MonthlySnapshotConfig.empty();
    try {
      return MonthlySnapshotConfig.fromJsonString(raw);
    } catch (_) {
      return MonthlySnapshotConfig.empty();
    }
  }

  Future<void> save(MonthlySnapshotConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }

  /// 指定月のスナップショットを更新（既存なら上書き）。
  Future<void> upsert(MonthlySnapshot snapshot) async {
    final cfg = await load();
    await save(cfg.upsert(snapshot));
  }
}
