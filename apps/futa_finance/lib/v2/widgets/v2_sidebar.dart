import 'package:flutter/material.dart';

import '../../data/app_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// v2 サイドバー。Linear / Notion 風の左ナビ。
/// 仕様:
/// - 上部: ワークスペース識別子（アプリ名 + モードスイッチ）
/// - 中央: ナビ項目（アイコン + ラベル）
/// - 下部: 設定・バージョンなどのフッターセクション
class V2Sidebar extends StatelessWidget {
  /// ナビ項目リスト
  final List<V2NavItem> items;

  /// 現在選択中のナビ ID
  final String currentId;

  /// 選択切替時のハンドラ
  final ValueChanged<String> onSelect;

  /// 下部に置くフッターウィジェット（バージョン表示など）
  final Widget? footer;

  /// モードスイッチ（事業/個人）。null なら非表示
  final Widget? modeSwitcher;

  const V2Sidebar({
    super.key,
    required this.items,
    required this.currentId,
    required this.onSelect,
    this.footer,
    this.modeSwitcher,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: V2Spacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: V2Colors.sidebar,
        border: Border(
          right: BorderSide(color: V2Colors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          _header(),
          if (modeSwitcher != null) ...[
            const SizedBox(height: V2Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md),
              child: modeSwitcher!,
            ),
            const SizedBox(height: V2Spacing.md),
          ],
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.sm,
                  vertical: V2Spacing.md),
              children: [
                for (final item in items)
                  _NavTile(
                    item: item,
                    selected: item.id == currentId,
                    onTap: () => onSelect(item.id),
                  ),
              ],
            ),
          ),
          if (footer != null) ...[
            const Divider(),
            footer!,
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final mode = AppModeManager.instance.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.lg, V2Spacing.lg, V2Spacing.lg, V2Spacing.sm),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: mode == AppMode.business
                  ? V2Colors.accent
                  : V2Colors.accentPersonal,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            ),
            alignment: Alignment.center,
            child: const Text('財',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
          const SizedBox(width: V2Spacing.sm),
          const Text('FutaFinance',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: V2Colors.textPrimary)),
        ],
      ),
    );
  }
}

class V2NavItem {
  final String id;
  final String label;
  final IconData icon;
  final String? badge;

  const V2NavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.badge,
  });
}

class _NavTile extends StatefulWidget {
  final V2NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? V2Colors.selected
        : _hover
            ? V2Colors.hover
            : Colors.transparent;
    final fg = widget.selected
        ? V2Colors.accent
        : V2Colors.textBody;

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
                Icon(widget.item.icon, size: 16, color: fg),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: V2Typography.body.copyWith(
                      color: fg,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.item.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: V2Spacing.sm, vertical: 1),
                    decoration: BoxDecoration(
                      color: V2Colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(
                          V2Spacing.radiusXs),
                    ),
                    child: Text(widget.item.badge!,
                        style: V2Typography.micro),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
