import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../theme/app_theme.dart';

/// 設定：世帯コードの共有／参加、メンバー、サインアウト。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _joinCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _joinCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await HouseholdService.instance.joinHousehold(_joinCtrl.text, user);
      if (!mounted) return;
      _joinCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('世帯に参加しました ♡')),
      );
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    HouseholdService.instance.reset();
    // AuthGate が自動でログイン画面へ。
  }

  @override
  Widget build(BuildContext context) {
    final hs = HouseholdService.instance;
    final code = hs.householdId ?? '------';
    final names = hs.memberNames.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('ふたりの世帯コード'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('このコードをパートナーに教えてね',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                  const SizedBox(height: 10),
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: AppColors.pinkDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('コードをコピーしました')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('コピー'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('メンバー'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
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
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('パートナーの世帯に参加する'),
          const SizedBox(height: 8),
          const Text(
            'パートナーが先に登録している場合は、その世帯コードを入力すると\nふたりで同じ家計簿を共有できます。',
            style: TextStyle(fontSize: 12, color: AppColors.textSub),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _joinCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: '例: A1B2C3'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _join,
                child: const Text('参加'),
              ),
            ],
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
