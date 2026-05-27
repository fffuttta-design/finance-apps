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

  @override
  Future<MonthlySnapshotConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return MonthlySnapshotConfig.empty();
    try {
      return MonthlySnapshotConfig.fromJsonString(raw);
    } catch (_) {
      return MonthlySnapshotConfig.empty();
    }
  }

  @override
  Future<void> save(MonthlySnapshotConfig config) async {
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

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore
      .instance
      .doc('users/$uid/config/${_modeKey}_monthly_snapshots');

  @override
  Future<MonthlySnapshotConfig> load() async {
    final snap = await _doc.get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return MonthlySnapshotConfig.empty();
    try {
      return MonthlySnapshotConfig.fromJsonString(raw);
    } catch (_) {
      return MonthlySnapshotConfig.empty();
    }
  }

  @override
  Future<void> save(MonthlySnapshotConfig config) async {
    await _doc.set({
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
