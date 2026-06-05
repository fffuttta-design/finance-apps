import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../theme/app_theme.dart';

/// 設定：共有状態の表示、メンバー、サインアウト。
/// 二人専用アプリなので世帯コードの入力（参加）は不要（自動で共有）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    HouseholdService.instance.reset();
    // AuthGate が自動でログイン画面へ。
  }

  @override
  Widget build(BuildContext context) {
    final hs = HouseholdService.instance;
    final names = hs.memberNames.values.toList();
    final myEmail = AuthService.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 共有状態
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8FA8), Color(0xFFFF6B8A)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('ふたりで共有しています',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('ログインするだけで自動的に同じ家計簿になります ♡',
                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('メンバー'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  if (names.isEmpty)
                    const ListTile(
                      title: Text('読み込み中…',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  for (final n in names)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.pinkSoft,
                        child: Icon(Icons.person_rounded,
                            color: AppColors.pinkDark),
                      ),
                      title: Text(n,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('アカウント'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_rounded,
                  color: AppColors.pinkDark),
              title: Text(myEmail.isEmpty ? 'ログイン中' : myEmail,
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSub,
              side: const BorderSide(color: AppColors.divider),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('サインアウト'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      );
}
