import 'package:cloud_firestore/cloud_firestore.dart';

/// 月の予算（世帯で共有）。households/{hid} ドキュメントの monthlyBudget フィールド。
/// 専用サブコレクションを使わないことで Firestore ルール変更を不要にしている。
class BudgetRepository {
  BudgetRepository._();
  static final BudgetRepository instance = BudgetRepository._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String hid) =>
      _db.collection('households').doc(hid);

  /// 月の予算（円）の購読。未設定なら null。
  Stream<int?> watch(String hid) => _doc(hid)
      .snapshots()
      .map((s) => (s.data()?['monthlyBudget'] as num?)?.toInt());

  /// 月の予算を保存（null で解除）。
  Future<void> save(String hid, int? amount) =>
      _doc(hid).set({'monthlyBudget': amount}, SetOptions(merge: true));
}
