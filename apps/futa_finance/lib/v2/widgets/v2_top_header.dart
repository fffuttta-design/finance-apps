import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/app_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// マネフォ ME 風の上部ヘッダー。
///
/// 事業モード: 濃いネイビー背景 + 白文字（v2 サイドバー由来の色を流用）
/// 個人モード: 白背景 + ME 風のオレンジロゴ
///
/// このコントラストで「いま事業/個人どっちにいるか」が一目で分かる。
/// アプリ名の下にバージョン番号を小さく表示。
class V2TopHeader extends StatefulWidget {
  /// 現在のアプリモード
  final AppMode mode;

  /// アクセント色（ロゴ・記録ボタン用）
  final Color accent;

  /// 右側のアクション群
  final List<Widget> actions;

  /// モード切替 widget（segmented control）
  final Widget? modeSwitcher;

  const V2TopHeader({
    super.key,
    required this.mode,
    required this.accent,
    this.actions = const [],
    this.modeSwitcher,
  });

  @override
  State<V2TopHeader> createState() => _V2TopHeaderState();
}

class _V2TopHeaderState extends State<V2TopHeader> {
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = 'v${info.version}');
    } catch (_) {/* ignore */}
  }

  bool get _isBusiness => widget.mode == AppMode.business;

  Color get _bg =>
      _isBusiness ? V2Colors.sidebar : V2Colors.surface;

  Color get _fg =>
      _isBusiness ? V2Colors.sidebarText : V2Colors.textPrimary;

  Color get _versionFg => _isBusiness
      ? V2Colors.sidebarTextMuted
      : V2Colors.textMuted;

  Color get _border =>
      _isBusiness ? V2Colors.sidebarDivider : V2Colors.border;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // 狭い画面（スマホ）はアプリ名/バージョンを省略し、モード切替を可変幅にして
      // 記録ボタンまで収まるようにする（横幅オーバーで見切れるのを防ぐ）。
      final narrow = c.maxWidth < 600;
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: _bg,
          border: Border(
            bottom: BorderSide(color: _border, width: 1),
          ),
        ),
        padding: EdgeInsets.symmetric(
            horizontal: narrow ? V2Spacing.md : V2Spacing.xl,
            vertical: V2Spacing.xs),
        child: Row(
          children: [
            _logo(),
            if (!narrow) ...[
              const SizedBox(width: V2Spacing.sm),
              // アプリ名 + バージョン（2 行）
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'FutaFinance',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.1,
                      color: _fg,
                    ),
                  ),
                  if (_versionLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _versionLabel!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        color: _versionFg,
                        fontFeatures: V2Typography.tabularNums,
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              if (widget.modeSwitcher != null) ...[
                SizedBox(width: 240, child: widget.modeSwitcher!),
                const SizedBox(width: V2Spacing.md),
              ],
            ] else ...[
              const SizedBox(width: V2Spacing.sm),
              if (widget.modeSwitcher != null) ...[
                Expanded(child: widget.modeSwitcher!),
                const SizedBox(width: V2Spacing.sm),
              ] else
                const Spacer(),
            ],
            for (var i = 0; i < widget.actions.length; i++) ...[
              if (i > 0) const SizedBox(width: V2Spacing.sm),
              widget.actions[i],
            ],
          ],
        ),
      );
    });
  }

  Widget _logo() {
    // 事業時: 白背景にネイビーの「財」（コントラスト確保）
    // 個人時: アクセント(オレンジ)背景に白の「財」
    final bg = _isBusiness ? Colors.white : widget.accent;
    final fg = _isBusiness ? V2Colors.sidebar : Colors.white;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
      ),
      alignment: Alignment.center,
      child: Text('財',
          style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 15)),
    );
  }
}
