import 'package:cloud_firestore/cloud_firestore.dart';

/// 取引チャットの1メッセージ。
class TxComment {
  final String id;
  final String uid;
  final String text;

  /// 添付画像のDriveリンク（任意）。
  final String? imageUrl;
  final DateTime? createdAt;

  /// 'comment'＝2人の会話 / 'log'＝アプリが自動で残した変更履歴。
  /// log は吹き出しではなく中央のグレー帯で表示する（たくはるカレンダーと同じ）。
  final String kind;

  const TxComment(
      {required this.id,
      required this.uid,
      required this.text,
      this.imageUrl,
      this.createdAt,
      this.kind = 'comment'});

  bool get isLog => kind == 'log';
}

/// Firestore の1ドキュメントから [TxComment] を作る（取引／レシート共通）。
TxComment txCommentFromMap(String id, Map<String, dynamic> m) => TxComment(
      id: id,
      uid: (m['uid'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      imageUrl: m['imageUrl'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      kind: (m['kind'] ?? 'comment') as String,
    );

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
        list.add(txCommentFromMap(d.id, d.data()));
      }
      return list;
    });
  }

  Future<void> add(String hid, String txId, String uid, String text,
      {String? imageUrl}) async {
    final t = text.trim();
    // テキストか画像のどちらかがあれば送信。
    if (t.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final batch = _db.batch();
    batch.set(_coll(hid, txId).doc(id), {
      'uid': uid,
      'text': t,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // 親取引にコメント数を持たせて、一覧でバッジ表示できるようにする。
    batch.set(_txDoc(hid, txId),
        {'commentCount': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();
  }

  /// 変更履歴（アプリが自動で残す1行）を投稿する。
  /// 会話ではないので 💬 バッジ（commentCount）は増やさない。
  Future<void> addLog(String hid, String txId, String uid, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _coll(hid, txId).doc(id).set({
      'uid': uid,
      'text': t,
      'kind': 'log',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
