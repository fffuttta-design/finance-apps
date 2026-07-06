import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter/material.dart';

import '../../data/month_closing_repository.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 月末締めの状態バー（締め処理完了・可逆）。支出/収入タブ・ホームで共通利用。
///
/// - [compact]=false: 未締めなら「N月を締める」ボタン、締め済なら完了バナー＋取り消し。
/// - [compact]=true : 締め済のときだけ小さな「✓ 締め済」バッジ（ホーム向け・読み取り専用）。
class MonthClosingBar extends StatefulWidget {
  final DateTime month;

  /// 締め時に記録するスナップショット（任意）。
  final int? snapshotExpense;
  final int? snapshotIncome;

  /// コンパクト表示（ホーム用・締め済バッジのみ）。
  final bool compact;

  /// 小さい操作チップ（タブ右上用）。未締め→「締める」、締め済→「締め済・取消」。
  final bool dense;

  /// 締め/取消の直後に呼ばれる（呼び元でグレーアウト等を更新するため）。
  final VoidCallback? onChanged;

  /// 全体締めの前に「締め済みであるべきウォレット」。未締めがあるうちは締めさせず
  /// アラートを出す（支出タブの全体締め用）。key=複合キー(w:/card:) / label=表示名。
  final List<({String key, String label})>? walletsToClose;

  const MonthClosingBar({
    super.key,
    required this.month,
    this.snapshotExpense,
    this.snapshotIncome,
    this.compact = false,
    this.dense = false,
    this.onChanged,
    this.walletsToClose,
  });

  @override
  State<MonthClosingBar> createState() => _MonthClosingBarState();
}

class _MonthClosingBarState extends State<MonthClosingBar> {
  core.MonthClosingConfig _cfg = core.MonthClosingConfig.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MonthClosingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) _load();
  }

  Future<void> _load() async {
    final c = await MonthClosingRepository.instance.load();
    if (mounted) setState(() => _cfg = c);
  }

  core.MonthClosing? get _closing =>
      _cfg.forMonth(widget.month.year, widget.month.month);

  Future<void> _close() async {
    // まだ締めていないウォレットがあれば、全体締めをブロックしてアラート。
    final pending = (widget.walletsToClose ?? const [])
        .where((w) =>
            !_cfg.closings.any((c) => c.yearMonth == w.key && c.isClosed))
        .map((w) => w.label)
        .toList();
    if (pending.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('まだ締めていないウォレットがあります'),
          content: Text(
              '${widget.month.month}月の全体を締める前に、次のウォレットを先に締めてください：\n\n'
              '・${pending.join('\n・')}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final key =
        core.MonthClosing.monthKey(widget.month.year, widget.month.month);
    final existing = _closing ?? core.MonthClosing(yearMonth: key);
    final cfg = _cfg.upsert(existing.copyWith(
      closedAt: DateTime.now(),
      closedTotalExpense: widget.snapshotExpense,
      closedTotalIncome: widget.snapshotIncome,
    ));
    await MonthClosingRepository.instance.save(cfg);
    if (mounted) setState(() => _cfg = cfg);
    widget.onChanged?.call();
  }

  Future<void> _reopen() async {
    final existing = _closing;
    if (existing == null) return;
    final cfg = _cfg.upsert(existing.copyWith(clearClosedAt: true));
    await MonthClosingRepository.instance.save(cfg);
    if (mounted) setState(() => _cfg = cfg);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final closing = _closing;
    final isClosed = closing?.isClosed ?? false;

    // ホーム等のコンパクト表示：締め済の時だけバッジ。
    if (widget.compact) {
      if (!isClosed) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: V2Colors.positive.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle,
                size: 13, color: V2Colors.positive),
            const SizedBox(width: 3),
            Text('${widget.month.month}月 締め済',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: V2Colors.positive)),
          ],
        ),
      );
    }

    // タブ右上用の小さい操作チップ。
    if (widget.dense) {
      if (isClosed) {
        return InkWell(
          onTap: _reopen,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: V2Colors.positive.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 14, color: V2Colors.positive),
                const SizedBox(width: 4),
                Text('${widget.month.month}月 締め済',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: V2Colors.positive)),
                const SizedBox(width: 6),
                Text('取消',
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textMuted)),
              ],
            ),
          ),
        );
      }
      return InkWell(
        onTap: _close,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: V2Colors.positive),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.task_alt, size: 15, color: V2Colors.positive),
              const SizedBox(width: 5),
              Text('${widget.month.month}月を締める',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.positive)),
            ],
          ),
        ),
      );
    }

    if (isClosed) {
      final d = closing!.closedAt!;
      final stamp =
          '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.md, vertical: V2Spacing.sm),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: V2Colors.positive),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 20, color: V2Colors.positive),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.month.month}月は締め処理完了',
                      style: V2Typography.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF166534))),
                  Text('$stamp に締め・もう編集の必要はありません',
                      style: V2Typography.micro
                          .copyWith(color: const Color(0xFF166534))),
                ],
              ),
            ),
            TextButton(
              onPressed: _reopen,
              child: const Text('締めを取り消す', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _close,
        icon: const Icon(Icons.task_alt, size: 18),
        label: Text('${widget.month.month}月を締める（締め処理完了）'),
        style: OutlinedButton.styleFrom(
          foregroundColor: V2Colors.positive,
          side: const BorderSide(color: V2Colors.positive),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
