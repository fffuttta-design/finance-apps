import 'package:flutter/material.dart';

import '../../../data/ui_preferences.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/v2_card.dart';

/// v2.1 ネイティブ「サイドバー並び順」パネル。
/// v1 SidebarOrderScreen の機能を v2.1 デザインで再実装。
/// 設定タブの右パネルに表示される（フルスクリーン遷移ではない）。
class V2SidebarOrderPanel extends StatefulWidget {
  const V2SidebarOrderPanel({super.key});

  @override
  State<V2SidebarOrderPanel> createState() =>
      _V2SidebarOrderPanelState();
}

class _V2SidebarOrderPanelState extends State<V2SidebarOrderPanel> {
  late List<String> _order;
  bool _dirty = false;

  /// ナビアイテムの表示情報（v1 と完全同等）
  static const Map<String, ({String label, IconData icon, String hint})>
      _items = {
    'home': (
      label: 'ホーム',
      icon: Icons.dashboard_outlined,
      hint: 'ホーム画面（残高・月次フロー）'
    ),
    'expenses': (
      label: '支出',
      icon: Icons.receipt_long_outlined,
      hint: '支出タブ'
    ),
    'income': (
      label: '収入',
      icon: Icons.savings_outlined,
      hint: '収入タブ'
    ),
    'asset': (
      label: '資産',
      icon: Icons.account_balance_wallet_outlined,
      hint: '資産タブ（ウォレット残高）'
    ),
    'cards': (
      label: 'クレカ',
      icon: Icons.credit_card_outlined,
      hint: 'クレジットカードタブ'
    ),
    'report': (
      label: '集計',
      icon: Icons.bar_chart_outlined,
      hint: '集計タブ（PL / カテゴリ別 / 月末締め）'
    ),
    'settings': (
      label: '設定',
      icon: Icons.settings_outlined,
      hint: '設定画面'
    ),
    'devLab': (
      label: '🧪 開発中',
      icon: Icons.science_outlined,
      hint: '事業モード専用の試作タブ'
    ),
  };

  @override
  void initState() {
    super.initState();
    _order = [...UiPreferences.instance.sidebarOrder];
  }

  Future<void> _save() async {
    await UiPreferences.instance.setSidebarOrder(_order);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('サイドバーの並び順を保存しました')),
    );
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
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ヘッダー
        Padding(
          padding: const EdgeInsets.fromLTRB(
              V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('サイドバー / 上タブの並び順',
                        style: V2Typography.h1),
                    const SizedBox(height: V2Spacing.xs),
                    Text(
                      'ドラッグでナビ項目を並び替え。v2.1 上タブ、v2 サイドバー、v1 サイドバーすべてに反映されます。',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt, size: 14),
                label: const Text('デフォルト'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              FilledButton.icon(
                onPressed: _dirty ? _save : null,
                icon: const Icon(Icons.check, size: 14),
                label: const Text('保存'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
        ),
        // リスト本体
        Expanded(
          child: V2Card(
            padding: EdgeInsets.zero,
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.sm, vertical: V2Spacing.sm),
              itemCount: _order.length,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final id = _order.removeAt(oldIdx);
                  _order.insert(newIdx, id);
                  _dirty = true;
                });
              },
              proxyDecorator:
                  (child, index, animation) => Material(
                color: Colors.transparent,
                child: child,
              ),
              itemBuilder: (context, i) {
                final id = _order[i];
                final item = _items[id];
                if (item == null) {
                  return SizedBox(key: ValueKey('unknown-$id'));
                }
                return _ReorderTile(
                  key: ValueKey(id),
                  index: i + 1,
                  icon: item.icon,
                  label: item.label,
                  hint: item.hint,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ReorderTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final String hint;
  const _ReorderTile({
    super.key,
    required this.index,
    required this.icon,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
        border: Border.all(color: V2Colors.border),
      ),
      child: Row(
        children: [
          // 番号バッジ
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
            ),
            child: Text('$index',
                style: V2Typography.micro.copyWith(
                    color: V2Colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: V2Typography.tabularNums)),
          ),
          const SizedBox(width: V2Spacing.sm),
          Icon(icon, size: 16, color: V2Colors.accent),
          const SizedBox(width: V2Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: V2Typography.bodyStrong.copyWith(
                        color: V2Colors.textPrimary)),
                Text(hint,
                    style: V2Typography.micro.copyWith(
                        color: V2Colors.textMuted)),
              ],
            ),
          ),
          ReorderableDragStartListener(
            index: index - 1,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_indicator,
                  color: V2Colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
