import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// マネフォ ME 風のホーム placeholder（v2.1）。
/// 3 カラム構成:
/// - 左: 総資産サマリー
/// - 中央: カンタン入力 + 最新入出金 + 月の収支
/// - 右: お知らせ / コラム枠（うちは将来用、今は予算進捗）
///
/// 実データ連携は Phase 1 で。
class V2HomeTopNavScreen extends StatelessWidget {
  /// アクセント色（事業=青、個人=オレンジ）
  final Color accent;

  const V2HomeTopNavScreen({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 1024;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左: 総資産（固定幅）
            SizedBox(width: 240, child: _LeftAssetSummary(accent: accent)),
            const SizedBox(width: V2Spacing.lg),
            // 中央: メインコンテンツ
            Expanded(child: _CenterColumn(accent: accent)),
            const SizedBox(width: V2Spacing.lg),
            // 右: お知らせ枠（固定幅）
            SizedBox(width: 280, child: _RightSidebar()),
          ],
        );
      }
      // 狭い時は中央のみ縦並び
      return Column(
        children: [
          _LeftAssetSummary(accent: accent),
          const SizedBox(height: V2Spacing.lg),
          _CenterColumn(accent: accent),
        ],
      );
    });
  }
}

class _LeftAssetSummary extends StatelessWidget {
  final Color accent;
  const _LeftAssetSummary({required this.accent});

