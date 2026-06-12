import 'package:cloud_firestore/cloud_firestore.dart';

import 'plan_item.dart';

/// 世帯のプランニング項目（Firestore）。households/{hid}/plan_items。
class PlanRepository {
  PlanRepository._();
  static final PlanRepository instance = PlanRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _coll(String hid) =>
      _db.collection('households/$hid/plan_items');

  /// リアルタイム購読（order昇順）。
  Stream<List<PlanItem>> watch(String hid) {
    return _coll(hid).orderBy('order').snapshots().map((snap) {
      final list = <PlanItem>[];
      for (final d in snap.docs) {
        try {
          list.add(PlanItem.fromJson(Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      return list;
    });
  }

  /// 1件取得（通知タップから詳細を開く用）。
  Future<PlanItem?> getById(String hid, String id) async {
    try {
      final d = await _coll(hid).doc(id).get();
      if (!d.exists || d.data() == null) return null;
      return PlanItem.fromJson(Map<String, dynamic>.from(d.data()!));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String hid, PlanItem item, String uid) async {
    await _coll(hid).doc(item.id).set({
      ...item.toJson(),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String hid, String id) async {
    await _coll(hid).doc(id).delete();
  }

  /// 並び替え後の order を一括更新。
  Future<void> reorder(String hid, List<PlanItem> ordered, String uid) async {
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.set(
        _coll(hid).doc(ordered[i].id),
        {'order': i, 'updatedBy': uid, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}
