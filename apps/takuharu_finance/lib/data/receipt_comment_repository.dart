import 'package:cloud_firestore/cloud_firestore.dart';

import 'comment_repository.dart' show TxComment;

/// レシート単位のチャット（households/{hid}/receipts/{receiptId}/comments）。
///
/// レシート（同じ receiptId を持つ複数品目）に対して、コメントを **1本** に
/// まとめて持たせる。コメントは品目レコード（transactions）とは独立した場所に
/// 置くので、まとめ編集で品目を足し引きしても迷子にならない。
///
/// receipts/{receiptId} ドキュメント本体には commentCount（一覧の💬バッジ用）と
/// migratedFromItems（旧・品目別コメントを統合済みか）を持たせる。
class ReceiptCommentRepository {
  ReceiptCommentRepository._();
  static final ReceiptCommentRepository instance = ReceiptCommentRepository._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _receiptDoc(String hid, String rid) =>
      _db.doc('households/$hid/receipts/$rid');

  CollectionReference<Map<String, dynamic>> _coll(String hid, String rid) =>
      _receiptDoc(hid, rid).collection('comments');

  /// このレシートのチャットをリアルタイム購読（古い順）。
  Stream<List<TxComment>> watch(String hid, String rid) {
    return _coll(hid, rid)
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

  /// このレシートのコメント数（一覧の💬バッジ用）。
  Stream<int> watchCount(String hid, String rid) {
    return _receiptDoc(hid, rid)
        .snapshots()
        .map((d) => ((d.data()?['commentCount']) as num?)?.toInt() ?? 0);
  }

  /// レシートのチャットに1件投稿（テキスト or 画像）。
  Future<void> add(String hid, String rid, String uid, String text,
      {String? imageUrl}) async {
    final t = text.trim();
    if (t.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final batch = _db.batch();
    batch.set(_coll(hid, rid).doc(id), {
      'uid': uid,
      'text': t,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // レシート本体にコメント数を持たせて、一覧でバッジ表示できるようにする。
    batch.set(_receiptDoc(hid, rid),
        {'commentCount': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();
  }

  /// 旧「品目ごと」に付いていたコメントを、このレシートの1スレッドへ寄せて統合する。
  ///
  /// [memberTxIds] … このレシートの品目（transactions）の id 一覧。
  /// レシート詳細を開いたときに一度だけ実行し、二度目以降は
  /// receipts/{rid}.migratedFromItems=true を見てスキップする（冪等）。
  Future<void> migrateFromItems(
      String hid, String rid, List<String> memberTxIds) async {
    try {
      final rd = await _receiptDoc(hid, rid).get();
      if (rd.data()?['migratedFromItems'] == true) return; // 統合済み

      // 各品目にぶら下がっている旧コメントを集める。
      final moved = <Map<String, dynamic>>[];
      final sources = <DocumentReference<Map<String, dynamic>>>[];
      for (final txId in memberTxIds) {
        final snap = await _db
            .collection('households/$hid/transactions/$txId/comments')
            .orderBy('createdAt', descending: false)
            .get();
        for (final d in snap.docs) {
          moved.add(d.data());
          sources.add(d.reference);
        }
      }

      final batch = _db.batch();
      // レシート側へコピー（createdAt/uid/text/imageUrl を保持）。
      var seq = 0;
      for (final m in moved) {
        final newId = '${DateTime.now().microsecondsSinceEpoch}-${seq++}';
        batch.set(_coll(hid, rid).doc(newId), {
          'uid': m['uid'] ?? '',
          'text': m['text'] ?? '',
          if (m['imageUrl'] != null) 'imageUrl': m['imageUrl'],
          // 旧コメントの投稿時刻を保持（無ければ現在時刻）。
          'createdAt': m['createdAt'] ?? FieldValue.serverTimestamp(),
        });
      }
      // 旧コメントを削除。
      for (final s in sources) {
        batch.delete(s);
      }
      // 品目側の💬バッジ（commentCount）は統合したので0に落とす。
      for (final txId in memberTxIds) {
        batch.set(_db.doc('households/$hid/transactions/$txId'),
            {'commentCount': 0}, SetOptions(merge: true));
      }
      // レシートの合計コメント数＋統合済みフラグ。
      final existing = (rd.data()?['commentCount'] as num?)?.toInt() ?? 0;
      batch.set(
          _receiptDoc(hid, rid),
          {
            'commentCount': existing + moved.length,
            'migratedFromItems': true,
          },
          SetOptions(merge: true));
      await batch.commit();
    } catch (_) {
      // 統合に失敗しても致命ではない（次回開いたときに再試行される）。
    }
  }
}
