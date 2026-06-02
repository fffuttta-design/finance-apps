import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 月末締めの状態（チェック済み項目・締め日時）のリポジトリ抽象。
abstract class MonthClosingRepository {
  static MonthClosingRepository instance = LocalMonthClosingRepository();

  static void useLocal() {
    instance = LocalMonthClosingRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreMonthClosingRepository(uid: uid);
  }

  Future<MonthClosingConfig> load();
  Future<void> save(MonthClosingConfig config);
  Future<void> upsert(MonthClosing closing);
}

class LocalMonthClosingRepository implements MonthClosingRepository {
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.month_closing';

  // モード別の解析済みキャッシュ。切替時の再解析を避ける。
  final Map<String, MonthClosingConfig> _cache = {};

  @override
  Future<MonthClosingConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    MonthClosingConfig result;
    if (raw == null) {
      result = MonthClosingConfig.empty();
    } else {
      try {
        result = MonthClosingConfig.fromJsonString(raw);
      } catch (_) {
        result = MonthClosingConfig.empty();
      }
    }
    _cache[prefix] = result;
    return result;
  }

  @override
  Future<void> save(MonthClosingConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }

  @override
  Future<void> upsert(MonthClosing closing) async {
    final cfg = await load();
    await save(cfg.upsert(closing));
  }
}

class FirestoreMonthClosingRepository implements MonthClosingRepository {
  FirestoreMonthClosingRepository({required this.uid});
  final String uid;

  /// モード別メモリキャッシュ。モード切替直後の即表示用（裏で最新取得）。
  final Map<String, MonthClosingConfig> _cache = {};

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_month_closing');

  @override
  Future<MonthClosingConfig> load() async {
    final mk = _modeKey;
    final cached = _cache[mk];
    if (cached != null) {
      unawaited(_fetch(mk));
      return cached;
    }
    return _fetch(mk);
  }

  Future<MonthClosingConfig> _fetch(String modeKey) async {
    final snap = await _docFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    MonthClosingConfig result;
    if (raw == null) {
      result = MonthClosingConfig.empty();
    } else {
      try {
        result = MonthClosingConfig.fromJsonString(raw);
      } catch (_) {
        result = MonthClosingConfig.empty();
      }
    }
    _cache[modeKey] = result;
    return result;
  }

  @override
  Future<void> save(MonthClosingConfig config) async {
    final mk = _modeKey;
    _cache[mk] = config;
    await _docFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> upsert(MonthClosing closing) async {
    final cfg = await load();
    await save(cfg.upsert(closing));
  }
}
