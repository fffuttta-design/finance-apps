import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'v2_sidebar.dart' show V2NavItem;

/// マネフォ ME 風の上タブナビ。
/// 白背景 + 横並びタブ + 選択中タブの下にアクセント色のアンダーラインバー。
class V2TopNav extends StatelessWidget {
  /// タブ項目
  final List<V2NavItem> items;

  /// 現在選択中のタブ ID
  final String currentId;

  /// 選択切替
  final ValueChanged<String> onSelect;

  /// アクセント色（事業=青、個人=オレンジ）
  final Color accent;

  const V2TopNav({
    super.key,
    required this.items,
    required this.currentId,
    required this.onSelect,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: V2Colors.surface,
        border: Border(
          bottom: BorderSide(color: V2Colors.border, width: 1),
        ),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: V2Spacing.xl),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _Tab(
                item: item,
                selected: item.id == currentId,
                accent: accent,
                onTap: () => onSelect(item.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  final V2NavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _Tab({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected
        ? widget.accent
        : (_hover ? V2Colors.textPrimary : V2Colors.textBody);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 52,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.lg),
                child: Center(
                  child: Row(
                    children: [
                      Icon(widget.item.icon, size: 16, color: fg),
                      const SizedBox(width: V2Spacing.sm),
                      Text(
                        widget.item.label,
                        style: V2Typography.bodyStrong.copyWith(
                          color: fg,
                          fontWeight: widget.selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 選択中タブの下のアクセントバー
              if (widget.selected)
                Positioned(
                  left: V2Spacing.md,
                  right: V2Spacing.md,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
