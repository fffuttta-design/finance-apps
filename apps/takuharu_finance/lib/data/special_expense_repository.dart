import 'package:cloud_firestore/cloud_firestore.dart';

import 'special_expense.dart';

/// 特別支出（世帯共有）。households/{hid}/special_expenses。
class SpecialExpenseRepository {
  SpecialExpenseRepository._();
  static final SpecialExpenseRepository instance =
      SpecialExpenseRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _coll(String hid) =>
      _db.collection('households/$hid/special_expenses');

  /// 新しい順（開始日の降順）に購読する。
  Stream<List<SpecialExpense>> watch(String hid) {
    return _coll(hid).snapshots().map((snap) {
      final list = <SpecialExpense>[];
      for (final d in snap.docs) {
        try {
          list.add(
              SpecialExpense.fromJson(Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      list.sort((a, b) => b.start.compareTo(a.start));
      return list;
    });
  }

  /// 一度だけ取得する（登録画面の候補出しなど）。
  Future<List<SpecialExpense>> fetch(String hid) async {
    final snap = await _coll(hid).get();
    final list = <SpecialExpense>[];
    for (final d in snap.docs) {
      try {
        list.add(SpecialExpense.fromJson(Map<String, dynamic>.from(d.data())));
      } catch (_) {}
    }
    list.sort((a, b) => b.start.compareTo(a.start));
    return list;
  }

  Future<void> save(String hid, SpecialExpense e, String uid) async {
    await _coll(hid).doc(e.id).set({
      ...e.toJson(),
      'createdAt': (e.createdAt ?? DateTime.now()).toIso8601String(),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 箱だけを消す。ぶら下がっている取引は消さない（呼び出し側で外す）。
  Future<void> delete(String hid, String id) async {
    await _coll(hid).doc(id).delete();
  }
}
