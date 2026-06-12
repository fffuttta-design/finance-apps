import 'package:cloud_firestore/cloud_firestore.dart';

import 'comment_repository.dart' show TxComment;

/// プランニング項目ごとのコメント（households/{hid}/plan_items/{planId}/comments）。
/// 取引チャットと同じ [TxComment] モデルを再利用する。
class PlanCommentRepository {
  PlanCommentRepository._();
  static final PlanCommentRepository instance = PlanCommentRepository._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _planDoc(String hid, String planId) =>
      _db.doc('households/$hid/plan_items/$planId');

  CollectionReference<Map<String, dynamic>> _coll(String hid, String planId) =>
      _planDoc(hid, planId).collection('comments');

  Stream<List<TxComment>> watch(String hid, String planId) {
    return _coll(hid, planId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) {
      final list = <TxComment>[];
      for (final d in snap.docs) {
        final m = d.data();
        list.add(TxComment(
          id: d.id,
          uid: (m['uid'] ?? '') as String,
          text: (m['text'] ?? '') as String,
          imageUrl: m['imageUrl'] as String?,
          createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
        ));
      }
      return list;
    });
  }

  Future<void> add(String hid, String planId, String uid, String text,
      {String? imageUrl}) async {
    final t = text.trim();
    if (t.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final batch = _db.batch();
    batch.set(_coll(hid, planId).doc(id), {
      'uid': uid,
      'text': t,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // 親項目にコメント数を持たせて、一覧でバッジ表示できるようにする。
    batch.set(_planDoc(hid, planId),
        {'commentCount': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();
  }
}
