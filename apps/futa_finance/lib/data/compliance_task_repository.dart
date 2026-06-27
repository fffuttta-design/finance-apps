import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'compliance_task.dart';

/// 手続き・届出スケジュール（ComplianceTask）の永続化。
///
/// [BudgetItemRepository] と同じく、シングルトン（ChangeNotifier）のまま
/// 保存先をログイン状態で切替える（ログイン中=Firestore全端末同期 / 未ログイン=ローカル）。
class ComplianceTaskRepository extends ChangeNotifier {
  ComplianceTaskRepository._();
  static final ComplianceTaskRepository instance =
      ComplianceTaskRepository._();

  final Map<String, ComplianceTasksConfig> _cache = {};
  String? _uid;
  bool _fs = false;

  String get _prefix => AppModeManager.instance.current.keyPrefix;
  String get _localKey => 'futa.$_prefix.compliance_tasks';
  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$_uid/config/${modeKey}_compliance_tasks');

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

  Future<ComplianceTasksConfig> load() async {
    final cached = _cache[_prefix];
    if (cached != null) {
      if (_fs && _uid != null) unawaited(_fetchFs(_modeKey, _prefix));
      return cached;
    }
    if (_fs && _uid != null) return _fetchFs(_modeKey, _prefix);
    return _loadLocal();
  }

  Future<ComplianceTasksConfig> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final result = _parse(prefs.getString(_localKey));
    _cache[_prefix] = result;
    return result;
  }

  Future<ComplianceTasksConfig> _fetchFs(
      String modeKey, String cacheKey) async {
    final snap = await _docFor(modeKey).get();
    var result = _parse(snap.data()?['json'] as String?);
    if (result.tasks.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final local = _parse(prefs.getString('futa.$cacheKey.compliance_tasks'));
      if (local.tasks.isNotEmpty) {
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

  ComplianceTasksConfig _parse(String? raw) {
    if (raw == null) return ComplianceTasksConfig.empty();
    try {
      return ComplianceTasksConfig.fromJsonString(raw);
    } catch (_) {
      return ComplianceTasksConfig.empty();
    }
  }

  Future<void> save(ComplianceTasksConfig config) async {
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

  Future<void> upsert(ComplianceTask task) async {
    final cfg = await load();
    final list = [...cfg.tasks];
    final idx = list.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      list[idx] = task;
    } else {
      list.add(task);
    }
    await save(ComplianceTasksConfig(tasks: list));
  }

  Future<void> remove(String id) async {
    final cfg = await load();
    final list = cfg.tasks.where((t) => t.id != id).toList();
    await save(ComplianceTasksConfig(tasks: list));
  }
}
