import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// v2 サイドバー（マネフォクラウド寄り）。
/// 仕様:
/// - 背景はダークネイビー、テキスト白系
/// - 上部: ロゴ + アプリ名
/// - 中央: ナビ項目（hover/selected で背景ハイライト）
/// - 下部: フッター（モードスイッチ + バージョン）
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
      color: V2Colors.sidebar,
      child: Column(
        children: [
          _header(),
          if (modeSwitcher != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  V2Spacing.md, 0, V2Spacing.md, V2Spacing.sm),
              child: modeSwitcher!,
            ),
          ],
          Container(height: 1, color: V2Colors.sidebarDivider),
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
            Container(height: 1, color: V2Colors.sidebarDivider),
            footer!,
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.lg, V2Spacing.lg, V2Spacing.lg, V2Spacing.md),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            ),
            alignment: Alignment.center,
            child: const Text('財',
                style: TextStyle(
                    color: V2Colors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
          const SizedBox(width: V2Spacing.sm),
          const Text('FutaFinance',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: V2Colors.sidebarText,
                  letterSpacing: 0.2)),
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
        ? V2Colors.sidebarSelected
        : _hover
            ? V2Colors.sidebarHover
            : Colors.transparent;
    final fg = widget.selected
        ? Colors.white
        : V2Colors.sidebarText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Stack(
            children: [
              // 選択中は左に明るい青のアクセントバー（マネフォクラウド風）
              if (widget.selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: V2Colors.accent,
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusXs),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.md, vertical: 8),
                margin: const EdgeInsets.only(left: 4),
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
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.item.badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: V2Spacing.sm,
                            vertical: 1),
                        decoration: BoxDecoration(
                          color: V2Colors.sidebarHover,
                          borderRadius: BorderRadius.circular(
                              V2Spacing.radiusXs),
                        ),
                        child: Text(widget.item.badge!,
                            style: V2Typography.micro.copyWith(
                                color: V2Colors.sidebarText)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

