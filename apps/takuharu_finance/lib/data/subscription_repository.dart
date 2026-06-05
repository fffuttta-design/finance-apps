import 'package:cloud_firestore/cloud_firestore.dart';

import 'subscription.dart';

/// 固定費・サブスク（世帯共有）。households/{hid}/subscriptions。
class SubscriptionRepository {
  SubscriptionRepository._();
  static final SubscriptionRepository instance = SubscriptionRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _coll(String hid) =>
      _db.collection('households/$hid/subscriptions');

  Stream<List<Subscription>> watch(String hid) {
    return _coll(hid).snapshots().map((snap) {
      final list = <Subscription>[];
      for (final d in snap.docs) {
        try {
          list.add(Subscription.fromJson(Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      list.sort((a, b) => b.amount.compareTo(a.amount));
      return list;
    });
  }

  Future<void> save(String hid, Subscription s) async {
    await _coll(hid).doc(s.id).set({
      ...s.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String hid, String id) async {
    await _coll(hid).doc(id).delete();
  }
}
