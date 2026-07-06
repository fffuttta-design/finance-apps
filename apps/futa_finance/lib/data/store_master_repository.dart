import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 場所マスタ（購入場所の登録リスト）。事業/個人で共通（モード非依存）。
///
/// 表記ゆれ（ファミマ／ファミリーマート…）を防ぐため、支出の「場所」は
/// ここから選ぶ。新規に入力した場所は保存時に自動で追加され、以後は候補に出る。
///
/// セクション（設定画面用の分類）も持つ。今は「場所マスタ画面での整理用」だが、
/// 将来は大カテゴリへ昇格させる余地を残す。保存は
/// Firestore `users/{uid}/config/store_master` の `json`（未ログイン時は prefs）。
/// json は後方互換のため「配列（旧・名前のみ）」と「オブジェクト（新）」の両対応。
class StoreMasterRepository {
  StoreMasterRepository._();
  static final StoreMasterRepository instance = StoreMasterRepository._();

  static const _prefsKey = 'futa.store_master';

  List<String> _cache = const []; // 場所名（表示順）
  List<String> _sections = const []; // セクション名（表示順）
  Map<String, String> _assign = {}; // 場所名 → セクション名
  bool _loaded = false;
  bool get isLoaded => _loaded;
  List<String> get cached => _cache;

  /// セクション名（表示順）。
  List<String> get sections => List.unmodifiable(_sections);

  /// 指定の場所が属するセクション名（未割り当ては null）。
  String? sectionOf(String store) => _assign[store.trim()];

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
        _parseInto(snap.data()?['json'] as String?);
      } catch (_) {
        _cache = const [];
        _sections = const [];
        _assign = {};
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      _parseInto(prefs.getString(_prefsKey));
    }
    _loaded = true;
    return _cache;
  }

  /// 場所名リストを保存（順序を保持）。セクション/割り当ては維持する。
  Future<void> save(List<String> names) async {
    final seen = <String>{};
    final clean = <String>[];
    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) clean.add(t);
    }
    _cache = clean;
    // 存在しなくなった場所の割り当ては掃除する。
    _assign.removeWhere((k, v) => !seen.contains(k));
    await _persist();
  }

  /// セクション一覧（順序）を保存。存在しないセクションへの割り当ては掃除する。
  Future<void> saveSections(List<String> sections) async {
    if (!_loaded) await load();
    final seen = <String>{};
    final clean = <String>[];
    for (final s in sections) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) clean.add(t);
    }
    _sections = clean;
    _assign.removeWhere((k, v) => !seen.contains(v));
    await _persist();
  }

  /// セクション名を変更（割り当ても追従して付け替える）。
  Future<void> renameSection(String oldName, String newName) async {
    if (!_loaded) await load();
    final o = oldName.trim();
    final n = newName.trim();
    if (o.isEmpty || n.isEmpty || o == n) return;
    _sections = _sections.map((s) => s == o ? n : s).toList();
    _assign = {
      for (final e in _assign.entries) e.key: (e.value == o ? n : e.value),
    };
    await _persist();
  }

  /// 1つの場所のセクションを設定（null で未割り当てに戻す）。
  Future<void> assignSection(String store, String? section) async {
    if (!_loaded) await load();
    final s = store.trim();
    if (s.isEmpty) return;
    final sec = section?.trim();
    if (sec == null || sec.isEmpty) {
      _assign.remove(s);
    } else {
      if (!_sections.contains(sec)) _sections = [..._sections, sec];
      _assign[s] = sec;
    }
    await _persist();
  }

  Future<void> _persist() async {
    final json = jsonEncode({
      'stores': _cache,
      'sections': _sections,
      'assign': _assign,
    });
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

  /// 旧形式（配列）と新形式（オブジェクト）の両対応でパースして内部へ反映。
  void _parseInto(String? raw) {
    _cache = const [];
    _sections = const [];
    _assign = {};
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        // 旧形式：名前の配列のみ。
        _cache = decoded
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
        return;
      }
      if (decoded is Map<String, dynamic>) {
        _cache = ((decoded['stores'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
        _sections = ((decoded['sections'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
        final a = (decoded['assign'] as Map?) ?? const {};
        _assign = {
          for (final e in a.entries)
            e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {
      // 壊れていたら空で始める。
    }
  }
}
