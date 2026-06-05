import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 変換ルール（この語 → この語 に置き換える）。
class ReplacementRule {
  final String from;
  final String to;
  const ReplacementRule(this.from, this.to);

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  factory ReplacementRule.fromJson(Map<String, dynamic> j) =>
      ReplacementRule((j['from'] ?? '').toString(), (j['to'] ?? '').toString());
}

/// 変換マスタ（読み取り時の表記ゆれを置き換える辞書）。
///
/// レシートOCRやAmazon取り込みで出る読みにくい語を、登録名に正規化する。
/// 事業/個人で共通（モード非依存）。Firestore `users/{uid}/config/replacements`
/// の `json` フィールド（未ログイン時は SharedPreferences）に保存。
class ReplacementRepository {
  ReplacementRepository._();
  static final ReplacementRepository instance = ReplacementRepository._();

  static const _prefsKey = 'futa.replacements';

  List<ReplacementRule> _cache = const [];
  bool get isLoaded => _loaded;
  bool _loaded = false;

  List<ReplacementRule> get cached => _cache;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.doc('users/$uid/config/replacements');
  }

  Future<List<ReplacementRule>> load() async {
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

  Future<void> save(List<ReplacementRule> rules) async {
    // 空の from は無効として除外。
    final clean = rules.where((r) => r.from.trim().isNotEmpty).toList();
    _cache = clean;
    final json = jsonEncode(clean.map((r) => r.toJson()).toList());
    final doc = _doc;
    if (doc != null) {
      await doc.set(
          {'json': json, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json);
    }
  }

  List<ReplacementRule> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              ReplacementRule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// キャッシュ済みルールでテキストを置き換える（同期・前から順に適用）。
  /// 事前に [load] を呼んでキャッシュを温めておくこと（未ロード時は素通り）。
  String apply(String text) {
    if (_cache.isEmpty || text.isEmpty) return text;
    var out = text;
    for (final r in _cache) {
      if (r.from.isNotEmpty) out = out.replaceAll(r.from, r.to);
    }
    return out;
  }
}
