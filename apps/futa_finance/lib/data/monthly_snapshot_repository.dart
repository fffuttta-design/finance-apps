import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 月初残高スナップショットのリポジトリ抽象。
abstract class MonthlySnapshotRepository {
  static MonthlySnapshotRepository instance =
      LocalMonthlySnapshotRepository();

  static void useLocal() {
    instance = LocalMonthlySnapshotRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreMonthlySnapshotRepository(uid: uid);
  }

  Future<MonthlySnapshotConfig> load();
  Future<void> save(MonthlySnapshotConfig config);
  Future<void> upsert(MonthlySnapshot snapshot);
}

class LocalMonthlySnapshotRepository
    implements MonthlySnapshotRepository {
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.monthly_snapshots';

  // モード別の解析済みキャッシュ。切替時の再解析を避ける。
  final Map<String, MonthlySnapshotConfig> _cache = {};

  @override
  Future<MonthlySnapshotConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    MonthlySnapshotConfig result;
    if (raw == null) {
      result = MonthlySnapshotConfig.empty();
    } else {
      try {
        result = MonthlySnapshotConfig.fromJsonString(raw);
      } catch (_) {
        result = MonthlySnapshotConfig.empty();
      }
    }
    _cache[prefix] = result;
    return result;
  }

  @override
  Future<void> save(MonthlySnapshotConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }

  @override
  Future<void> upsert(MonthlySnapshot snapshot) async {
    final cfg = await load();
    await save(cfg.upsert(snapshot));
  }
}

class FirestoreMonthlySnapshotRepository
    implements MonthlySnapshotRepository {
  FirestoreMonthlySnapshotRepository({required this.uid});
  final String uid;

  /// モード別メモリキャッシュ。モード切替直後の即表示用（裏で最新取得）。
  final Map<String, MonthlySnapshotConfig> _cache = {};

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_monthly_snapshots');

  @override
  Future<MonthlySnapshotConfig> load() async {
    final mk = _modeKey;
    final cached = _cache[mk];
    if (cached != null) {
      unawaited(_fetch(mk));
      return cached;
    }
    return _fetch(mk);
  }

  Future<MonthlySnapshotConfig> _fetch(String modeKey) async {
    final snap = await _docFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    MonthlySnapshotConfig result;
    if (raw == null) {
      result = MonthlySnapshotConfig.empty();
    } else {
      try {
        result = MonthlySnapshotConfig.fromJsonString(raw);
      } catch (_) {
        result = MonthlySnapshotConfig.empty();
      }
    }
    _cache[modeKey] = result;
    return result;
  }

  @override
  Future<void> save(MonthlySnapshotConfig config) async {
    final mk = _modeKey;
    _cache[mk] = config;
    await _docFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> upsert(MonthlySnapshot snapshot) async {
    final cfg = await load();
    await save(cfg.upsert(snapshot));
  }
}
