import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_top_nav.dart' show V2NavItem;

/// 新デザイン（リッチUI）の PC 向けシェル。
///
/// 左にサイドバー（ナビ＋記録ボタン）、右上に細いトップバー（タイトル＋モード切替）、
/// その下に各タブの本文を配置する。狭い画面（スマホ）では使わず、
/// 従来どおり下タブのシェルを使う（呼び出し側で出し分け）。
class RichSidebarShell extends StatefulWidget {
  final List<V2NavItem> items;
  final String currentId;
  final void Function(String id) onSelect;
  final Color accent;

  /// 個人モードかどうか（true ならサイドバーをオレンジ基調にする）。
  final bool personal;

  /// トップバー左に出す現在タブのタイトル。
  final String title;

  /// トップバー右に置くモード切替ウィジェット。
  final Widget modeSwitcher;

  /// トップバー中央に置く共有の月ナビ（月を使わないタブでは null）。
  final Widget? monthNav;

  /// サイドバー下部に置く「記録」ボタン。
  final Widget recordButton;

  /// 本文（各タブ画面）。
  final Widget content;

  const RichSidebarShell({
    super.key,
    required this.items,
    required this.currentId,
    required this.onSelect,
    required this.accent,
    this.personal = false,
    required this.title,
    required this.modeSwitcher,
    this.monthNav,
    required this.recordButton,
    required this.content,
  });

  @override
  State<RichSidebarShell> createState() => _RichSidebarShellState();
}

class _RichSidebarShellState extends State<RichSidebarShell> {
  /// サイドバーの開閉。トップバー左の ☰ で切替える。
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final personal = widget.personal;
    // 個人モードはオレンジ基調、事業モードは従来のネイビー。
    final sidebarBg =
        personal ? V2Colors.sidebarPersonal : V2Colors.sidebar;
    final sidebarText =
        personal ? V2Colors.sidebarPersonalText : V2Colors.sidebarText;
    final sidebarMuted = personal
        ? V2Colors.sidebarPersonalTextMuted
        : V2Colors.sidebarTextMuted;
    final sidebarHover =
        personal ? V2Colors.sidebarPersonalHover : V2Colors.sidebarHover;
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── サイドバー（開いているときだけ表示。☰で開閉） ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              width: _open ? V2Spacing.sidebarWidth : 0,
              color: sidebarBg,
              clipBehavior: Clip.hardEdge,
              child: OverflowBox(
                minWidth: V2Spacing.sidebarWidth,
                maxWidth: V2Spacing.sidebarWidth,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // ブランド
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('ふ',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Text('Finance',
                            style: TextStyle(
                                color: sidebarText,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  // ナビ
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      children: [
                        for (final it in widget.items)
                          _SidebarItem(
                            item: it,
                            selected: it.id == widget.currentId,
                            accent: accent,
                            mutedColor: sidebarMuted,
                            hoverColor: sidebarHover,
                            personal: personal,
                            onTap: () => widget.onSelect(it.id),
                          ),
                      ],
                    ),
                  ),
                  // 記録ボタンはトップバー右上へ移設（サイドバー下部からは撤去）。
                  const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            // ── メイン ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // トップバー
                  Container(
                    height: V2Spacing.topbarHeight,
                    decoration: const BoxDecoration(
                      color: V2Colors.topbar,
                      border: Border(
                          bottom: BorderSide(color: V2Colors.border)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        // サイドバー開閉ボタン。
                        IconButton(
                          icon: Icon(_open ? Icons.menu_open : Icons.menu),
                          color: V2Colors.textSecondary,
                          tooltip: _open ? 'サイドバーを閉じる' : 'サイドバーを開く',
                          onPressed: () => setState(() => _open = !_open),
                        ),
                        const SizedBox(width: 4),
                        Text(widget.title,
                            style: V2Typography.h1
                                .copyWith(color: V2Colors.textPrimary)),
                        // 共有の月ナビを中央に。月を使わないタブでは出さない。
                        Expanded(
                          child: Center(
                            child: widget.monthNav ?? const SizedBox.shrink(),
                          ),
                        ),
                        // モード切替（事業/個人）→ 記録ボタンの順で右上に並べる。
                        // セグメントが潰れないよう十分な幅を確保する。
                        SizedBox(width: 168, child: widget.modeSwitcher),
                        const SizedBox(width: 12),
                        widget.recordButton,
                      ],
                    ),
                  ),
                  // 本文は中央寄せ（最大幅）にする。資産タブ/PL/設定など
                  // 自前で中央寄せしない画面が横に引き伸ばされるのを防ぐ。
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 1140),
                        child: widget.content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final V2NavItem item;
  final bool selected;
  final Color accent;
  final Color mutedColor;
  final Color hoverColor;
  final bool personal;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.accent,
    required this.mutedColor,
    required this.hoverColor,
    required this.personal,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // 個人モード（オレンジ地）は選択ハイライトをやや強めにして視認性を確保。
    final bg = selected
        ? widget.accent.withValues(alpha: widget.personal ? 0.42 : 0.22)
        : (_hover ? widget.hoverColor : Colors.transparent);
    final fg = selected ? Colors.white : widget.mutedColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Icon(widget.item.icon, size: 18, color: fg),
                const SizedBox(width: 11),
                Text(widget.item.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
