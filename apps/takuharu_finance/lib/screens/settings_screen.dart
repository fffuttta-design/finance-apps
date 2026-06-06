import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/update_flow.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'accounts_screen.dart';
import 'paste_import_screen.dart';
import 'replacements_screen.dart';

/// 設定：共有状態の表示、メンバー、サインアウト。
/// 二人専用アプリなので世帯コードの入力（参加）は不要（自動で共有）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
    // 設定画面は push されたルートなので、ルートまで戻して AuthGate を再表示
    // （これをしないと認証が消えても設定画面が残り「サインアウトできない」状態に）。
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// カップル向けの可愛い絵文字アイコン候補。
  static const _iconChoices = [
    '🐰', '🐻', '🐱', '🐶', '🐹', '🐧', '🦊', '🐢',
    '🌸', '🌷', '⭐', '🍓', '🍰', '☕', '💗', '👑',
  ];

  Future<void> _editMember(String uid, String name) async {
    final myUid = AuthService.instance.currentUser?.uid;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppColors.pinkDark),
              title: const Text('名前を変更'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _renameMember(uid, name);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.emoji_emotions_rounded, color: AppColors.pinkDark),
              title: const Text('アイコンを変更'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickIcon(uid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_rounded,
                  color: AppColors.pinkDark),
              title: Text(uid == myUid
                  ? '自分を世帯から外す'
                  : '「$name」を世帯から外す'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmRemove(uid, name, isSelf: uid == myUid);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _renameMember(String uid, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('名前を変更'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例: たく'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await HouseholdService.instance.setMemberName(uid, name);
    if (mounted) setState(() {});
  }

  Future<void> _pickIcon(String uid) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('アイコンを選ぶ'),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _iconChoices)
                InkWell(
                  onTap: () => Navigator.pop(dctx, e),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.pinkSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, ''), // 既定に戻す
            child: const Text('既定に戻す'),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    await HouseholdService.instance.setMemberIcon(uid, chosen);
    if (mounted) setState(() {});
  }

  Future<void> _editPersonalFoodBudget(
      String uid, String name, int current) async {
    final ctrl = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('$name の個人食費わく'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(prefixText: '¥ ', hintText: '例: 8000'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('やめる')),
          FilledButton(
            onPressed: () {
              final v =
                  int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
              Navigator.pop(dctx, v ?? -1);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result < 0) return;
    await HouseholdService.instance.setPersonalFoodBudget(uid, result);
    if (mounted) setState(() {});
  }

  Future<void> _confirmRemove(String uid, String name,
      {required bool isSelf}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('世帯から外す'),
        content: Text(isSelf
            ? '自分を世帯から外しますか？\n（このアプリからはサインアウトされ、再ログインすると再び参加します）'
            : '「$name」を世帯から外しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pinkDark),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('外す'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HouseholdService.instance.removeMember(uid);
    if (!mounted) return;
    if (isSelf) {
      await _signOut();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final hs = HouseholdService.instance;
    final entries = hs.memberNames.entries.toList();
    final myUid = AuthService.instance.currentUser?.uid;
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
                  if (entries.isEmpty)
                    const ListTile(
                      title: Text('読み込み中…',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  for (final e in entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.pinkSoft,
                        child: hs.memberIcons[e.key] != null &&
                                hs.memberIcons[e.key]!.isNotEmpty
                            ? Text(hs.memberIcons[e.key]!,
                                style: const TextStyle(fontSize: 20))
                            : const Icon(Icons.person_rounded,
                                color: AppColors.pinkDark),
                      ),
                      title: Text(
                          e.key == myUid ? '${e.value}（じぶん）' : e.value,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.edit_rounded,
                          size: 18, color: AppColors.textSub),
                      onTap: () => _editMember(e.key, e.value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('個人の食費わく'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 10, 0, 4),
                    child: Text(
                      '個人用の食費を共用財布から使ってよい月の上限。記録で「個人の食費わく」をONにすると、ここから引かれます。',
                      style: TextStyle(fontSize: 11, color: AppColors.textSub),
                    ),
                  ),
                  if (entries.isEmpty)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('読み込み中…',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  for (final e in entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.pinkSoft,
                        child: hs.memberIcons[e.key] != null &&
                                hs.memberIcons[e.key]!.isNotEmpty
                            ? Text(hs.memberIcons[e.key]!,
                                style: const TextStyle(fontSize: 20))
                            : const Icon(Icons.lunch_dining_rounded,
                                color: AppColors.pinkDark),
                      ),
                      title: Text(e.value,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '月 ${formatYen(hs.personalFoodBudgetFor(e.key))}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.edit_rounded,
                          size: 18, color: AppColors.textSub),
                      onTap: () => _editPersonalFoodBudget(
                          e.key, e.value, hs.personalFoodBudgetFor(e.key)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
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
