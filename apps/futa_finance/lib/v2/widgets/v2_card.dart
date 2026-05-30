import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';

/// v2 のベースとなるカード。罫線中心、影なし（Notion / Stripe 風）。
///
/// [hoverable] を true にすると、マウス hover で背景がほんのり変わる。
/// [onTap] を渡せば InkWell ではなく MouseRegion + GestureDetector で
/// クリック領域にする（ripple なし、デスクトップ向き）。
class V2Card extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool hoverable;
  final VoidCallback? onTap;
  final Color? background;
  final Color? borderColor;
  final double radius;

  const V2Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(V2Spacing.lg),
    this.hoverable = false,
    this.onTap,
    this.background,
    this.borderColor,
    this.radius = V2Spacing.radiusLg,
  });

  @override
  State<V2Card> createState() => _V2CardState();
}

class _V2CardState extends State<V2Card> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? V2Colors.surface;
    final hoverBg = V2Colors.surfaceMuted;
    final showHover =
        (widget.hoverable || widget.onTap != null) && _hovering;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: showHover ? hoverBg : bg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
            color: widget.borderColor ?? V2Colors.border, width: 1),
      ),
      child: widget.child,
    );

    if (widget.onTap == null && !widget.hoverable) return card;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}
