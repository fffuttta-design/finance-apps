import 'dart:async';

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

  // モード別の解析済みキャッシュ。切替時の再解析を避ける。
  final Map<String, SubscriptionConfig> _cache = {};

  @override
  Future<SubscriptionConfig> load() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    SubscriptionConfig result;
    if (raw == null) {
      result = SubscriptionConfig.empty();
    } else {
      try {
        result = SubscriptionConfig.fromJsonString(raw);
      } catch (_) {
        result = SubscriptionConfig.empty();
      }
    }
    _cache[prefix] = result;
    return result;
  }

  @override
  Future<void> save(SubscriptionConfig config) async {
    _cache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.toJsonString());
  }
}

/// Firestore 実装。Config 系は1ドキュメントに JSON 文字列を格納。
/// パス: `users/{uid}/config/{mode}_subscriptions`
class FirestoreSubscriptionRepository implements SubscriptionRepository {
  FirestoreSubscriptionRepository({required this.uid});
  final String uid;

  /// モード別メモリキャッシュ。モード切替直後の即表示用（裏で最新取得）。
  final Map<String, SubscriptionConfig> _cache = {};

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  DocumentReference<Map<String, dynamic>> _docFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_subscriptions');

  @override
  Future<SubscriptionConfig> load() async {
    final mk = _modeKey;
    final cached = _cache[mk];
    if (cached != null) {
      unawaited(_fetch(mk));
      return cached;
    }
    return _fetch(mk);
  }

  Future<SubscriptionConfig> _fetch(String modeKey) async {
    final snap = await _docFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    SubscriptionConfig result;
    if (raw == null) {
      result = SubscriptionConfig.empty();
    } else {
      try {
        result = SubscriptionConfig.fromJsonString(raw);
      } catch (_) {
        result = SubscriptionConfig.empty();
      }
    }
    _cache[modeKey] = result;
    return result;
  }

  @override
  Future<void> save(SubscriptionConfig config) async {
    final mk = _modeKey;
    // 🛡 安全ガード: 空リストで「2件以上ある既存」を上書きしようとしたら拒否する。
    // 過去に事業14件→0・個人6件→2 の消失事故があった（引き金は未特定：誤った
    // バックアップ取り込み／読み込み時のパース失敗で空キャッシュ→保存、等が疑い）。
    // 破滅的な“全消し上書き”だけを防ぐ。1件→0（最後の1件削除）は通す。
    if (config.subscriptions.isEmpty) {
      try {
        final raw = (await _docFor(mk).get()).data()?['json'] as String?;
        if (raw != null &&
            SubscriptionConfig.fromJsonString(raw).subscriptions.length >= 2) {
          // 既存が2件以上あるのに空で上書き＝異常。保存を中止して既存を守る。
          return;
        }
      } catch (_) {
        // 既存確認に失敗したら従来どおり保存する（ガードは保守的に）。
      }
    }
    _cache[mk] = config;
    await _docFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
