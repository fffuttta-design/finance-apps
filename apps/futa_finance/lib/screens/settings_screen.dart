import 'package:flutter/material.dart';

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../mock/mock_data.dart';
import 'account_editor_screen.dart';
import 'card_editor_screen.dart';
import 'category_editor_screen.dart';
import 'income_master_screen.dart';
import 'subscription_list_screen.dart';

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
            _tile(
              icon: Icons.attach_money,
              title: '収入マスタ',
              subtitle: '継続収入・単発収入のテンプレート登録',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const IncomeMasterScreen()),
              ),
            ),
            _tile(
              icon: Icons.subscriptions,
              title: 'サブスク一覧',
              subtitle: '月払い/年払いの継続課金を一覧管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionListScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _section('データ管理'),
            _tile(
              icon: Icons.upload_file,
              title: 'サンプルデータを投入（全置換）',
              subtitle: '既存の取引を全削除し、5月実データ30件 + 住信SBI口座をセット',
              onTap: () => _seedSampleData(context),
            ),
            _tile(
              icon: Icons.delete_sweep,
              title: '全取引を削除',
              subtitle: '入力済みの取引を全て消去（戻せません）',
              onTap: () => _clearAll(context),
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedSampleData(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('サンプルデータを投入'),
        content: const Text(
            '現在の取引を全て削除し、2026年5月の実データ30件で置換します。\n'
            '住信SBI口座（月初¥10,652,701）が未登録なら同時に追加します。\n'
            'よろしいですか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('投入')),
        ],
      ),
    );
    if (ok != true) return;

    // 取引を全置換
    await TransactionRepository.instance
        .replaceAll(MockData.sampleTransactions());

    // 銀行口座が未登録 or 住信SBIがまだない場合のみ追加
    final settings = SettingsRepository();
    final payments = await settings.loadPayments();
    final hasSbi = payments.bankAccounts.any((b) => b.name == '住信SBI');
    if (!hasSbi) {
      await settings.savePayments(payments.copyWith(
        bankAccounts: [...payments.bankAccounts, MockData.sampleBank],
      ));
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(hasSbi
              ? 'サンプル30件で置換しました'
              : 'サンプル30件 + 住信SBI口座を投入しました')),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('全取引を削除'),
        content: const Text('登録されている全ての取引を削除します。\nこの操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    await TransactionRepository.instance.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全取引を削除しました')),
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
    bool danger = false,
  }) {
    final iconColor =
        danger ? const Color(0xFFDC2626) : const Color(0xFF1A237E);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
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
