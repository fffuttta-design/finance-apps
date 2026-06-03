import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 世帯（二人で共有する家計データの単位）の管理。
///
/// データ構造:
///   users/{uid}            { householdId, name }
///   households/{code}      { members:[uid], memberNames:{uid:name}, createdBy, createdAt }
///   households/{code}/transactions/{id}
///
/// ログイン後に [ensureHousehold] を呼ぶと、世帯が無ければ自動作成し、
/// 6文字の「世帯コード」を発行する。パートナーは [joinHousehold] でそのコードを
/// 入力して同じ世帯に参加できる。
class HouseholdService extends ChangeNotifier {
  HouseholdService._();
  static final HouseholdService instance = HouseholdService._();

  final _db = FirebaseFirestore.instance;

  String? _householdId;
  String? get householdId => _householdId;

  /// {uid: 表示名}
  Map<String, String> memberNames = {};

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _households =>
      _db.collection('households');

  /// ログイン後に呼ぶ。世帯が無ければ自動作成、あれば読み込み。
  Future<void> ensureHousehold(User user) async {
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'わたし';
    final uref = _users.doc(user.uid);
    final usnap = await uref.get();
    final existing = usnap.data()?['householdId'];

    if (existing is String && existing.isNotEmpty) {
      _householdId = existing;
      // 念のためメンバー登録・名前を更新。
      await _households.doc(existing).set({
        'members': FieldValue.arrayUnion([user.uid]),
        'memberNames': {user.uid: name},
      }, SetOptions(merge: true));
    } else {
      final code = await _generateUniqueCode();
      _householdId = code;
      await _households.doc(code).set({
        'members': [user.uid],
        'memberNames': {user.uid: name},
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await uref
          .set({'householdId': code, 'name': name}, SetOptions(merge: true));
    }
    await _loadMembers();
    notifyListeners();
  }

  /// パートナーの世帯コードを入力して参加する。
  Future<void> joinHousehold(String codeRaw, User user) async {
    final code = codeRaw.trim().toUpperCase();
    if (code.isEmpty) throw '世帯コードを入力してください';
    final snap = await _households.doc(code).get();
    if (!snap.exists) throw 'その世帯コードは見つかりませんでした';
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'パートナー';
    await _households.doc(code).set({
      'members': FieldValue.arrayUnion([user.uid]),
      'memberNames': {user.uid: name},
    }, SetOptions(merge: true));
    await _users
        .doc(user.uid)
        .set({'householdId': code, 'name': name}, SetOptions(merge: true));
    _householdId = code;
    await _loadMembers();
    notifyListeners();
  }

  Future<void> _loadMembers() async {
    final hid = _householdId;
    if (hid == null) return;
    final snap = await _households.doc(hid).get();
    final mn = snap.data()?['memberNames'];
    if (mn is Map) {
      memberNames = mn.map((k, v) => MapEntry('$k', '$v'));
    }
  }

  Future<String> _generateUniqueCode() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = _randomCode();
      final snap = await _households.doc(code).get();
      if (!snap.exists) return code;
    }
    // 衝突が続く場合の保険（ほぼ起こらない）。
    return _randomCode();
  }

  String _randomCode() {
    // 紛らわしい文字(0/O,1/I)は除外。
    const chars = 'ABCDEFGHJKLMNPRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void reset() {
    _householdId = null;
    memberNames = {};
    notifyListeners();
  }
}
