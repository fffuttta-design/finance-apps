import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart' as core;

import 'categories.dart';

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

  /// txId 単体を取得（通知タップからチャットを開く用）。
  Future<core.Transaction?> getById(String hid, String txId) async {
    try {
      final d = await _coll(hid).doc(txId).get();
      if (!d.exists || d.data() == null) return null;
      return core.Transaction.fromJson(Map<String, dynamic>.from(d.data()!));
    } catch (_) {
      return null;
    }
  }

  Future<void> add(String hid, core.Transaction t, String uid) async {
    await _coll(hid).doc(t.id).set({
      ...t.toJson(),
      'recordedBy': uid,
      // 登録日時（初回保存時のみ。明細に「いつ登録したか」を出すため）。
      'createdAt': (t.createdAt ?? DateTime.now()).toIso8601String(),
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
        // 登録日時（初回保存時のみ。レシート品目も個別に「いつ登録したか」を持つ）。
        'createdAt': (t.createdAt ?? DateTime.now()).toIso8601String(),
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

  /// 取引を削除する。削除した本人 [uid] を記録してから消すことで、
  /// 通知サービス側が「削除した人を除いた相手」へ通知できる（自己通知を防ぐ）。
  Future<void> delete(String hid, String id, String uid) async {
    try {
      await _coll(hid)
          .doc(id)
          .set({'deletedBy': uid}, SetOptions(merge: true));
    } catch (_) {/* 失敗しても削除は続行（削除者不明で通知されるだけ） */}
    await _coll(hid).doc(id).delete();
  }

  /// 指定 receiptId の品目をすべて取得（レシート詳細の再読み込み用）。
  /// まとめ編集で品目を足し引きしたあと、最新の品目リストを取り直す。
  Future<List<core.Transaction>> listByReceiptId(
      String hid, String receiptId) async {
    final list = <core.Transaction>[];
    try {
      final snap =
          await _coll(hid).where('receiptId', isEqualTo: receiptId).get();
      for (final d in snap.docs) {
        try {
          list.add(
              core.Transaction.fromJson(Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
    } catch (_) {}
    // id は登録時刻ベースなので、id 昇順で並びを安定させる。
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  /// 指定 receiptId の取引すべてに receiptUrl を後付けする（裏のDrive保存完了後）。
  /// 既に保存済みの品目へ、あとから画像リンクを紐付けるために使う。
  Future<void> attachReceiptUrl(
      String hid, String receiptId, String url) async {
    final snap =
        await _coll(hid).where('receiptId', isEqualTo: receiptId).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.set(d.reference, {'receiptUrl': url}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// 過去に「その他」で記録された差額調整（消費税・調整／値引き・調整）の行を、
  /// そのレシートの主たるカテゴリ（品目の金額合計が一番大きいカテゴリ）に付け替える。
  /// v0.2.96 以降の新規記録は最初からこのカテゴリで入るので、これは一度きりの直し用。
  /// 戻り値は直した件数。金額・日付・品名は変更しない。
  Future<int> repairAdjustmentCategories(String hid) async {
    const adjNames = ['消費税・調整', '値引き・調整'];
    final snap =
        await _coll(hid).where('description', whereIn: adjNames).get();
    var fixed = 0;
    // レシートごとの品目は使い回すのでキャッシュする。
    final cache = <String, List<core.Transaction>>{};
    for (final d in snap.docs) {
      core.Transaction t;
      try {
        t = core.Transaction.fromJson(Map<String, dynamic>.from(d.data()));
      } catch (_) {
        continue;
      }
      final rid = t.receiptId;
      if (rid == null || rid.isEmpty) continue;
      final members = cache[rid] ??= await listByReceiptId(hid, rid);
      // 主たるカテゴリは「調整行以外の品目」から決める。
      final cat = dominantCategory(members
          .where((m) => !adjNames.contains(m.description))
          .map((m) => (m.category.major, m.amount)));
      if (cat == t.category.major) continue;
      await d.reference.set({
        'categoryMajor': cat,
        'categorySub': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      fixed++;
    }
    return fixed;
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
