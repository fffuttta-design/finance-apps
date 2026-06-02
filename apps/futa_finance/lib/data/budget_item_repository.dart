import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'budget_item.dart';

/// 予算項目（BudgetItem）の永続化。
/// 開発中ラボ（事業モード）専用なので Local のみ。
/// 事業/個人モードでキーを分ける（個人モードでも将来使えるように）。
class BudgetItemRepository extends ChangeNotifier {
  BudgetItemRepository._();
  static final BudgetItemRepository instance = BudgetItemRepository._();

  String _key() => 'futa.${AppModeManager.instance.current.keyPrefix}.budget_items';

  // モード別の解析済みキャッシュ。切替時の再解析を避ける。
  final Map<String, BudgetItemsConfig> _cache = {};

  Future<BudgetItemsConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    BudgetItemsConfig result;
    if (raw == null) {
      result = BudgetItemsConfig.empty();
    } else {
      try {
        result = BudgetItemsConfig.fromJsonString(raw);
      } catch (_) {
        result = BudgetItemsConfig.empty();
      }
    }
    _cache[prefix] = result;
    return result;
  }

  Future<void> save(BudgetItemsConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(), config.toJsonString());
    notifyListeners();
  }

  Future<void> upsert(BudgetItem item) async {
    final cfg = await load();
    final list = [...cfg.items];
    final idx = list.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.add(item);
    }
    await save(BudgetItemsConfig(items: list));
  }

  Future<void> remove(String id) async {
    final cfg = await load();
    final list = cfg.items.where((i) => i.id != id).toList();
    await save(BudgetItemsConfig(items: list));
  }
}
