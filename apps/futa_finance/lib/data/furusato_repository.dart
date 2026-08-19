import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'furusato.dart';

/// ふるさと納税管理のリポジトリ抽象。
///
/// 保持するのは「枠の上限」と「取引に対する付加情報（自治体・証明書・
/// ワンストップ）」だけ。寄付そのものは既存の Transaction が正本で、
/// ここには金額も日付も持たない（数字がズレる余地を作らないため）。
abstract class FurusatoRepository {
  static FurusatoRepository instance = LocalFurusatoRepository();

  static void useLocal() {
    instance = LocalFurusatoRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreFurusatoRepository(uid: uid);
  }

  Future<FurusatoConfig> load();
  Future<void> save(FurusatoConfig config);
}

class LocalFurusatoRepository implements FurusatoRepository {
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.furusato';

  final Map<String, FurusatoConfig> _cache = {};

  @override
  Future<FurusatoConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    FurusatoConfig result;
    if (raw == null) {
      result = FurusatoConfig.empty();
    } else {
      try {
        result = FurusatoConfig.fromJsonString(raw);
      } catch (_) {
        result = FurusatoConfig.empty();
      }
    }
    _cache[prefix] = result;
    return result;
  }

  @override
  Future<void> save(FurusatoConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}

class FirestoreFurusatoRepository implements FurusatoRepository {
  FirestoreFurusatoRepository({required this.uid});
  final String uid;

  final Map<String, FurusatoConfig> _cache = {};

  String get _modeKey => AppModeManager.instance.current == AppMode.business
      ? 'business'
      : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance.doc('users/$uid/config/${modeKey}_furusato');

  @override
  Future<FurusatoConfig> load() async {
    final mk = _modeKey;
    final cached = _cache[mk];
    if (cached != null) {
      unawaited(_fetch(mk));
      return cached;
    }
    return _fetch(mk);
  }

  Future<FurusatoConfig> _fetch(String modeKey) async {
    final snap = await _docFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    FurusatoConfig result;
    if (raw == null) {
      result = FurusatoConfig.empty();
    } else {
      try {
        result = FurusatoConfig.fromJsonString(raw);
      } catch (_) {
        result = FurusatoConfig.empty();
      }
    }
    _cache[modeKey] = result;
    return result;
  }

  @override
  Future<void> save(FurusatoConfig config) async {
    final mk = _modeKey;
    _cache[mk] = config;
    await _docFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
