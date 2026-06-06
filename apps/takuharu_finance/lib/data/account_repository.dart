import 'package:cloud_firestore/cloud_firestore.dart';

import 'account.dart';

/// 口座・クレカ（世帯共有）。households/{hid}/accounts。
class AccountRepository {
  AccountRepository._();
  static final AccountRepository instance = AccountRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _coll(String hid) =>
      _db.collection('households/$hid/accounts');

  Stream<List<Account>> watch(String hid) {
    return _coll(hid).snapshots().map((snap) {
      final list = <Account>[];
      for (final d in snap.docs) {
        try {
          list.add(Account.fromJson(Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      return list;
    });
  }

  Future<List<Account>> loadAll(String hid) async {
    final snap = await _coll(hid).get();
    final list = <Account>[];
    for (final d in snap.docs) {
      try {
        list.add(Account.fromJson(Map<String, dynamic>.from(d.data())));
      } catch (_) {}
    }
    return list;
  }

  Future<void> save(String hid, Account a) async {
    await _coll(hid).doc(a.id).set({
      ...a.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String hid, String id) async {
    await _coll(hid).doc(id).delete();
  }
}
