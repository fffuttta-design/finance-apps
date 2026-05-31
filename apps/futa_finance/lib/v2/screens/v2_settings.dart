import 'package:flutter/material.dart';

import '../../data/app_mode.dart';
import '../../data/ui_preferences.dart';
import '../../screens/account_editor_screen.dart';
import '../../screens/card_editor_screen.dart';
import '../../screens/category_editor_screen.dart';
import '../../screens/checklist_editor_screen.dart';
import '../../screens/income_master_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/sidebar_order_screen.dart';
import '../../screens/subscription_list_screen.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 ネイティブ設定タブ。
/// 左メニュー（カテゴリ別） + 右コンテンツのマスター/ディテール構成。
///
/// - 表示設定 / サイドバー並び順 / UI バージョン / 未使用フラグ は v2.1 ネイティブ
/// - カテゴリ / ウォレット / クレカ / 収入マスタ / 固定費 / チェックリスト / バックアップ
///   は v1 画面を右パネルに埋め込み（AppBar を潰す）
/// - 各 v1 エディタは将来順次 v2.1 ネイティブで書き直す
class V2SettingsScreen extends StatefulWidget {
  final Color accent;
  const V2SettingsScreen({super.key, required this.accent});

  @override
  State<V2SettingsScreen> createState() => _V2SettingsScreenState();
}

class _V2SettingsScreenState extends State<V2SettingsScreen> {
  String _currentId = 'display';

