import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'checklist_repository.dart';
import 'income_source_repository.dart';
import 'month_closing_repository.dart';
import 'monthly_snapshot_repository.dart';
import 'settings_repository.dart';
import 'subscription_repository.dart';
import 'transaction_repository.dart';

/// 初回ログイン時に、ローカル（SharedPreferences）のデータを Firestore に
/// アップロードする一方向移行サービス。
///
/// - Firestore に既にデータがある場合（2台目以降の端末）はスキップ
/// - 完了したら uid 単位でフラグを立てて以降スキップ
/// - 失敗しても致命的でない（ローカルデータは残るので再試行可能）
class DataMigrationService {
  DataMigrationService._();

  static const _migratedKeyPrefix = 'futa.firestore_migrated.';

  /// 事業用カテゴリを PL 構成（科目＋セクション）へ一度だけ置き換える。
  /// 業務モードがアクティブな時に実行。カテゴリ「定義」のみ差し替え、
  /// 取引レコードは触らない（旧カテゴリ名は新科目のサブとして残してあるため、
  /// 過去取引はそのまま表示・PLにも反映される）。idempotent。
  static const _plCategoriesKey = 'futa.migration.pl_categories_v1';

  static Future<void> migratePLCategoriesIfNeeded() async {
    if (AppModeManager.instance.current != AppMode.business) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_plCategoriesKey) == true) return;
    await SettingsRepository.instance
        .saveCategories(CategoryConfig.futaDefaults());
    await prefs.setBool(_plCategoriesKey, true);
  }

  /// 必要なら移行を実行する（idempotent、複数回呼んでもOK）。
  static Future<void> migrateLocalToFirestoreIfNeeded(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final flagKey = '$_migratedKeyPrefix$uid';
    if (prefs.getBool(flagKey) == true) return;

    // 事業モード→個人モードの順で実行。
    for (final mode in AppMode.values) {
      await _migrateMode(uid, mode);
    }

    await prefs.setBool(flagKey, true);
  }

  /// 1モード分の移行。
  /// クラウド側に既存データがあれば、ローカル側を「クラウドが正」として上書きしない
  /// （複数端末からのデータ衝突回避）。
  static Future<void> _migrateMode(String uid, AppMode mode) async {
    // モード切替を一時的に実行して、Local Repository が正しいキーを参照するようにする。
    final originalMode = AppModeManager.instance.current;
    if (originalMode != mode) {
      await AppModeManager.instance.setMode(mode);
    }

    try {
      // ── 取引 ──
      await _migrateTransactions(uid, mode);

      // ── Config 系（Firestore に未存在なら Local をアップロード）──
      await _migrateConfig<CategoryConfig>(
        uid: uid,
        mode: mode,
        configKey: 'categories',
        loadLocal: () async {
          // Local Repository でロード
          final repo = LocalSettingsRepository();
          return await repo.loadCategories();
        },
        saveCloud: (config) async {
          await SettingsRepository.instance.saveCategories(config);
        },
        isEmpty: (config) => config.majors.isEmpty,
      );
      await _migrateConfig<PaymentMethodsConfig>(
        uid: uid,
        mode: mode,
        configKey: 'payments',
        loadLocal: () async {
          final repo = LocalSettingsRepository();
          return await repo.loadPayments();
        },
        saveCloud: (config) async {
          await SettingsRepository.instance.savePayments(config);
        },
        isEmpty: (config) =>
            config.bankAccounts.isEmpty && config.creditCards.isEmpty,
      );
      await _migrateConfig<SubscriptionConfig>(
        uid: uid,
        mode: mode,
        configKey: 'subscriptions',
        loadLocal: () async => await LocalSubscriptionRepository().load(),
        saveCloud: (config) async {
          await SubscriptionRepository.instance.save(config);
        },
        isEmpty: (config) => config.subscriptions.isEmpty,
      );
      await _migrateConfig<IncomeSourceConfig>(
        uid: uid,
        mode: mode,
        configKey: 'income_sources',
        loadLocal: () async => await LocalIncomeSourceRepository().load(),
        saveCloud: (config) async {
          await IncomeSourceRepository.instance.save(config);
        },
        isEmpty: (config) => config.sources.isEmpty,
      );
      await _migrateConfig<MonthlySnapshotConfig>(
        uid: uid,
        mode: mode,
        configKey: 'monthly_snapshots',
        loadLocal: () async =>
            await LocalMonthlySnapshotRepository().load(),
        saveCloud: (config) async {
          await MonthlySnapshotRepository.instance.save(config);
        },
        isEmpty: (config) => config.snapshots.isEmpty,
      );
      await _migrateConfig<MonthClosingConfig>(
        uid: uid,
        mode: mode,
        configKey: 'month_closing',
        loadLocal: () async => await LocalMonthClosingRepository().load(),
        saveCloud: (config) async {
          await MonthClosingRepository.instance.save(config);
        },
        isEmpty: (config) => config.closings.isEmpty,
      );
      await _migrateConfig<ChecklistConfig>(
        uid: uid,
        mode: mode,
        configKey: 'checklist',
        loadLocal: () async => await LocalChecklistRepository().load(),
        saveCloud: (config) async {
          await ChecklistRepository.instance.save(config);
        },
        // チェックリストは「デフォルト」が常にあるので isEmpty 判定で
        // 「未編集ならクラウドへアップロードしない」とする。
        isEmpty: (config) => config.items.isEmpty,
      );
    } finally {
      // モードを元に戻す
      if (originalMode != mode) {
        await AppModeManager.instance.setMode(originalMode);
      }
    }
  }

  /// 取引（個別ドキュメント）の移行。
  /// クラウドに既に取引があれば、ローカルからは追加しない（衝突回避）。
  static Future<void> _migrateTransactions(
      String uid, AppMode mode) async {
    // クラウド側の現在件数を確認
    final modeKey = mode == AppMode.business ? 'business' : 'personal';
    final cloudCount = await FirebaseFirestore.instance
        .collection('users/$uid/transactions')
        .where('mode', isEqualTo: modeKey)
        .count()
        .get();
    if ((cloudCount.count ?? 0) > 0) {
      // クラウド側に既にある → 移行スキップ
      return;
    }

    // ローカルから全件読込
    final local = await LocalTransactionRepository().loadAll();
    if (local.isEmpty) return;

    // Firestore Repository が現モードのものになっているはずなので
    // replaceAll でバルク投入（mode フィールドも自動付与される）
    await TransactionRepository.instance.replaceAll(local);
  }

  /// Config の移行（クラウドに無い、かつローカルに中身があれば push）。
  static Future<void> _migrateConfig<T>({
    required String uid,
    required AppMode mode,
    required String configKey,
    required Future<T> Function() loadLocal,
    required Future<void> Function(T) saveCloud,
    required bool Function(T) isEmpty,
  }) async {
    final modeKey = mode == AppMode.business ? 'business' : 'personal';
    final docPath = 'users/$uid/config/${modeKey}_$configKey';
    final cloudSnap =
        await FirebaseFirestore.instance.doc(docPath).get();
    if (cloudSnap.exists) {
      // クラウド側に既にある → 移行スキップ
      return;
    }
    final local = await loadLocal();
    if (isEmpty(local)) return;
    await saveCloud(local);
  }
}
