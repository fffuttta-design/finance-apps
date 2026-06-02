import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 月末締めチェックリスト設定のリポジトリ抽象。
abstract class ChecklistRepository {
  static ChecklistRepository instance = LocalChecklistRepository();

  static void useLocal() {
    instance = LocalChecklistRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreChecklistRepository(uid: uid);
  }

  Future<ChecklistConfig> load();
  Future<void> save(ChecklistConfig config);
}

class LocalChecklistRepository implements ChecklistRepository {
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.checklist';

  // モード別の解析済みキャッシュ。切替時の再解析を避ける。
  final Map<String, ChecklistConfig> _cache = {};

  ChecklistConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? ChecklistConfig.businessDefaults()
        : ChecklistConfig.personalDefaults();
  }

  @override
  Future<ChecklistConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final result = raw == null
        ? _defaultsForCurrentMode()
        : (() {
            try {
              return ChecklistConfig.fromJsonString(raw);
            } catch (_) {
              return _defaultsForCurrentMode();
            }
          })();
    _cache[prefix] = result;
    return result;
  }

  @override
  Future<void> save(ChecklistConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}

class FirestoreChecklistRepository implements ChecklistRepository {
  FirestoreChecklistRepository({required this.uid});
  final String uid;

  /// モード別メモリキャッシュ。モード切替直後の即表示用（裏で最新取得）。
  final Map<String, ChecklistConfig> _cache = {};

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  ChecklistConfig _defaultsFor(String modeKey) {
    return modeKey == 'business'
        ? ChecklistConfig.businessDefaults()
        : ChecklistConfig.personalDefaults();
  }

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_checklist');

  @override
  Future<ChecklistConfig> load() async {
    final mk = _modeKey;
    final cached = _cache[mk];
    if (cached != null) {
      unawaited(_fetch(mk));
      return cached;
    }
    return _fetch(mk);
  }

  Future<ChecklistConfig> _fetch(String modeKey) async {
    final snap = await _docFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    ChecklistConfig result;
    if (raw == null) {
      result = _defaultsFor(modeKey);
    } else {
      try {
        result = ChecklistConfig.fromJsonString(raw);
      } catch (_) {
        result = _defaultsFor(modeKey);
      }
    }
    _cache[modeKey] = result;
    return result;
  }

  @override
  Future<void> save(ChecklistConfig config) async {
    final mk = _modeKey;
    _cache[mk] = config;
    await _docFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
