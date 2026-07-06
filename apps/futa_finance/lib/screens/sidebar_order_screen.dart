import 'package:flutter/material.dart';

import '../data/ui_preferences.dart';

/// サイドバー（広い画面の左ナビ）の並び順を編集する画面。
/// ドラッグでアイテムを並び替え → UiPreferences に永続化。
/// 並び順は root_screen の _SideNav が listen して即時反映。
class SidebarOrderScreen extends StatefulWidget {
  const SidebarOrderScreen({super.key});

  @override
  State<SidebarOrderScreen> createState() => _SidebarOrderScreenState();
}

class _SidebarOrderScreenState extends State<SidebarOrderScreen> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = [...UiPreferences.instance.sidebarOrder];
  }

  /// 識別子 → ナビアイテムの表示情報。
  /// devLab（開発中）は事業モード時のみサイドバーに表示されるが、
  /// 並び順の管理上はリストに含める（事業モード時に並び順が効く）。
  static const Map<String, ({String label, IconData icon, String hint})>
      _items = {
    'home': (
      label: 'ホーム',
      icon: Icons.home,
      hint: 'ホーム画面（残高・月次フロー）'
    ),
    'expenses': (
      label: '支出',
      icon: Icons.receipt_long,
      hint: '支出タブ'
    ),
    'income': (
      label: '収入',
      icon: Icons.savings,
      hint: '収入タブ'
    ),
    'asset': (
      label: '資産',
      icon: Icons.account_balance_wallet,
      hint: '資産タブ（ウォレット残高）'
    ),
    'cards': (
      label: 'クレカ',
      icon: Icons.credit_card,
      hint: 'クレジットカードタブ'
    ),
    'report': (
      label: '業績',
      icon: Icons.bar_chart,
      hint: '業績タブ（統計・テーブル・月末締め）'
    ),
    'settings': (
      label: '設定',
      icon: Icons.settings,
      hint: '設定画面'
    ),
    'devLab': (
      label: '🧪 開発中',
      icon: Icons.science,
      hint: '事業モード専用の試作タブ'
    ),
  };

  Future<void> _save() async {
    await UiPreferences.instance.setSidebarOrder(_order);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('サイドバーの並び順を保存しました')),
    );
    Navigator.pop(context);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('並び順をデフォルトに戻す'),
        content: const Text('現在のカスタム並び順を破棄してデフォルトに戻します。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('リセット')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _order = [...UiPreferences.defaultSidebarOrder];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('サイドバーの並び順',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt,
                color: Color(0xFF6B7280)),
            tooltip: 'デフォルトに戻す',
            onPressed: _reset,
          ),
          IconButton(
            icon:
                const Icon(Icons.check, color: Color(0xFF1A237E)),
            tooltip: '保存',
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 説明バナー
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.drag_indicator,
                      size: 16, color: Color(0xFF1A237E)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '右側の ⋮ をドラッグして並び替え。\n'
                      '広い画面（PC/タブレット）のサイドバー表示に反映されます。',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF1E3A8A)),
                    ),
                  ),
                ],
              ),
            ),
            // 並び替えリスト
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                itemCount: _order.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx--;
                    final id = _order.removeAt(oldIdx);
                    _order.insert(newIdx, id);
                  });
                },
                itemBuilder: (context, i) {
                  final id = _order[i];
                  final item = _items[id];
                  if (item == null) {
                    // 未知の識別子（将来追加 or 削除済）はスキップ表示
                    return SizedBox(
                      key: ValueKey('unknown-$id'),
                    );
                  }
                  return Container(
                    key: ValueKey(id),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFE5E7EB)),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B7280))),
                      ),
                      title: Row(
                        children: [
                          Icon(item.icon,
                              size: 18,
                              color: const Color(0xFF1A237E)),
                          const SizedBox(width: 8),
                          Text(item.label,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.hint,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9CA3AF))),
                      ),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_indicator,
                              color: Color(0xFFD1D5DB)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
