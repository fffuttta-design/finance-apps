import 'package:flutter/material.dart';

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
class V2TopHeader extends StatelessWidget {
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

  bool get _isBusiness => mode == AppMode.business;

  /// 事業=ネイビー / 個人=白
  Color get _bg =>
      _isBusiness ? V2Colors.sidebar : V2Colors.surface;

  /// 文字色（背景に応じて反転）
  Color get _fg =>
      _isBusiness ? V2Colors.sidebarText : V2Colors.textPrimary;

  /// 境界線（ダーク背景時は同じネイビーで自然に消す）
  Color get _border => _isBusiness
      ? V2Colors.sidebarDivider
      : V2Colors.border;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _bg,
        border: Border(
          bottom: BorderSide(color: _border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.xl, vertical: V2Spacing.sm),
      child: Row(
        children: [
          _logo(),
          const SizedBox(width: V2Spacing.sm),
          Text(
            'FutaFinance',
            style: V2Typography.h2.copyWith(
                color: _fg,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2),
          ),
          const Spacer(),
          if (modeSwitcher != null) ...[
            SizedBox(width: 240, child: modeSwitcher!),
            const SizedBox(width: V2Spacing.md),
          ],
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: V2Spacing.sm),
            actions[i],
          ],
        ],
      ),
    );
  }

  Widget _logo() {
    // 事業時: 白背景にネイビーの「財」（コントラスト確保）
    // 個人時: アクセント(オレンジ)背景に白の「財」
    final bg = _isBusiness ? Colors.white : accent;
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
