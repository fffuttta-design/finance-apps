import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'pl_plan.dart';

/// PL 年間計画（予実）の永続化。開発中ラボ用。Local のみ・モード別。
/// 事業年度（期首年）ごとにキーを分ける。
class PlPlanRepository extends ChangeNotifier {
  PlPlanRepository._();
  static final PlPlanRepository instance = PlPlanRepository._();

  String _key(int fyStartYear) =>
      'futa.${AppModeManager.instance.current.keyPrefix}.pl_plan.$fyStartYear';

  // (prefix + fyStartYear) → Config のキャッシュ。
  final Map<String, PlPlanConfig> _cache = {};

  Future<PlPlanConfig> load(int fyStartYear) async {
    final ck = '${AppModeManager.instance.current.keyPrefix}.$fyStartYear';
    final cached = _cache[ck];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(fyStartYear));
    PlPlanConfig result;
    if (raw == null) {
      result = PlPlanConfig.empty(fyStartYear);
    } else {
      try {
        result = PlPlanConfig.fromJsonString(raw);
      } catch (_) {
        result = PlPlanConfig.empty(fyStartYear);
      }
    }
    _cache[ck] = result;
    return result;
  }

  Future<void> save(PlPlanConfig config) async {
    final ck =
        '${AppModeManager.instance.current.keyPrefix}.${config.fyStartYear}';
    _cache[ck] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(config.fyStartYear), config.toJsonString());
    notifyListeners();
  }
}
