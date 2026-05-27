import 'package:flutter/foundation.dart';

/// PaymentMethodsConfig（ウォレット/カード）の保存変更通知。
///
/// SettingsRepository.savePayments() を経由した時に notify される。
/// 各画面（ホーム残高セクション、資産タブ、通帳画面等）はこれを listen して
/// payments の最新値を再ロードする運用。
///
/// 各 Repository 実装 (Local/Firestore) は元々 Stream を持たないため、
/// アプリ層で集約した変更通知を一本化する。
class PaymentsChangeNotifier extends ChangeNotifier {
  PaymentsChangeNotifier._();
  static final PaymentsChangeNotifier instance =
      PaymentsChangeNotifier._();

  /// savePayments 完了後に呼ぶ。
  void notifyChanged() => notifyListeners();
}
