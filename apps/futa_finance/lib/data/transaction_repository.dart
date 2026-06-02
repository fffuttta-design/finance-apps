import 'dart:async';
import 'dart:convert';

// cloud_firestore にも Transaction 型があるため、衝突回避で hide。
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 取引データのリポジトリ抽象。
///
/// Local（SharedPreferences）/ Firestore どちらの実装でも入れ替え可能。
/// UI 側は `TransactionRepository.instance` を経由してアクセス。
///
/// 切替は起動時に [useLocal] / [useFirestore] で行う。
abstract class TransactionRepository {
  static TransactionRepository instance = LocalTransactionRepository();

  /// ローカル（SharedPreferences）実装を有効化。デフォルト。
  static void useLocal() {
    if (instance is FirestoreTransactionRepository) {
      (instance as FirestoreTransactionRepository).dispose();
    }
    instance = LocalTransactionRepository();
  }

  /// Firestore 実装に切り替え（ログイン直後に呼ぶ）。
  static void useFirestore(String uid) {
    if (instance is FirestoreTransactionRepository) {
      (instance as FirestoreTransactionRepository).dispose();
    }
    instance = FirestoreTransactionRepository(uid: uid);
  }

  /// 変更通知ストリーム（loadAll後の最新リスト）。
  Stream<List<Transaction>> get stream;

  Future<List<Transaction>> loadAll();
  Future<void> add(Transaction t);
  Future<void> update(Transaction t);
  Future<void> delete(String id);

  /// 全件置換（サンプル投入やバックアップ復元で使用）。
  Future<void> replaceAll(List<Transaction> txns);

  /// 全削除。
  Future<void> clear();
}

/// SharedPreferences ベースのローカル永続化実装。
/// AppMode (事業/個人) ごとにキーが分離される。
class LocalTransactionRepository implements TransactionRepository {
  /// 現モード依存のキー。
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.transactions';

  /// モード別の解析済みキャッシュ（prefix 'b'/'p' → 取引リスト）。
  /// モード切替のたびに JSON を読み直して解析し直すのを避ける。
  /// 書き込みは全て [_saveAll] を通るため、ここを更新すれば整合性が保てる。
  final Map<String, List<Transaction>> _cache = {};

  final _controller = StreamController<List<Transaction>>.broadcast();

  @override
  Stream<List<Transaction>> get stream => _controller.stream;

  @override
  Future<List<Transaction>> loadAll() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _cache[prefix];
    // キャッシュは外部での書き換えを防ぐためコピーを返す。
    if (cached != null) return List<Transaction>.from(cached);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache[prefix] = const [];
      return [];
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache[prefix] = List<Transaction>.from(list);
      return list;
    } catch (_) {
      _cache[prefix] = const [];
      return [];
    }
  }

  Future<void> _saveAll(List<Transaction> txns) async {
    // キャッシュを先に更新（次回 loadAll が即返せる）。
    _cache[AppModeManager.instance.current.keyPrefix] =
        List<Transaction>.from(txns);
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(txns.map((t) => t.toJson()).toList());
    await prefs.setString(_key, json);
    _controller.add(txns);
  }

  @override
  Future<void> add(Transaction t) async {
    final list = await loadAll();
    list.add(t);
    await _saveAll(list);
  }

  @override
  Future<void> update(Transaction t) async {
    final list = await loadAll();
    final idx = list.indexWhere((x) => x.id == t.id);
    if (idx >= 0) {
      list[idx] = t;
      await _saveAll(list);
    }
  }

  @override
  Future<void> delete(String id) async {
    final list = await loadAll();
    list.removeWhere((t) => t.id == id);
    await _saveAll(list);
  }

  @override
  Future<void> replaceAll(List<Transaction> txns) async {
    await _saveAll(txns);
  }

  @override
  Future<void> clear() async {
    await _saveAll([]);
  }
}

/// Firestore ベースの実装。リアルタイム同期＋オフラインキャッシュ対応。
///
/// データ構造: `users/{uid}/transactions/{txId}`
/// - 各ドキュメントに `mode` フィールド ("business" / "personal") を持たせる
/// - クエリは where('mode', isEqualTo: 現モード) でフィルタ
class FirestoreTransactionRepository implements TransactionRepository {
  FirestoreTransactionRepository({required this.uid}) {
    _attachListener();
    AppModeManager.instance.addListener(_onModeChange);
  }

  final String uid;
  final _controller = StreamController<List<Transaction>>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  CollectionReference<Map<String, dynamic>> get _coll =>
      FirebaseFirestore.instance.collection('users/$uid/transactions');

  Query<Map<String, dynamic>> get _query =>
      _coll.where('mode', isEqualTo: _modeKey);

  void _attachListener() {
    _firestoreSub?.cancel();
    _firestoreSub = _query.snapshots().listen((snap) {
      final list = <Transaction>[];
      for (final d in snap.docs) {
        try {
          // mode フィールドを除いた dict で Transaction を再構築
          final data = Map<String, dynamic>.from(d.data())..remove('mode');
          list.add(Transaction.fromJson(data));
        } catch (_) {}
      }
      _controller.add(list);
    });
  }

  void _onModeChange() {
    _attachListener();
  }

  void dispose() {
    AppModeManager.instance.removeListener(_onModeChange);
    _firestoreSub?.cancel();
    _controller.close();
  }

  @override
  Stream<List<Transaction>> get stream => _controller.stream;

  @override
  Future<List<Transaction>> loadAll() async {
    final snap = await _query.get();
    final list = <Transaction>[];
    for (final d in snap.docs) {
      try {
        final data = Map<String, dynamic>.from(d.data())..remove('mode');
        list.add(Transaction.fromJson(data));
      } catch (_) {}
    }
    return list;
  }

  Map<String, dynamic> _txDoc(Transaction t) => {
        ...t.toJson(),
        'mode': _modeKey,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  @override
  Future<void> add(Transaction t) async {
    await _coll.doc(t.id).set(_txDoc(t));
  }

  @override
  Future<void> update(Transaction t) async {
    await _coll.doc(t.id).set(_txDoc(t));
  }

  @override
  Future<void> delete(String id) async {
    await _coll.doc(id).delete();
  }

  @override
  Future<void> replaceAll(List<Transaction> txns) async {
    // 現モードの既存ドキュメントを削除 → 新規バッチ書き込み
    final batch = FirebaseFirestore.instance.batch();
    final existing = await _query.get();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    for (final t in txns) {
      batch.set(_coll.doc(t.id), _txDoc(t));
    }
    await batch.commit();
  }

  @override
  Future<void> clear() async {
    final batch = FirebaseFirestore.instance.batch();
    final existing = await _query.get();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}
