import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'income_year.dart';

/// 年収の記録（[IncomeYear]）の永続化。
///
/// 保存先の切替は [BudgetItemRepository] と同じ作法：
/// - ログイン中: Firestore `users/{uid}/config/{mode}_income_history`
/// - 未ログイン: SharedPreferences（端末ローカル）
///
/// 事業/個人モードでデータを分ける（実際に使うのは個人モード）。
class IncomeHistoryRepository extends ChangeNotifier {
  IncomeHistoryRepository._();
  static final IncomeHistoryRepository instance = IncomeHistoryRepository._();

  final Map<String, IncomeHistoryConfig> _cache = {};

  String? _uid;
  bool _fs = false;

  String get _prefix => AppModeManager.instance.current.keyPrefix;
  String get _localKey => 'futa.$_prefix.income_history';
  String get _modeKey => AppModeManager.instance.current == AppMode.business
      ? 'business'
      : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$_uid/config/${modeKey}_income_history');

  void useFirestore(String uid) {
    _uid = uid;
    _fs = true;
    _cache.clear();
    notifyListeners();
  }

  void useLocal() {
    _uid = null;
    _fs = false;
    _cache.clear();
    notifyListeners();
  }

  Future<IncomeHistoryConfig> load() async {
    final cached = _cache[_prefix];
    if (cached != null) {
      if (_fs && _uid != null) unawaited(_fetchFs(_modeKey, _prefix));
      return cached;
    }
    if (_fs && _uid != null) return _fetchFs(_modeKey, _prefix);
    return _loadLocal();
  }

  Future<IncomeHistoryConfig> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final result = _parse(prefs.getString(_localKey));
    _cache[_prefix] = result;
    return result;
  }

  Future<IncomeHistoryConfig> _fetchFs(String modeKey, String cacheKey) async {
    final snap = await _docFor(modeKey).get();
    var result = _parse(snap.data()?['json'] as String?);
    // 初回同期：リモートが空でローカルに既存があれば引き上げる。
    if (result.years.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final local = _parse(prefs.getString('futa.$cacheKey.income_history'));
      if (local.years.isNotEmpty) {
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

  IncomeHistoryConfig _parse(String? raw) {
    if (raw == null) return IncomeHistoryConfig.empty();
    try {
      return IncomeHistoryConfig.fromJsonString(raw);
    } catch (_) {
      return IncomeHistoryConfig.empty();
    }
  }

  Future<void> save(IncomeHistoryConfig config) async {
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

  Future<void> upsert(IncomeYear item) async {
    final cfg = await load();
    final list = [...cfg.years];
    final idx = list.indexWhere((y) => y.id == item.id);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.add(item);
    }
    await save(IncomeHistoryConfig(years: list));
  }

  Future<void> remove(String id) async {
    final cfg = await load();
    final list = cfg.years.where((y) => y.id != id).toList();
    await save(IncomeHistoryConfig(years: list));
  }
}
