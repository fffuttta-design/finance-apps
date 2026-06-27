import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'budget_item.dart';

/// 予算項目（BudgetItem＝税金・保険など）の永続化。
///
/// シングルトン（ChangeNotifier）のまま、保存先をログイン状態で切替える：
/// - ログイン中: Firestore `users/{uid}/config/{mode}_budget_items`（全端末で同期）
/// - 未ログイン: SharedPreferences（端末ローカル）
///
/// 事業/個人モードでデータを分ける。`RepositoryProvider` が認証状態の変化で
/// [useFirestore]/[useLocal] を呼び、キャッシュを捨てて読み直させる。
class BudgetItemRepository extends ChangeNotifier {
  BudgetItemRepository._();
  static final BudgetItemRepository instance = BudgetItemRepository._();

  // モード別の解析済みキャッシュ（キー＝モードprefix）。
  final Map<String, BudgetItemsConfig> _cache = {};

  // 認証バックエンド。null/false ならローカル。
  String? _uid;
  bool _fs = false;

  String get _prefix => AppModeManager.instance.current.keyPrefix;
  String get _localKey => 'futa.$_prefix.budget_items';
  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$_uid/config/${modeKey}_budget_items');

  /// ログイン：以後 Firestore に保存・同期する。
  void useFirestore(String uid) {
    _uid = uid;
    _fs = true;
    _cache.clear();
    notifyListeners();
  }

  /// ログアウト：以後ローカル保存に戻す。
  void useLocal() {
    _uid = null;
    _fs = false;
    _cache.clear();
    notifyListeners();
  }

  Future<BudgetItemsConfig> load() async {
    final cached = _cache[_prefix];
    if (cached != null) {
      // バックグラウンドで最新を取りに行く（Firestore時のみ意味あり）。
      if (_fs && _uid != null) unawaited(_fetchFs(_modeKey, _prefix));
      return cached;
    }
    if (_fs && _uid != null) return _fetchFs(_modeKey, _prefix);
    return _loadLocal();
  }

  Future<BudgetItemsConfig> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final result = _parse(prefs.getString(_localKey));
    _cache[_prefix] = result;
    return result;
  }

  Future<BudgetItemsConfig> _fetchFs(String modeKey, String cacheKey) async {
    final snap = await _docFor(modeKey).get();
    var result = _parse(snap.data()?['json'] as String?);
    // 初回同期：リモートが空でローカルに既存データがあれば引き上げる。
    if (result.items.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final local = _parse(prefs.getString('futa.$cacheKey.budget_items'));
      if (local.items.isNotEmpty) {
        result = local;
        await _docFor(modeKey).set({
          'json': result.toJsonString(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    _cache[cacheKey] = result;
    notifyListeners();
    return result;
  }

  BudgetItemsConfig _parse(String? raw) {
    if (raw == null) return BudgetItemsConfig.empty();
    try {
      return BudgetItemsConfig.fromJsonString(raw);
    } catch (_) {
      return BudgetItemsConfig.empty();
    }
  }

  Future<void> save(BudgetItemsConfig config) async {
    _cache[_prefix] = config;
    if (_fs && _uid != null) {
      await _docFor(_modeKey).set({
        'json': config.toJsonString(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localKey, config.toJsonString());
    }
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
