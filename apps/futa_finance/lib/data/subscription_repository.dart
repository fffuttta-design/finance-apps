import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// サブスクリプション（固定費）設定のリポジトリ抽象。
abstract class SubscriptionRepository {
  static SubscriptionRepository instance = LocalSubscriptionRepository();

  static void useLocal() {
    instance = LocalSubscriptionRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreSubscriptionRepository(uid: uid);
  }

  Future<SubscriptionConfig> load();
  Future<void> save(SubscriptionConfig config);
}

/// SharedPreferences ベースのローカル実装。
class LocalSubscriptionRepository implements SubscriptionRepository {
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.subscriptions';

  @override
  Future<SubscriptionConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return SubscriptionConfig.empty();
    try {
      return SubscriptionConfig.fromJsonString(raw);
    } catch (_) {
      return SubscriptionConfig.empty();
    }
  }

  @override
  Future<void> save(SubscriptionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}

/// Firestore 実装。Config 系は1ドキュメントに JSON 文字列を格納。
/// パス: `users/{uid}/config/{mode}_subscriptions`
class FirestoreSubscriptionRepository implements SubscriptionRepository {
  FirestoreSubscriptionRepository({required this.uid});
  final String uid;

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore
      .instance
      .doc('users/$uid/config/${_modeKey}_subscriptions');

  @override
  Future<SubscriptionConfig> load() async {
    final snap = await _doc.get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return SubscriptionConfig.empty();
    try {
      return SubscriptionConfig.fromJsonString(raw);
    } catch (_) {
      return SubscriptionConfig.empty();
    }
  }

  @override
  Future<void> save(SubscriptionConfig config) async {
    await _doc.set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
