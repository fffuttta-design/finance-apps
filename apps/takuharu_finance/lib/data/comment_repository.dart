import 'package:cloud_firestore/cloud_firestore.dart';

/// 取引チャットの1メッセージ。
class TxComment {
  final String id;
  final String uid;
  final String text;
  final DateTime? createdAt;
  const TxComment(
      {required this.id,
      required this.uid,
      required this.text,
      this.createdAt});
}

/// 取引ごとのチャット（households/{hid}/transactions/{txId}/comments）。
class CommentRepository {
  CommentRepository._();
  static final CommentRepository instance = CommentRepository._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _txDoc(String hid, String txId) =>
      _db.doc('households/$hid/transactions/$txId');

  CollectionReference<Map<String, dynamic>> _coll(String hid, String txId) =>
      _txDoc(hid, txId).collection('comments');

  Stream<List<TxComment>> watch(String hid, String txId) {
    return _coll(hid, txId)
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
          createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
        ));
      }
      return list;
    });
  }

  Future<void> add(String hid, String txId, String uid, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final batch = _db.batch();
    batch.set(_coll(hid, txId).doc(id), {
      'uid': uid,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // 親取引にコメント数を持たせて、一覧でバッジ表示できるようにする。
    batch.set(_txDoc(hid, txId),
        {'commentCount': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();
  }
}
