import 'package:flutter/material.dart';

import '../../data/app_mode.dart';
import '../../screens/dev_lab_screen.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 開発中タブ。
/// 上部に「実験中」バナーを置き、本体は v1 DevLabScreen をそのまま埋め込む。
/// （PL / BS / 予算管理の試作機能をいじる場所）
class V2DevLabScreen extends StatelessWidget {
  final Color accent;
  const V2DevLabScreen({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final bannerTitle = isBusiness ? '🧪 開発中ラボ' : '📥 データ取込（個人）';
    final bannerBody = isBusiness
        ? 'PL / BS / 予算管理の試作機能。事業モード専用、データは v1 と完全共有。'
        : 'コピーした明細を貼り付けて、取引をまとめて追加できます。現在の個人モードに追加されます。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              0, V2Spacing.xl, 0, V2Spacing.md),
          child: V2Card(
            background: V2Colors.warningSoft.withValues(alpha: 0.5),
            borderColor: V2Colors.warning.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(
                    isBusiness
                        ? Icons.science_outlined
                        : Icons.upload_file_outlined,
                    size: 18,
                    color: V2Colors.warning),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bannerTitle,
                          style: V2Typography.bodyStrong.copyWith(
                              color: V2Colors.textPrimary)),
                      Text(
                        bannerBody,
                        style: V2Typography.caption.copyWith(
                            color: V2Colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // v1 DevLab を埋め込み（AppBar は v2_root の _wrapV1 で潰される）
        Expanded(
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
            child: const DevLabScreen(),
          ),
        ),
      ],
    );
  }
}
