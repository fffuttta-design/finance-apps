import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../data/update_flow.dart';
import '../theme/app_theme.dart';
import 'accounts_screen.dart';
import 'paste_import_screen.dart';
import 'replacements_screen.dart';

import '../widgets/web_layout.dart';
/// 設定：お金（口座・支払方法）・データ・アプリ。
/// 個人用アプリなので世帯・メンバー・通知の設定は無い。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // サイドバーで選択中のカテゴリ（0:お金 1:データ 2:アプリ）。
  int _tab = 0;

  static const _navItems = <({IconData icon, String label})>[
    (icon: Icons.account_balance_wallet_rounded, label: 'お金'),
    (icon: Icons.storage_rounded, label: 'データ'),
    (icon: Icons.smartphone_rounded, label: 'アプリ'),
  ];

  Future<void> _addPayment() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('支払方法を追加'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例: 楽天カード / PayPay'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('追加')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final list = List<String>.of(HouseholdService.instance.paymentMethods);
    if (!list.contains(name)) list.add(name);
    await HouseholdService.instance.setPaymentMethods(list);
    if (mounted) setState(() {});
  }

  Future<void> _removePayment(String m) async {
    final list = List<String>.of(HouseholdService.instance.paymentMethods)
      ..remove(m);
    await HouseholdService.instance.setPaymentMethods(list);
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    HouseholdService.instance.reset();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: WebCenterFill(
        maxWidth: 900,
        child: LayoutBuilder(builder: (context, c) {
          final double railWidth = c.maxWidth < 480 ? 92 : 132;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: railWidth,
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  border: Border(
                    right: BorderSide(color: AppColors.divider),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      for (var i = 0; i < _navItems.length; i++)
                        _NavTile(
                          icon: _navItems[i].icon,
                          label: _navItems[i].label,
                          selected: _tab == i,
                          onTap: () => setState(() => _tab = i),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _moneyTab(),
                    _dataTab(),
                    _appTab(),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// タブ①「お金」：口座・クレカ・支払方法。
  Widget _moneyTab() {
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('口座・クレカ'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.pinkDark),
              title: const Text('口座・残高の管理',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('銀行・クレカ・現金を登録。記録の支払元＆残高になります',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSub),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('支払方法（口座未登録のとき用）'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in HouseholdService.instance.paymentMethods)
                        Chip(
                          label: Text(m),
                          onDeleted: () => _removePayment(m),
                          backgroundColor: AppColors.pinkSoft,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _addPayment,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('追加'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
    );
  }

  /// タブ②「データ」：貼り付け取り込み・変換マスタ。
  Widget _dataTab() {
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('データ'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.content_paste_rounded,
                  color: AppColors.pinkDark),
              title: const Text('貼り付けで取り込み',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('日付・カテゴリ・内容・金額を一括登録',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PasteImportScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.find_replace_rounded,
                  color: AppColors.pinkDark),
              title: const Text('変換マスタ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('レシートの表記ゆれを置き換え',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReplacementsScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_fix_high_rounded,
                  color: AppColors.pinkDark),
              title: const Text('消費税・差額のカテゴリを直す',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('過去の「その他」をレシートの主なカテゴリに付け替え',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _repairAdjustments,
            ),
          ),
        ],
    );
  }

  /// 過去の差額調整のカテゴリを、そのレシートの主なカテゴリへ付け替える。
  Future<void> _repairAdjustments() async {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('消費税・差額のカテゴリを直す'),
        content: const Text(
            '過去に「その他」で記録された「消費税・調整」「値引き・調整」を、\n'
            'そのレシートの主なカテゴリ（食費のレシートなら食費）に付け替えます。\n\n'
            '金額・日付・品名は変わりません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('直す')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await TxRepository.instance.repairAdjustmentCategories(hid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n == 0 ? '直すものはありませんでした' : '$n件のカテゴリを直しました')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('直せませんでした')));
    }
  }

  /// タブ③「アプリ」：アカウント・更新・サインアウト。
  Widget _appTab() {
    final myEmail = AuthService.instance.currentUser?.email ?? '';
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          const SizedBox(height: 20),
          _sectionTitle('アプリ'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update_rounded,
                  color: AppColors.pinkDark),
              title: const Text('アプリの更新を確認',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => UpdateFlow.checkManually(context),
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

/// サイドバーの1項目（アイコンを上、ラベルを下）。選択中は水色で強調。
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.pinkDark : AppColors.textSub;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: selected ? AppColors.pinkSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
