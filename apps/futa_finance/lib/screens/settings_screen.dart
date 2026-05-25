import 'package:flutter/material.dart';

import 'account_editor_screen.dart';
import 'card_editor_screen.dart';
import 'category_editor_screen.dart';

/// 設定のトップ画面。各サブ設定への入り口を並べる。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '設定',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('お金の項目'),
            _tile(
              icon: Icons.category,
              title: 'カテゴリ編集',
              subtitle: '大カテゴリ・小カテゴリの追加と編集',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CategoryEditorScreen()),
              ),
            ),
            _tile(
              icon: Icons.account_balance,
              title: '銀行口座',
              subtitle: '取引で選択する銀行の登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AccountEditorScreen()),
              ),
            ),
            _tile(
              icon: Icons.credit_card,
              title: 'クレジットカード',
              subtitle: '取引で選択するカードの登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CardEditorScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1),
        ),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A237E)),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827))),
        subtitle: Text(subtitle,
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        trailing: const Icon(Icons.chevron_right,
            color: Color(0xFF9CA3AF), size: 20),
        onTap: onTap,
      ),
    );
  }
}