  static const _menus = <_MenuGroup>[
    _MenuGroup(title: '表示・UI', items: [
      _MenuItem('display', '表示設定', Icons.tune),
      _MenuItem('sidebarOrder', 'サイドバー並び順', Icons.view_sidebar_outlined),
    ]),
    _MenuGroup(title: 'マスタデータ', items: [
      _MenuItem('category', 'カテゴリ', Icons.label_outline),
      _MenuItem('wallet', 'ウォレット（銀行/現金/電子マネー）',
          Icons.account_balance_wallet_outlined),
      _MenuItem('card', 'クレジットカード', Icons.credit_card_outlined),
      _MenuItem('incomeMaster', '収入マスタ', Icons.savings_outlined),
      _MenuItem('subscription', '固定費・サブスク', Icons.event_repeat),
      _MenuItem('checklist', '月末締めチェックリスト', Icons.checklist),
    ]),
    _MenuGroup(title: 'データ管理', items: [
      _MenuItem('backup', 'バックアップ / 取り込み',
          Icons.cloud_upload_outlined),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 左: メニュー ──
          SizedBox(
            width: 240,
            child: _SettingsMenu(
              groups: _menus,
              currentId: _currentId,
              accent: widget.accent,
              onSelect: (id) => setState(() => _currentId = id),
            ),
          ),
          const SizedBox(width: V2Spacing.lg),
          // ── 右: パネル ──
          Expanded(child: _buildPanel()),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    switch (_currentId) {
      case 'display':
        return const _DisplayPanel();
      case 'sidebarOrder':
        return _embedV1(const SidebarOrderScreen(),
            title: 'サイドバー並び順');
      case 'category':
        return _embedV1(const CategoryEditorScreen(),
            title: 'カテゴリ編集');
      case 'wallet':
        return _embedV1(const AccountEditorScreen(),
            title: 'ウォレット（銀行/現金/電子マネー）');
      case 'card':
        return _embedV1(const CardEditorScreen(),
            title: 'クレジットカード');
      case 'incomeMaster':
        return _embedV1(const IncomeMasterScreen(),
            title: '収入マスタ');
      case 'subscription':
        return _embedV1(const SubscriptionListScreen(),
            title: '固定費・サブスク');
      case 'checklist':
        return _embedV1(const ChecklistEditorScreen(),
            title: '月末締めチェックリスト');
      case 'backup':
        // v1 設定画面の「データ管理」セクションに飛ばす
        return _embedV1(const SettingsScreen(),
            title: 'バックアップ / 取り込み',
            note:
                '設定画面の「データ管理」セクションでバックアップ書き出し / 取り込みができます。');
      default:
        return const _DisplayPanel();
    }
  }

  Widget _embedV1(Widget child,
      {required String title, String? note}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(title: title, note: note),
        const SizedBox(height: V2Spacing.sm),
        Expanded(
          child: V2Card(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(V2Spacing.radiusLg),
              child: Theme(
                data: Theme.of(context).copyWith(
                  appBarTheme: const AppBarTheme(
                    toolbarHeight: 0,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════
// 左メニュー
// ═════════════════════════════════════════════════

class _MenuGroup {
  final String title;
  final List<_MenuItem> items;
  const _MenuGroup({required this.title, required this.items});
}

class _MenuItem {
  final String id;
  final String label;
  final IconData icon;
  const _MenuItem(this.id, this.label, this.icon);
}

class _SettingsMenu extends StatelessWidget {
  final List<_MenuGroup> groups;
  final String currentId;
  final Color accent;
  final ValueChanged<String> onSelect;
  const _SettingsMenu({
    required this.groups,
    required this.currentId,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return V2Card(
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.sm, vertical: V2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var gi = 0; gi < groups.length; gi++) ...[
            if (gi > 0) const SizedBox(height: V2Spacing.md),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.xs),
              child: Text(groups[gi].title,
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
            for (final item in groups[gi].items)
              _MenuTile(
                item: item,
                selected: item.id == currentId,
                accent: accent,
                onTap: () => onSelect(item.id),
              ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatefulWidget {
  final _MenuItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _MenuTile({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? V2Colors.accentSoft
        : (_hover ? V2Colors.hover : Colors.transparent);
    final fg = selected ? widget.accent : V2Colors.textBody;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(V2Spacing.radiusSm),
            ),
            child: Row(
              children: [
                Icon(widget.item.icon, size: 14, color: fg),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: V2Typography.caption.copyWith(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
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

// ═════════════════════════════════════════════════
// 右パネル: 共通ヘッダー
// ═════════════════════════════════════════════════

class _PanelHeader extends StatelessWidget {
  final String title;
  final String? note;
  const _PanelHeader({required this.title, this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.h1),
          if (note != null) ...[
            const SizedBox(height: V2Spacing.xs),
            Text(note!,
                style: V2Typography.caption.copyWith(
                    color: V2Colors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 表示設定パネル（v2.1 ネイティブ）
// ═════════════════════════════════════════════════

class _DisplayPanel extends StatelessWidget {
  const _DisplayPanel();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UiPreferences.instance,
      builder: (_, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeader(
                title: '表示設定',
                note: 'UI のバージョンや見た目の細かい挙動を切替えます。'),
            const SizedBox(height: V2Spacing.sm),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _SettingTile(
                      icon: Icons.dashboard_customize_outlined,
                      iconColor: V2Colors.accent,
                      title: 'UI バージョン',
                      subtitle:
                          '自動: Web は v2.1（推奨）、Android は v1。',
                      trailing: _UiVersionSelector(),
                    ),
                    _SettingTile(
                      icon: Icons.view_compact_outlined,
                      iconColor: V2Colors.badgeBlue,
                      title: 'v2 レイアウト',
                      subtitle: 'サイドバー版 (v2) / 上タブ版 (v2.1) の切替',
                      trailing: _V2VariantSelector(),
                    ),
                    _SettingTile(
                      icon: Icons.visibility_off_outlined,
                      iconColor: V2Colors.textSecondary,
                      title: '未使用のウォレット/カードを隠す',
                      subtitle:
                          '各ウォレット/クレカ編集で「未使用」フラグを立てた項目を非表示にする',
                      trailing: Switch.adaptive(
                        value:
                            UiPreferences.instance.hideInactive,
                        onChanged: (v) => UiPreferences.instance
                            .setHideInactive(v),
                        activeThumbColor: V2Colors.accent,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.md),
                    _ModeIndicator(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.sm),
      child: V2Card(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: V2Spacing.md),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(V2Spacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: V2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V2Typography.bodyStrong),
                  Text(subtitle,
                      style: V2Typography.micro.copyWith(
                          color: V2Colors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.md),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _UiVersionSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final v = UiPreferences.instance.useV2Ui;
    final label = v == null
        ? '自動'
        : (v ? 'v2.1 を強制' : 'v1 (旧)');
    return PopupMenuButton<bool?>(
      tooltip: '切替',
      onSelected: (val) =>
          UiPreferences.instance.setUseV2Ui(val),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: null,
          checked: v == null,
          child: const Text('自動（推奨）'),
        ),
        CheckedPopupMenuItem(
          value: true,
          checked: v == true,
          child: const Text('v2.1 を強制'),
        ),
        CheckedPopupMenuItem(
          value: false,
          checked: v == false,
          child: const Text('v1 を強制（旧 UI / 非推奨）'),
        ),
      ],
      child: _SelectorChip(label: label),
    );
  }
}

class _V2VariantSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final variant = UiPreferences.instance.v2Variant;
    final isTopNav = variant == UiPreferences.v2VariantTopNav;
    final label = isTopNav ? '上タブ (v2.1)' : 'サイドバー (v2)';
    return PopupMenuButton<String>(
      tooltip: '切替',
      onSelected: (val) =>
          UiPreferences.instance.setV2Variant(val),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: UiPreferences.v2VariantSidebar,
          checked: !isTopNav,
          child: const Text('サイドバー (v2)\nマネフォクラウド風'),
        ),
        CheckedPopupMenuItem(
          value: UiPreferences.v2VariantTopNav,
          checked: isTopNav,
          child: const Text('上タブ (v2.1)\nマネフォ ME 風'),
        ),
      ],
      child: _SelectorChip(label: label),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  final String label;
  const _SelectorChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: V2Colors.accentSoft,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: V2Typography.caption.copyWith(
                  color: V2Colors.accent,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down,
              size: 16, color: V2Colors.accent),
        ],
      ),
    );
  }
}

class _ModeIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModeManager.instance,
      builder: (_, _) {
        final isBusiness =
            AppModeManager.instance.current == AppMode.business;
        return V2Card(
          background: V2Colors.surfaceMuted,
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: V2Spacing.md),
          child: Row(
            children: [
              Icon(
                  isBusiness
                      ? Icons.business_center_outlined
                      : Icons.person_outline,
                  size: 16,
                  color: V2Colors.textSecondary),
              const SizedBox(width: V2Spacing.sm),
              Expanded(
                child: Text(
                  '現在のモード: ${isBusiness ? '事業' : '個人'}（ヘッダー右上のスイッチで切替）',
                  style: V2Typography.caption.copyWith(
                      color: V2Colors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
