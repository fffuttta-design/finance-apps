import 'app_mode.dart';
import 'budget_item_repository.dart';
import 'checklist_repository.dart';
import 'compliance_task_repository.dart';
import 'income_source_repository.dart';
import 'month_closing_repository.dart';
import 'monthly_snapshot_repository.dart';
import 'settings_repository.dart';
import 'subscription_repository.dart';
import 'transaction_repository.dart';

/// 全リポジトリの Local/Firestore 切替を一括管理する中央 Provider。
///
/// AuthGate が認証状態の変化を検知して、ログイン時に [useFirestore]、
/// ログアウト時に [useLocal] を呼ぶ。各 Repository の static instance が
/// 一斉に差し替わるので、UI 側は何も変更不要で同期が動き出す。
class RepositoryProvider {
  RepositoryProvider._();

  /// 現在 Firestore 版を使っているか。
  static bool _firestoreActive = false;
  static String? _currentUid;

  static bool get isFirestoreActive => _firestoreActive;
  static String? get currentUid => _currentUid;

  /// 全リポジトリを Firestore 実装に切替（ログイン直後）。
  static void useFirestore(String uid) {
    if (_firestoreActive && _currentUid == uid) return;
    TransactionRepository.useFirestore(uid);
    SettingsRepository.useFirestore(uid);
    SubscriptionRepository.useFirestore(uid);
    IncomeSourceRepository.useFirestore(uid);
    MonthlySnapshotRepository.useFirestore(uid);
    MonthClosingRepository.useFirestore(uid);
    ChecklistRepository.useFirestore(uid);
    BudgetItemRepository.instance.useFirestore(uid);
    ComplianceTaskRepository.instance.useFirestore(uid);
    _firestoreActive = true;
    _currentUid = uid;
  }

  /// 全リポジトリを Local 実装に切替（ログアウト時）。
  static void useLocal() {
    TransactionRepository.useLocal();
    SettingsRepository.useLocal();
    SubscriptionRepository.useLocal();
    IncomeSourceRepository.useLocal();
    MonthlySnapshotRepository.useLocal();
    MonthClosingRepository.useLocal();
    ChecklistRepository.useLocal();
    BudgetItemRepository.instance.useLocal();
    ComplianceTaskRepository.instance.useLocal();
    _firestoreActive = false;
    _currentUid = null;
  }

  /// 現在と逆のモードのデータを裏で先読みしてキャッシュを温める。
  /// 起動後に1回呼ぶと、事業⇄個人の初回切替のもたつきが軽減される。
  /// Firestore 利用時のみ意味がある（Local は元々即時）。
  static Future<void> prefetchOtherMode() async {
    if (!_firestoreActive) return;
    final other = AppModeManager.instance.current == AppMode.business
        ? 'personal'
        : 'business';
    await Future.wait([
      TransactionRepository.instance.prefetch(other),
      SettingsRepository.instance.prefetch(other),
      MonthlySnapshotRepository.instance.prefetch(other),
    ]);
  }
}
