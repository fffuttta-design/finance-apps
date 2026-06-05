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

  /// 複数取引をまとめて追加（レシートの品目ごと記録など）。
  Future<void> addAll(
      String hid, List<core.Transaction> txns, String uid) async {
    final batch = _db.batch();
    final coll = _coll(hid);
    for (final t in txns) {
      batch.set(coll.doc(t.id), {
        ...t.toJson(),
        'recordedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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

  /// 指定の receiptId 群のうち、既に存在するものを返す（固定費の二重記録防止）。
  Future<Set<String>> existingReceiptIds(
      String hid, List<String> ids) async {
    final result = <String>{};
    final coll = _coll(hid);
    for (var i = 0; i < ids.length; i += 30) {
      final end = (i + 30 < ids.length) ? i + 30 : ids.length;
      final chunk = ids.sublist(i, end);
      if (chunk.isEmpty) continue;
      final snap = await coll.where('receiptId', whereIn: chunk).get();
      for (final d in snap.docs) {
        final rid = d.data()['receiptId'];
        if (rid is String) result.add(rid);
      }
    }
    return result;
  }
}
