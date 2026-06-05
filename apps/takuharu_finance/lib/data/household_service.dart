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

  /// 二人専用アプリなので、世帯コードの入力（参加）はせず、
  /// 許可された全員を「固定の1つの共有世帯」に自動で入れる。
  /// これで何もしなくても必ず同じ家計簿を共有できる。
  static const String sharedHid = 'TAKUHARU';

  String? _householdId;
  String? get householdId => _householdId;

  /// {uid: 表示名}
  Map<String, String> memberNames = {};

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _households =>
      _db.collection('households');

  /// ログイン後に呼ぶ。許可された全員を固定の共有世帯に入れる。
  /// 以前バラバラの世帯に入れていた場合は、そのデータを共有世帯へ移行する。
  Future<void> ensureHousehold(User user) async {
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'わたし';
    final uref = _users.doc(user.uid);
    final prev = (await uref.get()).data()?['householdId'];

    // 固定の共有世帯へ自分を登録（コード入力不要・必ず同期）。
    await _households.doc(sharedHid).set({
      'members': FieldValue.arrayUnion([user.uid]),
      'memberNames': {user.uid: name},
    }, SetOptions(merge: true));
    await uref.set(
        {'householdId': sharedHid, 'name': name}, SetOptions(merge: true));
    _householdId = sharedHid;

    // 旧方式で個別世帯に入っていたデータを共有世帯へ移行（best-effort）。
    if (prev is String && prev.isNotEmpty && prev != sharedHid) {
      try {
        await _migrateData(prev, sharedHid);
      } catch (_) {}
    }
    await _loadMembers();
    notifyListeners();
  }

  /// 旧世帯 [fromHid] の取引・プランを共有世帯 [toHid] へコピー（同IDは上書きで重複防止）。
  Future<void> _migrateData(String fromHid, String toHid) async {
    for (final sub in const ['transactions', 'plan_items']) {
      final src = await _households.doc(fromHid).collection(sub).get();
      if (src.docs.isEmpty) continue;
      final batch = _db.batch();
      for (final d in src.docs) {
        batch.set(
          _households.doc(toHid).collection(sub).doc(d.id),
          d.data(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
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

  void reset() {
    _householdId = null;
    memberNames = {};
    notifyListeners();
  }
}
