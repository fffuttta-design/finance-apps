import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 場所マスタ（購入場所の登録リスト）。事業/個人で共通（モード非依存）。
///
/// 表記ゆれ（ファミマ／ファミリーマート…）を防ぐため、支出の「場所」は
/// ここから選ぶ。新規に入力した場所は保存時に自動で追加され、以後は候補に出る。
/// Firestore `users/{uid}/config/store_master` の `json`（未ログイン時は prefs）。
class StoreMasterRepository {
  StoreMasterRepository._();
  static final StoreMasterRepository instance = StoreMasterRepository._();

  static const _prefsKey = 'futa.store_master';

  List<String> _cache = const [];
  bool _loaded = false;
  bool get isLoaded => _loaded;
  List<String> get cached => _cache;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.doc('users/$uid/config/store_master');
  }

  Future<List<String>> load() async {
    final doc = _doc;
    if (doc != null) {
      try {
        final snap = await doc.get();
        _cache = _parse(snap.data()?['json'] as String?);
      } catch (_) {
        _cache = const [];
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      _cache = _parse(prefs.getString(_prefsKey));
    }
    _loaded = true;
    return _cache;
  }

  Future<void> save(List<String> names) async {
    // 空白除去＋重複除去（順序は保持）。
    final seen = <String>{};
    final clean = <String>[];
    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) clean.add(t);
    }
    _cache = clean;
    final json = jsonEncode(clean);
    final doc = _doc;
    if (doc != null) {
      await doc.set({'json': json, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json);
    }
  }

  /// 1件追加（重複は無視）。未ロードなら先にロードしてから足す。
  Future<void> add(String name) async {
    final t = name.trim();
    if (t.isEmpty) return;
    if (!_loaded) await load();
    if (_cache.contains(t)) return;
    await save([..._cache, t]);
  }

  /// 複数の場所名をまとめて取り込む（履歴からの初期取り込み等）。重複は無視。
  Future<void> addAll(Iterable<String> names) async {
    if (!_loaded) await load();
    final set = {..._cache};
    var changed = false;
    final next = [..._cache];
    for (final n in names) {
      final t = n.trim();
      if (t.isNotEmpty && set.add(t)) {
        next.add(t);
        changed = true;
      }
    }
    if (changed) await save(next);
  }

  List<String> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