  @override
  Widget build(BuildContext context) {
    return V2Card(
      padding: const EdgeInsets.all(V2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('総資産',
              style: V2Typography.bodyStrong.copyWith(
                  color: V2Colors.textPrimary, fontSize: 13)),
          const SizedBox(height: V2Spacing.md),
          Text('¥7,798,727',
              style: V2Typography.kpiValue.copyWith(
                  color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.sm),
          Row(
            children: [
              Icon(Icons.trending_up,
                  size: 14, color: V2Colors.positive),
              const SizedBox(width: 4),
              Text('+¥200,000',
                  style: V2Typography.caption.copyWith(
                      color: V2Colors.positive,
                      fontWeight: FontWeight.w700,
                      fontFeatures: V2Typography.tabularNums)),
              const SizedBox(width: V2Spacing.xs),
              Text('前月末比',
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textSecondary)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: V2Spacing.md),
            child: Divider(),
          ),
          _AssetTile(
              label: '住信SBIネット銀行',
              value: '¥7,283,944',
              color: V2Colors.badgeBlue),
          _AssetTile(
              label: '三井住友銀行',
              value: '¥514,783',
              color: V2Colors.badgeBlue),
          _AssetTile(
              label: '三井住友カード',
              value: '-¥86,033',
              color: V2Colors.negative),
          const SizedBox(height: V2Spacing.sm),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('口座を追加'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _AssetTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: V2Spacing.sm),
          Expanded(
            child: Text(label,
                style: V2Typography.caption,
                overflow: TextOverflow.ellipsis),
          ),
          Text(value,
              style: V2Typography.caption.copyWith(
                  color: V2Colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _CenterColumn extends StatelessWidget {
  final Color accent;
  const _CenterColumn({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // カンタン入力（ME の目玉機能）
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 18, color: accent),
                  const SizedBox(width: V2Spacing.sm),
                  Text('カンタン入力',
                      style: V2Typography.h2.copyWith(
                          color: V2Colors.textPrimary)),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              Row(
                children: [
                  _CategoryChip(
                      label: '支出',
                      color: V2Colors.negative,
                      bg: V2Colors.negativeSoft),
                  const SizedBox(width: V2Spacing.sm),
                  _CategoryChip(
                      label: '未分類',
                      color: V2Colors.textSecondary,
                      bg: V2Colors.surfaceMuted),
                  const SizedBox(width: V2Spacing.lg),
                  Text('日付',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary)),
                  const SizedBox(width: V2Spacing.sm),
                  Text('2026/05/30',
                      style: V2Typography.body.copyWith(
                          fontFeatures: V2Typography.tabularNums)),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: '金額を入力してください',
                  suffixText: '円',
                  suffixStyle: V2Typography.body,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: V2Spacing.sm),
              TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: '内容を入力してください（任意）',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: V2Spacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor:
                        accent.withValues(alpha: 0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('保存する'),
                ),
              ),
              const SizedBox(height: V2Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.add_circle_outline,
                      size: 14, color: accent),
                  label: Text('収入・振替を入力する',
                      style: V2Typography.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        // 最新の入出金
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('最新の入出金',
                      style: V2Typography.h2.copyWith(
                          color: V2Colors.textPrimary)),
                  const Spacer(),
                  Text('履歴の詳細を見る',
                      style: V2Typography.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: V2Spacing.xs),
                  Icon(Icons.chevron_right, size: 14, color: accent),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              const _TransactionRow(
                  date: '5/30',
                  category: '通信費',
                  desc: 'gigafile便',
                  amount: '-¥198',
                  color: V2Colors.negative),
              const _TransactionRow(
                  date: '5/28',
                  category: '事業売上',
                  desc: 'クライアントA',
                  amount: '+¥200,000',
                  color: V2Colors.positive),
              const _TransactionRow(
                  date: '5/25',
                  category: '家賃',
                  desc: '銀行引落',
                  amount: '-¥105,000',
                  color: V2Colors.negative),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        // 5 月の収支
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('5月の収支',
                      style: V2Typography.h2.copyWith(
                          color: V2Colors.textPrimary)),
                  const SizedBox(width: V2Spacing.sm),
                  Text('(2026-05-01 〜 2026-05-31)',
                      style: V2Typography.caption),
                ],
              ),
              const SizedBox(height: V2Spacing.md),
              _SummaryRow(
                  label: '当月収入', value: '¥200,000', color: V2Colors.positive),
              const Divider(height: 1),
              _SummaryRow(
                  label: '当月支出', value: '-¥124,533', color: V2Colors.negative),
              const Divider(height: 1),
              _SummaryRow(
                  label: '当月収支',
                  value: '+¥75,467',
                  color: V2Colors.positive,
                  emphasize: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _CategoryChip(
      {required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: V2Typography.caption.copyWith(
                  color: color, fontWeight: FontWeight.w700)),
          const SizedBox(width: V2Spacing.xs),
          Icon(Icons.arrow_drop_down, size: 16, color: color),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final String date;
  final String category;
  final String desc;
  final String amount;
  final Color color;
  const _TransactionRow({
    required this.date,
    required this.category,
    required this.desc,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: V2Colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(date,
                  style: V2Typography.caption.copyWith(
                      fontFeatures: V2Typography.tabularNums))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: V2Colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V2Spacing.radiusXs),
            ),
            child:
                Text(category, style: V2Typography.micro),
          ),
          const SizedBox(width: V2Spacing.md),
          Expanded(
            child: Text(desc,
                style: V2Typography.body,
                overflow: TextOverflow.ellipsis),
          ),
          Text(amount,
              style: V2Typography.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool emphasize;
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(label,
              style: emphasize
                  ? V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 14)
                  : V2Typography.body),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontSize: emphasize ? 20 : 16,
                fontWeight:
                    emphasize ? FontWeight.w800 : FontWeight.w700,
                color: color,
                fontFeatures: V2Typography.tabularNums,
              )),
        ],
      ),
    );
  }
}

class _RightSidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今月の予算',
                  style: V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 13)),
              const SizedBox(height: V2Spacing.md),
              const _BudgetBar(
                  label: '食費',
                  used: 28000,
                  total: 40000,
                  color: V2Colors.badgeBlue),
              const SizedBox(height: V2Spacing.sm),
              const _BudgetBar(
                  label: '交通費',
                  used: 8500,
                  total: 12000,
                  color: V2Colors.badgeGreen),
              const SizedBox(height: V2Spacing.sm),
              const _BudgetBar(
                  label: '娯楽',
                  used: 15000,
                  total: 10000,
                  color: V2Colors.badgeRed),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.lg),
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('お知らせ',
                  style: V2Typography.bodyStrong.copyWith(
                      color: V2Colors.textPrimary, fontSize: 13)),
              const SizedBox(height: V2Spacing.sm),
              Text(
                  'Phase 1 で実データ連携実装予定。\n'
                  'カンタン入力もここで完結予定。',
                  style: V2Typography.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetBar extends StatelessWidget {
  final String label;
  final int used;
  final int total;
  final Color color;
  const _BudgetBar({
    required this.label,
    required this.used,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (used / total).clamp(0.0, 1.0);
    final over = used > total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: V2Typography.caption),
            const Spacer(),
            Text(
              '¥${_fmt(used)} / ¥${_fmt(total)}',
              style: V2Typography.micro.copyWith(
                  color: over
                      ? V2Colors.negative
                      : V2Colors.textSecondary,
                  fontFeatures: V2Typography.tabularNums),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: V2Colors.surfaceMuted,
            valueColor:
                AlwaysStoppedAnimation(over ? V2Colors.negative : color),
          ),
        ),
      ],
    );
  }

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
