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

  Future<BudgetItemsConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    if (raw == null) return BudgetItemsConfig.empty();
    try {
      return BudgetItemsConfig.fromJsonString(raw);
    } catch (_) {
      return BudgetItemsConfig.empty();
    }
  }

  Future<void> save(BudgetItemsConfig config) async {
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
