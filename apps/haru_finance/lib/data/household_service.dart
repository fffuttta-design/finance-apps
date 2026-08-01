import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 本人（はる）1 人ぶんの家計データの持ち主（スコープ）を管理する。
///
/// たくはるファイナンスの「世帯共有」を廃止し、すべて本人だけのデータにした。
/// データ構造:
///   users/{uid}                     { name, paymentMethods, replacements,
///                                      customExpenseCats, customIncomeCats,
///                                      monthlyBudget }
///   users/{uid}/transactions/{id}
///   users/{uid}/subscriptions/{id}
///   users/{uid}/accounts/{id}
///
/// 互換のためクラス名・`householdId` ゲッターはそのまま残しているが、
/// 中身は「ログイン中の uid」を指す（＝各リポジトリの保存先は users/{uid}/…）。
class HouseholdService extends ChangeNotifier {
  HouseholdService._();
  static final HouseholdService instance = HouseholdService._();

  final _db = FirebaseFirestore.instance;

  /// データの持ち主 = ログイン中の uid。
  String? _uid;
  String? get householdId => _uid;

  /// {uid: 表示名}。本人 1 人だけ。名前を出す画面のために保持する。
  Map<String, String> memberNames = {};

  /// 支払方法の一覧（現金/クレカ/PayPay 等）。users/{uid}.paymentMethods。
  static const defaultPayments = ['現金', 'クレジットカード', '電子マネー', '銀行振込'];
  List<String> paymentMethods = List.of(defaultPayments);

  /// 変換マスタ（読み取り表記ゆれ辞書）。users/{uid}.replacements。
  /// 各要素 {'from':..,'to':..}。レシートOCRの店名・品目名に適用。
  List<Map<String, String>> replacements = [];

  /// ユーザー追加のカスタムカテゴリ（既定カテゴリに追加表示）。
  List<String> customExpenseCats = [];
  List<String> customIncomeCats = [];

  List<String> customCats({required bool income}) =>
      income ? customIncomeCats : customExpenseCats;

  Future<void> addCustomCategory(String name, {required bool income}) async {
    final uid = _uid;
    final n = name.trim();
    if (uid == null || n.isEmpty) return;
    final list = income ? customIncomeCats : customExpenseCats;
    if (list.contains(n)) return;
    list.add(n);
    await _users.doc(uid).set({
      income ? 'customIncomeCats' : 'customExpenseCats': list,
    }, SetOptions(merge: true));
    notifyListeners();
  }

  Future<void> removeCustomCategory(String name,
      {required bool income}) async {
    final uid = _uid;
    if (uid == null) return;
    final list = income ? customIncomeCats : customExpenseCats;
    list.remove(name);
    await _users.doc(uid).set({
      income ? 'customIncomeCats' : 'customExpenseCats': list,
    }, SetOptions(merge: true));
    notifyListeners();
  }

  /// キャッシュ済みの変換ルールでテキストを置き換える（同期）。
  String applyReplacements(String text) {
    if (replacements.isEmpty || text.isEmpty) return text;
    var out = text;
    for (final r in replacements) {
      final f = r['from'] ?? '';
      if (f.isNotEmpty) out = out.replaceAll(f, r['to'] ?? '');
    }
    return out;
  }

  /// 変換ルールを保存する。
  Future<void> setReplacements(List<Map<String, String>> rules) async {
    final uid = _uid;
    if (uid == null) return;
    final clean = rules
        .where((r) => (r['from'] ?? '').trim().isNotEmpty)
        .map((r) =>
            {'from': (r['from'] ?? '').trim(), 'to': (r['to'] ?? '').trim()})
        .toList();
    await _users.doc(uid).set({'replacements': clean}, SetOptions(merge: true));
    replacements = clean;
    notifyListeners();
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// ログイン後に呼ぶ。本人のスコープ（uid）を確定し、設定を読み込む。
  Future<void> ensureHousehold(User user) async {
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'わたし';
    _uid = user.uid;
    final uref = _users.doc(user.uid);
    // 名前は初回のみ設定（以後は編集した名前を尊重）。
    final snap = await uref.get();
    if ((snap.data()?['name'] as String?)?.trim().isNotEmpty != true) {
      await uref.set({'name': name}, SetOptions(merge: true));
    }
    await _loadConfig();
    notifyListeners();
  }

  Future<void> _loadConfig() async {
    final uid = _uid;
    if (uid == null) return;
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    final nm = (data?['name'] as String?)?.trim();
    memberNames = {uid: (nm != null && nm.isNotEmpty) ? nm : 'わたし'};
    final pm = data?['paymentMethods'];
    if (pm is List && pm.isNotEmpty) {
      paymentMethods = pm.map((e) => '$e').toList();
    } else {
      paymentMethods = List.of(defaultPayments);
    }
    customExpenseCats = (data?['customExpenseCats'] is List)
        ? (data!['customExpenseCats'] as List).map((e) => '$e').toList()
        : <String>[];
    customIncomeCats = (data?['customIncomeCats'] is List)
        ? (data!['customIncomeCats'] as List).map((e) => '$e').toList()
        : <String>[];
    final rp = data?['replacements'];
    replacements = rp is List
        ? rp
            .whereType<Map>()
            .map((m) => {
                  'from': '${m['from'] ?? ''}',
                  'to': '${m['to'] ?? ''}',
                })
            .toList()
        : <Map<String, String>>[];
  }

  /// 支払方法の一覧を保存する。
  Future<void> setPaymentMethods(List<String> methods) async {
    final uid = _uid;
    if (uid == null) return;
    final clean = methods
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    await _users.doc(uid).set(
        {'paymentMethods': clean}, SetOptions(merge: true));
    paymentMethods = clean;
    notifyListeners();
  }

  void reset() {
    _uid = null;
    memberNames = {};
    notifyListeners();
  }
}
