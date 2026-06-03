import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart' as core;

/// 世帯の収支取引（Firestore）。households/{hid}/transactions。
class TxRepository {
  TxRepository._();
  static final TxRepository instance = TxRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _coll(String hid) =>
      _db.collection('households/$hid/transactions');

  /// 取引のリアルタイム購読（日付の新しい順）。
  Stream<List<core.Transaction>> watch(String hid) {
    return _coll(hid)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) {
      final list = <core.Transaction>[];
      for (final d in snap.docs) {
        try {
          list.add(core.Transaction.fromJson(Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      return list;
    });
  }

  Future<void> add(String hid, core.Transaction t, String uid) async {
    await _coll(hid).doc(t.id).set({
      ...t.toJson(),
      'recordedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update(String hid, core.Transaction t, String uid) async {
    await _coll(hid).doc(t.id).set({
      ...t.toJson(),
      'recordedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String hid, String id) async {
    await _coll(hid).doc(id).delete();
  }
}
