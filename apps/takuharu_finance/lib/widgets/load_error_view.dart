import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../theme/app_theme.dart';

/// 読み込み失敗時の共通エラービュー（可愛い系）。
///
/// [permissionError]（Firestore の permission-denied）のときは、
/// 「このアカウントでは見られない＝ログインアカウント違いかも」を案内し、
/// 別アカウントへのログインし直し（サインアウト）を促す。
/// それ以外は通信エラー等として「もう一度」だけを出す。
class LoadErrorView extends StatelessWidget {
  final bool permissionError;
  final String? message;
  final VoidCallback onRetry;
  const LoadErrorView({
    super.key,
    required this.permissionError,
    required this.onRetry,
    this.message,
  });

  Future<void> _signOut() async {
    // userStream が AuthGate をログイン画面へ自動遷移させる。
    await AuthService.instance.signOut();
    HouseholdService.instance.reset();
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.currentUser?.email;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
              ),
              child: permissionError
                  ? _permission(email)
                  : _generic(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _permission(String? email) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_person_rounded, size: 48, color: AppColors.pink),
        const SizedBox(height: 12),
        const Text('このアカウントでは見られません',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        const Text(
          'ログイン中のアカウントには、このおうちの家計簿を見る権限がありません。'
          'アカウントを間違えていないか確認してね。',
          style: TextStyle(fontSize: 12, color: AppColors.textSub),
          textAlign: TextAlign.center,
        ),
        if (email != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.pinkSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_circle_rounded,
                    size: 18, color: AppColors.pinkDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('ログイン中: $email',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.text)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('べつのアカウントでログインし直す'),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('もう一度ためす'),
        ),
      ],
    );
  }

  Widget _generic() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.pink),
        const SizedBox(height: 12),
        const Text('データの読み込みに失敗しました',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        const Text(
          '通信が不安定なときに起きやすいです。電波の良い場所で'
          'もう一度お試しください。',
          style: TextStyle(fontSize: 12, color: AppColors.textSub),
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(message!,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textSub)),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('もう一度'),
          ),
        ),
      ],
    );
  }
}
