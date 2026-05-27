import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 設定（カテゴリ・支払方法）のリポジトリ抽象。
///
/// 既存コードは `SettingsRepository()` で new していたが、factory コンストラクタで
/// 現在の [instance] を返すよう変更（ログイン中は Firestore 版が返る）。
abstract class SettingsRepository {
  factory SettingsRepository() => instance;

  static SettingsRepository instance = LocalSettingsRepository();

  static void useLocal() {
    instance = LocalSettingsRepository();
  }

  static void useFirestore(String uid) {
    instance = FirestoreSettingsRepository(uid: uid);
  }

  Future<CategoryConfig> loadCategories();
  Future<void> saveCategories(CategoryConfig config);
  Future<PaymentMethodsConfig> loadPayments();
  Future<void> savePayments(PaymentMethodsConfig config);
}

/// SharedPreferences ベースのローカル実装。
class LocalSettingsRepository implements SettingsRepository {
  String get _kCategories =>
      'futa.${AppModeManager.instance.current.keyPrefix}.categories';
  String get _kPayments =>
      'futa.${AppModeManager.instance.current.keyPrefix}.payments';

  CategoryConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? CategoryConfig.businessDefaults()
        : CategoryConfig.personalDefaults();
  }

  @override
  Future<CategoryConfig> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCategories);
    if (raw == null) return _defaultsForCurrentMode();
    try {
      return CategoryConfig.fromJsonString(raw);
    } catch (_) {
      return _defaultsForCurrentMode();
    }
  }

  @override
  Future<void> saveCategories(CategoryConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCategories, config.toJsonString());
  }

  @override
  Future<PaymentMethodsConfig> loadPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPayments);
    if (raw == null) return PaymentMethodsConfig.empty();
    try {
      return PaymentMethodsConfig.fromJsonString(raw);
    } catch (_) {
      return PaymentMethodsConfig.empty();
    }
  }

  @override
  Future<void> savePayments(PaymentMethodsConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPayments, config.toJsonString());
  }
}

class FirestoreSettingsRepository implements SettingsRepository {
  FirestoreSettingsRepository({required this.uid});
  final String uid;

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  CategoryConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? CategoryConfig.businessDefaults()
        : CategoryConfig.personalDefaults();
  }

  DocumentReference<Map<String, dynamic>> get _categoriesDoc =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${_modeKey}_categories');

  DocumentReference<Map<String, dynamic>> get _paymentsDoc =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${_modeKey}_payments');

  @override
  Future<CategoryConfig> loadCategories() async {
    final snap = await _categoriesDoc.get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return _defaultsForCurrentMode();
    try {
      return CategoryConfig.fromJsonString(raw);
    } catch (_) {
      return _defaultsForCurrentMode();
    }
  }

  @override
  Future<void> saveCategories(CategoryConfig config) async {
    await _categoriesDoc.set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<PaymentMethodsConfig> loadPayments() async {
    final snap = await _paymentsDoc.get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return PaymentMethodsConfig.empty();
    try {
      return PaymentMethodsConfig.fromJsonString(raw);
    } catch (_) {
      return PaymentMethodsConfig.empty();
    }
  }

  @override
  Future<void> savePayments(PaymentMethodsConfig config) async {
    await _paymentsDoc.set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
