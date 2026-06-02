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

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  ChecklistConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? ChecklistConfig.businessDefaults()
        : ChecklistConfig.personalDefaults();
  }

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore
      .instance
      .doc('users/$uid/config/${_modeKey}_checklist');

  @override
  Future<ChecklistConfig> load() async {
    final snap = await _doc.get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return _defaultsForCurrentMode();
    try {
      return ChecklistConfig.fromJsonString(raw);
    } catch (_) {
      return _defaultsForCurrentMode();
    }
  }

  @override
  Future<void> save(ChecklistConfig config) async {
    await _doc.set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
