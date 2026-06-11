import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../widgets/v2_top_header.dart';
import '../widgets/v2_top_nav.dart';

/// マネフォ ME 風の v2.1 シェル。
///
/// レイアウト:
/// ┌────────────────────────────────┐
/// │ TopHeader (ロゴ + モード + 記録)        │
/// ├────────────────────────────────┤
/// │ TopNav (タブ：ホーム/支出/収入/...)       │
/// ├────────────────────────────────┤
/// │                                          │
/// │            Content (中央寄せ)             │
/// │            最大幅 1200px                  │
/// │                                          │
/// └────────────────────────────────┘
class V2TopNavShell extends StatefulWidget {
  final V2TopHeader header;
  final V2TopNav topNav;
  final Widget content;

  /// 中央コンテンツの最大幅。マネフォ ME はだいたい 1040px 前後
  final double maxContentWidth;

  /// モバイル（狭い画面）でナビを下部に置くときの下部ナビ。
  /// [navAtBottom] が true のとき、上タブの代わりにこれを画面下に表示する。
  final Widget? bottomNav;

  /// true のとき、タブを上ではなく下（[bottomNav]）に配置する（たくはる風）。
  final bool navAtBottom;

  const V2TopNavShell({
    super.key,
    required this.header,
    required this.topNav,
    required this.content,
    this.maxContentWidth = 1040,
    this.bottomNav,
    this.navAtBottom = false,
  });

  @override
  State<V2TopNavShell> createState() => _V2TopNavShellState();
}

class _V2TopNavShellState extends State<V2TopNavShell> {
  // コンテンツ用の主スクロールコントローラ。
  // PrimaryScrollController で各画面の縦 SingleChildScrollView に共有し、
  // 左右余白（カラム外）でホイールしても中央コンテンツをスクロールできるようにする。
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // カラム外（左右余白）のホイール操作を中央コンテンツのスクロールへ転送する。
  void _forwardWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (_scroll.offset + e.scrollDelta.dy)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (target != _scroll.offset) _scroll.jumpTo(target);
  }

  // 左右余白の透明な転送エリア。
  Widget _marginForwarder() => Expanded(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _forwardWheel,
          child: const SizedBox.expand(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      // モバイルはタブを下部に（たくはる風）。
      bottomNavigationBar: widget.navAtBottom ? widget.bottomNav : null,
      body: SafeArea(
        // 下部ナビを出すときは下端の SafeArea を bottomNav 側に任せる。
        bottom: !widget.navAtBottom,
        child: Column(
          children: [
            widget.header,
            // 上配置のときだけ上タブを出す。
            if (!widget.navAtBottom) widget.topNav,
            // スクロールは各画面側に任せる（v2.1 ネイティブ画面は内部で
            // SingleChildScrollView を持つ）。それらを下の PrimaryScrollController に
            // 共有させ、左右余白でもホイールスクロールできるようにする。
            Expanded(
              child: PrimaryScrollController(
                controller: _scroll,
                // デスクトップ含む全プラットフォームで、縦の SingleChildScrollView を
                // 自動的にこのコントローラに接続させる（既定ではデスクトップは非接続）。
                // ※ マスター/詳細など縦スクロールが同時に2つ出る画面（設定）では
                //   個別に primary:false を指定して衝突を回避している。
                automaticallyInheritForPlatforms: const {
                  TargetPlatform.android,
                  TargetPlatform.iOS,
                  TargetPlatform.fuchsia,
                  TargetPlatform.linux,
                  TargetPlatform.macOS,
                  TargetPlatform.windows,
                },
                child: LayoutBuilder(
                  builder: (context, c) {
                    // 広い画面（PC）でコンテンツ列の左右に余白があるときだけ、
                    // 「ここまでが表示エリア」が分かる縦の区切り線を入れる。
                    final showRails = c.maxWidth > widget.maxContentWidth + 1;
                    if (!showRails) {
                      // 余白なし＝そのまま全幅。
                      return Align(
                        alignment: Alignment.topCenter,
                        child: widget.content,
                      );
                    }
                    // 余白あり＝[余白(転送)｜中央コンテンツ(区切り線)｜余白(転送)]。
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _marginForwarder(),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: widget.maxContentWidth),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(color: V2Colors.border),
                                right: BorderSide(color: V2Colors.border),
                              ),
                            ),
                            child: widget.content,
                          ),
                        ),
                        _marginForwarder(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
