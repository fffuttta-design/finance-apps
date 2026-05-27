import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 収入マスタのリポジトリ抽象。
abstract class IncomeSourceRepository {
  static IncomeSourceRepository instance = LocalIncomeSourceRepository();

  static void useLocal() {
    instance = LocalIncomeSourceRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreIncomeSourceRepository(uid: uid);
  }

  Future<IncomeSourceConfig> load();
  Future<void> save(IncomeSourceConfig config);
}

class LocalIncomeSourceRepository implements IncomeSourceRepository {
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.income_sources';

  @override
  Future<IncomeSourceConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return IncomeSourceConfig.empty();
    try {
      return IncomeSourceConfig.fromJsonString(raw);
    } catch (_) {
      return IncomeSourceConfig.empty();
    }
  }

  @override
  Future<void> save(IncomeSourceConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}

class FirestoreIncomeSourceRepository implements IncomeSourceRepository {
  FirestoreIncomeSourceRepository({required this.uid});
  final String uid;

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore
      .instance
      .doc('users/$uid/config/${_modeKey}_income_sources');

  @override
  Future<IncomeSourceConfig> load() async {
    final snap = await _doc.get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return IncomeSourceConfig.empty();
    try {
      return IncomeSourceConfig.fromJsonString(raw);
    } catch (_) {
      return IncomeSourceConfig.empty();
    }
  }

  @override
  Future<void> save(IncomeSourceConfig config) async {
    await _doc.set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
