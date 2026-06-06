import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/transaction_repository.dart';
import '../../screens/income_input_screen.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 ネイティブ収入タブ（マネフォクラウド寄りのテーブル中心）。
///
/// - 上部: 月切替 + 件数/合計（見込み別行）
/// - 中央: 取引一覧テーブル（日付 / カテゴリ / 内容 / 入金先 / 金額）
/// - 見込み収入は行にバッジ表示（isPending = true）
class V2IncomeScreen extends StatefulWidget {
  final Color accent;
  const V2IncomeScreen({super.key, required this.accent});

  @override
  State<V2IncomeScreen> createState() => _V2IncomeScreenState();
}

class _V2IncomeScreenState extends State<V2IncomeScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  bool _loading = true;

  late DateTime _focused =
      DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _loading = false;
    });
  }

  List<core.Transaction> get _monthIncome {
    return _transactions
        .where((t) =>
            t.type == core.TransactionType.income &&
            t.date.year == _focused.year &&
            t.date.month == _focused.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  void _shiftMonth(int delta) {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month + delta);
    });
  }

  Future<void> _openInput() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncomeInputScreen()),
    );
    if (mounted) await _load();
  }

  void _showTxnSummary(core.Transaction t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${t.date.month}/${t.date.day} ${t.description.isEmpty ? t.paymentMethod : t.description} +${formatYen(t.amount)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final all = _monthIncome;
    final confirmed = all.where((t) => !t.isPending).toList();
    final pending = all.where((t) => t.isPending).toList();
    final confirmedTotal =
        confirmed.fold<int>(0, (s, t) => s + t.amount);
    final pendingTotal =
        pending.fold<int>(0, (s, t) => s + t.amount);
    final total = confirmedTotal + pendingTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.xl, horizontal: V2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 月切替 + 集計 ─────────────────
          V2Card(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.lg, vertical: V2Spacing.md),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text('${_focused.year}年${_focused.month}月',
                    style: V2Typography.h2.copyWith(
                        color: V2Colors.textPrimary)),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () => _shiftMonth(1),
                ),
                const SizedBox(width: V2Spacing.lg),
                Text('${all.length} 件',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary)),
                if (pending.isNotEmpty) ...[
                  const SizedBox(width: V2Spacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: V2Colors.warningSoft,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('見込み ${pending.length}',
                        style: TextStyle(
                            fontSize: 10,
                            color: V2Colors.warning,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('合計',
                        style: V2Typography.micro.copyWith(
                            color: V2Colors.textSecondary)),
                    Text(formatYen(total, withSign: true),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: V2Colors.positive,
                            fontFeatures:
                                V2Typography.tabularNums)),
                    if (pendingTotal > 0)
                      Text(
                          '確定 ${formatYen(confirmedTotal, withSign: true)} / 見込み ${formatYen(pendingTotal, withSign: true)}',
                          style: V2Typography.micro.copyWith(
                              color: V2Colors.textMuted,
                              fontFeatures:
                                  V2Typography.tabularNums)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
          // ── テーブル ─────────────────
          V2Card(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.savings_outlined,
                          size: 18, color: widget.accent),
                      const SizedBox(width: V2Spacing.sm),
                      Text(isBusiness ? '売上明細' : '収入明細',
                          style: V2Typography.h2),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _openInput,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('追加'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: V2Spacing.sm),
                        Text('${_focused.month}月の収入記録なし',
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.textSecondary)),
                      ],
                    ),
                  )
                else
                  _IncomeTable(
                    rows: all,
                    onTapRow: _showTxnSummary,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// テーブル
// ═════════════════════════════════════════════════

class _IncomeTable extends StatelessWidget {
  final List<core.Transaction> rows;
  final void Function(core.Transaction t) onTapRow;
  const _IncomeTable({
    required this.rows,
    required this.onTapRow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // データ行（各行を枠付きカードで表示）
        for (final t in rows) _IncomeRow(
          t: t,
          onTap: () => onTapRow(t),
        ),
      ],
    );
  }
}

class _IncomeRow extends StatefulWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  const _IncomeRow({
    required this.t,
    required this.onTap,
  });

  @override
  State<_IncomeRow> createState() => _IncomeRowState();
}

class _IncomeRowState extends State<_IncomeRow> {
  bool _hover = false;

  String _categoryLabel() {
    final major = widget.t.category.major.trim();
    final sub = widget.t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return '未分類';
    if (sub.isEmpty) return major;
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.t.isPending;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          // たくはる風: 1 行 = 角丸枠付きの長方形カード（左右に余白）
          margin: const EdgeInsets.fromLTRB(
              V2Spacing.md, 0, V2Spacing.md, 8),
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: _hover
                ? V2Colors.hover
                : (isPending
                    ? V2Colors.warningSoft.withValues(alpha: 0.3)
                    : V2Colors.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: V2Colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 38,
                child: Text(
                    '${widget.t.date.month}/${widget.t.date.day}',
                    style: V2Typography.numericCell),
              ),
              const SizedBox(width: V2Spacing.sm),
              // 中央: 状態バッジ＋カテゴリ＋内容（受取方法は非表示）
              Expanded(
                child: Row(
                  children: [
                    // 状態（見込み/確定）バッジ
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isPending
                            ? V2Colors.warningSoft
                            : V2Colors.positiveSoft,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(isPending ? '見込み' : '確定',
                          style: TextStyle(
                              fontSize: 10,
                              color: isPending
                                  ? V2Colors.warning
                                  : V2Colors.positive,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: V2Colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(_categoryLabel(),
                          style: V2Typography.micro),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.t.description.isEmpty
                            ? '—'
                            : widget.t.description,
                        style: V2Typography.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              Text(
                '+${formatYen(widget.t.amount)}',
                style: V2Typography.numericCell.copyWith(
                    color: isPending
                        ? V2Colors.warning
                        : V2Colors.positive,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
