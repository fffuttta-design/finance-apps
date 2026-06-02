import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'liability.dart';

/// 借入金・負債（Liability）の永続化。
/// 開発中ラボ（簡易BS）用。事業/個人モードでキーを分ける。Local のみ。
class LiabilityRepository extends ChangeNotifier {
  LiabilityRepository._();
  static final LiabilityRepository instance = LiabilityRepository._();

  String _key() =>
      'futa.${AppModeManager.instance.current.keyPrefix}.liabilities';

  // モード別の解析済みキャッシュ。切替時の再解析を避ける。
  final Map<String, LiabilitiesConfig> _cache = {};

  Future<LiabilitiesConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    LiabilitiesConfig result;
    if (raw == null) {
      result = LiabilitiesConfig.empty();
    } else {
      try {
        result = LiabilitiesConfig.fromJsonString(raw);
      } catch (_) {
        result = LiabilitiesConfig.empty();
      }
    }
    _cache[prefix] = result;
    return result;
  }

  Future<void> save(LiabilitiesConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(), config.toJsonString());
    notifyListeners();
  }

  Future<void> upsert(Liability item) async {
    final cfg = await load();
    final list = [...cfg.items];
    final idx = list.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.add(item);
    }
    await save(LiabilitiesConfig(items: list));
  }

  Future<void> remove(String id) async {
    final cfg = await load();
    final list = cfg.items.where((i) => i.id != id).toList();
    await save(LiabilitiesConfig(items: list));
  }
}
