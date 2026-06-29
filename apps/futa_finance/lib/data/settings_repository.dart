import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/category_colors.dart';
import 'app_mode.dart';
import 'transfer_template.dart';

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
  Future<TransferTemplatesConfig> loadTransferTemplates();
  Future<void> saveTransferTemplates(TransferTemplatesConfig config);

  /// 指定モードのカテゴリ/支払方法を裏で先読みしてキャッシュを温める。
  /// 既定は何もしない（Local は元々即時）。
  Future<void> prefetch(String modeKey) async {}
}

/// SharedPreferences ベースのローカル実装。
class LocalSettingsRepository implements SettingsRepository {
  String get _kCategories =>
      'futa.${AppModeManager.instance.current.keyPrefix}.categories';
  String get _kPayments =>
      'futa.${AppModeManager.instance.current.keyPrefix}.payments';
  String get _kTransferTemplates =>
      'futa.${AppModeManager.instance.current.keyPrefix}.transfer_templates';

  // モード別の解析済みキャッシュ（prefix 'b'/'p' → Config）。
  // 切替のたびに JSON を解析し直すのを避ける。書き込みは save* を通る。
  final Map<String, CategoryConfig> _categoriesCache = {};
  final Map<String, PaymentMethodsConfig> _paymentsCache = {};

  CategoryConfig _defaultsForCurrentMode() {
    return AppModeManager.instance.current == AppMode.business
        ? CategoryConfig.businessDefaults()
        : CategoryConfig.personalDefaults();
  }

  @override
  Future<CategoryConfig> loadCategories() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _categoriesCache[prefix];
    if (cached != null) {
      CategoryColors.update(cached);
      return cached;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCategories);
    final result = raw == null
        ? _defaultsForCurrentMode()
        : (() {
            try {
              return CategoryConfig.fromJsonString(raw);
            } catch (_) {
              return _defaultsForCurrentMode();
            }
          })();
    _categoriesCache[prefix] = result;
    CategoryColors.update(result);
    return result;
  }

  @override
  Future<void> saveCategories(CategoryConfig config) async {
    _categoriesCache[AppModeManager.instance.current.keyPrefix] = config;
    CategoryColors.update(config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCategories, config.toJsonString());
  }

  @override
  Future<PaymentMethodsConfig> loadPayments() async {
    final prefix = AppModeManager.instance.current.keyPrefix;
    final cached = _paymentsCache[prefix];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPayments);
    final result = raw == null
        ? PaymentMethodsConfig.empty()
        : (() {
            try {
              return PaymentMethodsConfig.fromJsonString(raw);
            } catch (_) {
              return PaymentMethodsConfig.empty();
            }
          })();
    _paymentsCache[prefix] = result;
    return result;
  }

  @override
  Future<void> savePayments(PaymentMethodsConfig config) async {
    _paymentsCache[AppModeManager.instance.current.keyPrefix] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPayments, config.toJsonString());
  }

  @override
  Future<TransferTemplatesConfig> loadTransferTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTransferTemplates);
    if (raw == null) return TransferTemplatesConfig.empty();
    try {
      return TransferTemplatesConfig.fromJsonString(raw);
    } catch (_) {
      return TransferTemplatesConfig.empty();
    }
  }

  @override
  Future<void> saveTransferTemplates(TransferTemplatesConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTransferTemplates, config.toJsonString());
  }

  @override
  Future<void> prefetch(String modeKey) async {} // Local は即時のため不要
}

class FirestoreSettingsRepository implements SettingsRepository {
  FirestoreSettingsRepository({required this.uid});
  final String uid;

  /// モード別（'business'/'personal'）のメモリキャッシュ。
  /// モード切替直後にネットワーク往復を待たず前回値を即返すために使う。
  /// load 時はキャッシュを即返し、裏で最新を取得してキャッシュ更新（次回反映）。
  final Map<String, CategoryConfig> _categoriesCache = {};
  final Map<String, PaymentMethodsConfig> _paymentsCache = {};

  String get _modeKey =>
      AppModeManager.instance.current == AppMode.business
          ? 'business'
          : 'personal';

  CategoryConfig _defaultsFor(String modeKey) {
    return modeKey == 'business'
        ? CategoryConfig.businessDefaults()
        : CategoryConfig.personalDefaults();
  }

  DocumentReference<Map<String, dynamic>> _categoriesDocFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_categories');

  DocumentReference<Map<String, dynamic>> _paymentsDocFor(String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_payments');

  @override
  Future<void> prefetch(String modeKey) async {
    try {
      if (!_categoriesCache.containsKey(modeKey)) {
        await _fetchCategories(modeKey);
      }
      if (!_paymentsCache.containsKey(modeKey)) {
        await _fetchPayments(modeKey);
      }
    } catch (_) {}
  }

  @override
  Future<CategoryConfig> loadCategories() async {
    final mk = _modeKey;
    final cached = _categoriesCache[mk];
    if (cached != null) {
      CategoryColors.update(cached);
      // 裏で最新を取得してキャッシュ更新（cross-device 変更を次回に反映）。
      unawaited(_fetchCategories(mk));
      return cached;
    }
    return _fetchCategories(mk);
  }

  Future<CategoryConfig> _fetchCategories(String modeKey) async {
    final snap = await _categoriesDocFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    CategoryConfig result;
    if (raw == null) {
      result = _defaultsFor(modeKey);
    } else {
      try {
        result = CategoryConfig.fromJsonString(raw);
      } catch (_) {
        result = _defaultsFor(modeKey);
      }
    }
    _categoriesCache[modeKey] = result;
    CategoryColors.update(result);
    return result;
  }

  @override
  Future<void> saveCategories(CategoryConfig config) async {
    final mk = _modeKey;
    _categoriesCache[mk] = config;
    await _categoriesDocFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<PaymentMethodsConfig> loadPayments() async {
    final mk = _modeKey;
    final cached = _paymentsCache[mk];
    if (cached != null) {
      unawaited(_fetchPayments(mk));
      return cached;
    }
    return _fetchPayments(mk);
  }

  Future<PaymentMethodsConfig> _fetchPayments(String modeKey) async {
    final snap = await _paymentsDocFor(modeKey).get();
    final raw = snap.data()?['json'] as String?;
    PaymentMethodsConfig result;
    if (raw == null) {
      result = PaymentMethodsConfig.empty();
    } else {
      try {
        result = PaymentMethodsConfig.fromJsonString(raw);
      } catch (_) {
        result = PaymentMethodsConfig.empty();
      }
    }
    _paymentsCache[modeKey] = result;
    return result;
  }

  @override
  Future<void> savePayments(PaymentMethodsConfig config) async {
    final mk = _modeKey;
    _paymentsCache[mk] = config;
    await _paymentsDocFor(mk).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  DocumentReference<Map<String, dynamic>> _transferTemplatesDocFor(
          String modeKey) =>
      FirebaseFirestore.instance
          .doc('users/$uid/config/${modeKey}_transfer_templates');

  @override
  Future<TransferTemplatesConfig> loadTransferTemplates() async {
    final snap = await _transferTemplatesDocFor(_modeKey).get();
    final raw = snap.data()?['json'] as String?;
    if (raw == null) return TransferTemplatesConfig.empty();
    try {
      return TransferTemplatesConfig.fromJsonString(raw);
    } catch (_) {
      return TransferTemplatesConfig.empty();
    }
  }

  @override
  Future<void> saveTransferTemplates(TransferTemplatesConfig config) async {
    await _transferTemplatesDocFor(_modeKey).set({
      'json': config.toJsonString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
