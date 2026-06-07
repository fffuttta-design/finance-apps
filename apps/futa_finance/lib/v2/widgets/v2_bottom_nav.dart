import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'v2_top_nav.dart' show V2NavItem;

/// モバイル（狭い画面）用の下部タブナビ。
/// たくはる風に「アイコン＋小さいラベル」を画面下に等幅で並べる。
/// 項目が多め（最大7）でも収まるようコンパクトに作る。
class V2BottomNav extends StatelessWidget {
  final List<V2NavItem> items;
  final String currentId;
  final ValueChanged<String> onSelect;
  final Color accent;

  const V2BottomNav({
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
        border: Border(top: BorderSide(color: V2Colors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _BottomTab(
                    item: item,
                    selected: item.id == currentId,
                    accent: accent,
                    onTap: () => onSelect(item.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  final V2NavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _BottomTab({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : V2Colors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 22, color: fg),
          const SizedBox(height: 3),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: TextStyle(
              fontSize: 10,
              height: 1.0,
              color: fg,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
