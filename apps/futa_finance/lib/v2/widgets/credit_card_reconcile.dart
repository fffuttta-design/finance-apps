import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/modal_input.dart';
import '../../utils/thousands_separator_input_formatter.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

// ═════════════════════════════════════════════════
// クレカ引落照合セクション + 棚卸しシート（共有）
//
// モバイル幅(v2_expenses)とリッチUI(rich_expenses)の両方から使う。
// ═════════════════════════════════════════════════

/// クレカごとに「予定金額（明細合計）vs 実際金額（手入力）」を並べ、差分で棚卸しを促す。
/// 行をタップすると棚卸しシート（明細確認＋差額の調整）が開く。
class CreditCardBillingSection extends StatelessWidget {
  final List<core.RegisteredCreditCard> cards;
  final List<core.Transaction> transactions;
  final String ym;

  /// 行タップ → 棚卸しシートを開く。
  final void Function(core.RegisteredCreditCard card) onOpenReconcile;

  const CreditCardBillingSection({
    super.key,
    required this.cards,
    required this.transactions,
    required this.ym,
    required this.onOpenReconcile,
  });

  /// 当月・当カードの明細合計（予定金額）。
  int _planned(core.RegisteredCreditCard card) {
    final parts = ym.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == card.name &&
            t.date.year == year &&
            t.date.month == month)
        .fold(0, (s, t) => s + t.amount);
  }

  /// セクションに表示するカード（当月明細あり or 実際金額入力済み）。
  List<core.RegisteredCreditCard> get _visibleCards {
    return cards.where((c) {
      return _planned(c) > 0 || c.monthlyActualBillings.containsKey(ym);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleCards;
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: V2Spacing.sm),
          child: Row(
            children: [
              const Icon(Icons.credit_card, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: V2Spacing.sm),
              Text('クレカ引落照合',
                  style: V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: V2Colors.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: V2Colors.divider),
                _BillingRow(
                  card: visible[i],
                  planned: _planned(visible[i]),
                  actual: visible[i].monthlyActualBillings[ym],
                  onOpenReconcile: onOpenReconcile,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// クレカ引落の棚卸しシートを開く。
///
/// [onSaveActual] 実際請求額の保存（null でクリア）。
/// [onEditTxn] / [onDeleteTxn] 明細の編集・削除。
/// [onAddAdjustment] 差額ぶんの調整取引を追加。
Future<void> showCardReconcileSheet(
  BuildContext context, {
  required core.RegisteredCreditCard card,
  required String ym,
  required Future<void> Function(int? amount) onSaveActual,
  required Future<void> Function(core.Transaction t) onEditTxn,
  required Future<void> Function(core.Transaction t) onDeleteTxn,
  required Future<void> Function(int amount) onAddAdjustment,
}) async {
  await showInputSheet<bool>(
    context,
    _CardReconcileSheet(
      card: card,
      ym: ym,
      onSaveActual: onSaveActual,
      onEditTxn: onEditTxn,
      onDeleteTxn: onDeleteTxn,
      onAddAdjustment: onAddAdjustment,
    ),
  );
}

class _BillingRow extends StatelessWidget {
  final core.RegisteredCreditCard card;
  final int planned;
  final int? actual;

  /// 行タップ → 棚卸しシートを開く。
  final void Function(core.RegisteredCreditCard card) onOpenReconcile;

  const _BillingRow({
    required this.card,
    required this.planned,
    required this.actual,
    required this.onOpenReconcile,
  });

  @override
  Widget build(BuildContext context) {
    final diff = actual != null ? actual! - planned : null;
    final hasActual = actual != null && actual! > 0;

    // 差分の色・ラベル
    Color diffColor;
    String diffLabel;
    if (diff == null) {
      diffColor = V2Colors.textMuted;
      diffLabel = '未入力';
    } else if (diff == 0) {
      diffColor = V2Colors.positive;
      diffLabel = '一致';
    } else if (diff > 0) {
      diffColor = V2Colors.negative;
      diffLabel = '+${formatYen(diff)} 超過';
    } else {
      diffColor = V2Colors.warning;
      diffLabel = '${formatYen(diff)} 未確認';
    }

    final isOver = diff != null && diff > 0;

    return InkWell(
      onTap: () => onOpenReconcile(card),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: V2Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // カード名行
            Row(
              children: [
                BrandLogo(
                  iconUrl: card.iconUrl,
                  fallbackEmoji: '💳',
                  size: 20,
                  borderRadius: 3,
                ),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.name,
                          style: V2Typography.body
                              .copyWith(fontWeight: FontWeight.w700)),
                      if (card.paymentDay != null)
                        Text('引き落とし日：毎月${card.paymentDay}日',
                            style: V2Typography.micro
                                .copyWith(color: V2Colors.textMuted)),
                    ],
                  ),
                ),
                // 差分バッジ
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: diffColor.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(diffLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: diffColor)),
                ),
                const SizedBox(width: V2Spacing.xs),
                const Icon(Icons.chevron_right,
                    size: 18, color: V2Colors.textMuted),
              ],
            ),
            const SizedBox(height: V2Spacing.sm),
            // 予定 / 実際 の2列（同一スタイル）
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 予定金額（自動）
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: V2Colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: V2Colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('予定（明細合計）',
                              style: V2Typography.micro
                                  .copyWith(color: V2Colors.textMuted)),
                          const SizedBox(height: 4),
                          Text(formatYen(planned),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: planned > 0
                                      ? V2Colors.textPrimary
                                      : V2Colors.textMuted,
                                  fontFeatures: V2Typography.tabularNums)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: V2Spacing.sm),
                  // 実際金額（タップで棚卸しシートを開いて入力）
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: hasActual
                            ? const Color(0xFFFEF2F2)
                            : V2Colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: hasActual
                                ? const Color(0xFFDC2626).withValues(alpha: 0.4)
                                : V2Colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('実際（カード通知）',
                                style: V2Typography.micro
                                    .copyWith(color: V2Colors.textMuted)),
                            const SizedBox(width: 3),
                            const Icon(Icons.edit,
                                size: 11, color: V2Colors.textMuted),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            hasActual ? formatYen(actual!) : '未入力',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: hasActual
                                    ? const Color(0xFFDC2626)
                                    : V2Colors.textMuted,
                                fontFeatures: V2Typography.tabularNums),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 超過警告バナー
            if (isOver) ...[
              const SizedBox(height: V2Spacing.sm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded,
                        size: 20, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '明細合計より ${formatYen(diff)} 多く請求されています！未記録の支出がある可能性があります。',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// クレカ引落の棚卸しシート
// ═════════════════════════════════════════════════

/// 1枚のクレカについて「予定（明細合計）vs 実際（手入力）」の差額を棚卸しする。
/// - そのカード払いの当月明細を一覧（タップで編集／削除）
/// - 実際請求額を入力
/// - 差額ぶんを「調整取引」としてその場で追加（記録漏れ補完）
class _CardReconcileSheet extends StatefulWidget {
  final core.RegisteredCreditCard card;
  final String ym;

  /// 実際請求額を保存（null でクリア）。
  final Future<void> Function(int? amount) onSaveActual;

  /// 明細行タップ → 取引を編集。
  final Future<void> Function(core.Transaction t) onEditTxn;

  /// 明細行 → 取引を削除。
  final Future<void> Function(core.Transaction t) onDeleteTxn;

  /// 差額ぶんの調整取引を追加。
  final Future<void> Function(int amount) onAddAdjustment;

  const _CardReconcileSheet({
    required this.card,
    required this.ym,
    required this.onSaveActual,
    required this.onEditTxn,
    required this.onDeleteTxn,
    required this.onAddAdjustment,
  });

  @override
  State<_CardReconcileSheet> createState() => _CardReconcileSheetState();
}

class _CardReconcileSheetState extends State<_CardReconcileSheet> {
  final _txRepo = TransactionRepository.instance;
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];
  int? _actual;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _actual = widget.card.monthlyActualBillings[widget.ym];
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _all = list);
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
      _all = txns;
      _loading = false;
    });
  }

  int get _year => int.parse(widget.ym.split('-')[0]);
  int get _month => int.parse(widget.ym.split('-')[1]);

  /// 当月・当カード払いの明細（新しい順）。
  List<core.Transaction> get _cardTxns {
    return _all
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == widget.card.name &&
            t.date.year == _year &&
            t.date.month == _month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  int get _planned => _cardTxns.fold(0, (s, t) => s + t.amount);

  /// 実際請求額を入力。
  Future<void> _inputActual() async {
    final ctrl = NoComposingUnderlineController(
        text: _actual != null && _actual! > 0 ? formatAmount(_actual!) : '');
    int? result;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${widget.card.name}の実際請求額'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('予定（明細合計）: ${formatYen(_planned)}',
                style: const TextStyle(
                    fontSize: 12, color: V2Colors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [
                HalfWidthDigitsFormatter(),
                ThousandsSeparatorInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'カード会社通知の請求額（円）',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () {
                result = -1; // クリア
                Navigator.pop(context);
              },
              child: const Text('クリア')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                result = parseAmount(ctrl.text) ?? 0;
                Navigator.pop(context);
              },
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    final amount = result! <= 0 ? null : result;
    await widget.onSaveActual(amount);
    if (mounted) setState(() => _actual = amount);
  }

  @override
  Widget build(BuildContext context) {
    final txns = _cardTxns;
    final planned = _planned;
    final actual = _actual;
    final diff = actual != null ? actual - planned : null;

    Color diffColor;
    String diffLabel;
    if (diff == null) {
      diffColor = V2Colors.textMuted;
      diffLabel = '実際額 未入力';
    } else if (diff == 0) {
      diffColor = V2Colors.positive;
      diffLabel = '一致';
    } else if (diff > 0) {
      diffColor = V2Colors.negative;
      diffLabel = '+${formatYen(diff)}';
    } else {
      diffColor = V2Colors.warning;
      diffLabel = formatYen(diff);
    }

    return Scaffold(
      backgroundColor: V2Colors.surface,
      appBar: AppBar(
        backgroundColor: V2Colors.surface,
        elevation: 0,
        title: Text('クレカ棚卸し（$_month月）',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(V2Spacing.lg),
              children: [
                Row(
                  children: [
                    BrandLogo(
                      iconUrl: widget.card.iconUrl,
                      fallbackEmoji: '💳',
                      size: 24,
                      borderRadius: 4,
                    ),
                    const SizedBox(width: V2Spacing.sm),
                    Expanded(
                        child:
                            Text(widget.card.name, style: V2Typography.h2)),
                  ],
                ),
                const SizedBox(height: V2Spacing.md),
                _SummaryBox(
                  planned: planned,
                  actual: actual,
                  diff: diff,
                  diffColor: diffColor,
                  diffLabel: diffLabel,
                  onInputActual: _inputActual,
                ),
                const SizedBox(height: V2Spacing.lg),
                if (diff != null && diff > 0)
                  _AdjustmentPrompt(
                    amount: diff,
                    onAdd: () => widget.onAddAdjustment(diff),
                  )
                else if (diff != null && diff < 0)
                  Container(
                    padding: const EdgeInsets.all(V2Spacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: V2Colors.warning, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 20, color: V2Colors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '明細合計が実際請求より ${formatYen(-diff)} 多いです。'
                            '二重計上や取消済みの可能性があります。'
                            '下の明細から余分な記録を削除・修正してください。',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (diff == 0)
                  Container(
                    padding: const EdgeInsets.all(V2Spacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: V2Colors.positive, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 20, color: V2Colors.positive),
                        const SizedBox(width: 8),
                        Text('明細合計と実際請求が一致しています。',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: V2Colors.positive)),
                      ],
                    ),
                  ),
                const SizedBox(height: V2Spacing.lg),
                Row(
                  children: [
                    Text('このカードの$_month月明細', style: V2Typography.h2),
                    const Spacer(),
                    Text('${txns.length}件 / ${formatYen(planned)}',
                        style: V2Typography.caption
                            .copyWith(color: V2Colors.textSecondary)),
                  ],
                ),
                const SizedBox(height: V2Spacing.sm),
                if (txns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('明細なし',
                          style: V2Typography.caption
                              .copyWith(color: V2Colors.textMuted)),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: V2Colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: V2Colors.border),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < txns.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1, color: V2Colors.divider),
                          _ReconcileTxnRow(
                            txn: txns[i],
                            onEdit: () => widget.onEditTxn(txns[i]),
                            onDelete: () => widget.onDeleteTxn(txns[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: V2Spacing.xl),
              ],
            ),
    );
  }
}

/// 予定 / 実際 / 差額のサマリーボックス。
class _SummaryBox extends StatelessWidget {
  final int planned;
  final int? actual;
  final int? diff;
  final Color diffColor;
  final String diffLabel;
  final VoidCallback onInputActual;

  const _SummaryBox({
    required this.planned,
    required this.actual,
    required this.diff,
    required this.diffColor,
    required this.diffLabel,
    required this.onInputActual,
  });

  @override
  Widget build(BuildContext context) {
    final hasActual = actual != null && actual! > 0;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('予定（明細合計）',
                          style: V2Typography.micro
                              .copyWith(color: V2Colors.textMuted)),
                      const SizedBox(height: 4),
                      Text(formatYen(planned),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: planned > 0
                                  ? V2Colors.textPrimary
                                  : V2Colors.textMuted,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
                const VerticalDivider(width: V2Spacing.lg),
                Expanded(
                  child: GestureDetector(
                    onTap: onInputActual,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('実際（カード通知）',
                              style: V2Typography.micro
                                  .copyWith(color: V2Colors.textMuted)),
                          const SizedBox(width: 3),
                          const Icon(Icons.edit,
                              size: 12, color: V2Colors.textMuted),
                        ]),
                        const SizedBox(height: 4),
                        Text(hasActual ? formatYen(actual!) : '入力する',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: hasActual
                                    ? const Color(0xFFDC2626)
                                    : V2Colors.textMuted,
                                fontFeatures: V2Typography.tabularNums)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.md),
          const Divider(height: 1, color: V2Colors.divider),
          const SizedBox(height: V2Spacing.md),
          Row(
            children: [
              Text('差額',
                  style: V2Typography.body
                      .copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: diffColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: diffColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(diffLabel,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: diffColor,
                        fontFeatures: V2Typography.tabularNums)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 差額ぶんを調整取引で埋めるプロンプト。
class _AdjustmentPrompt extends StatelessWidget {
  final int amount;
  final VoidCallback onAdd;

  const _AdjustmentPrompt({required this.amount, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDC2626), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded,
                  size: 20, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '実際の請求が明細合計より ${formatYen(amount)} 多いです。'
                  '記録漏れの支出がある可能性があります。',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text('差額 ${formatYen(amount)} を支出として記録'),
          ),
        ],
      ),
    );
  }
}

/// 棚卸しシート内の明細行（タップで編集 / ゴミ箱で削除）。
class _ReconcileTxnRow extends StatelessWidget {
  final core.Transaction txn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReconcileTxnRow({
    required this.txn,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cat = txn.category.sub.isNotEmpty
        ? '${txn.category.major} ＞ ${txn.category.sub}'
        : txn.category.major;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.md, vertical: V2Spacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text('${txn.date.month}/${txn.date.day}',
                  style: V2Typography.micro
                      .copyWith(color: V2Colors.textSecondary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      txn.description.isEmpty
                          ? txn.category.major
                          : txn.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(cat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('-${formatYen(txn.amount)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: V2Colors.negative,
                    fontFeatures: V2Typography.tabularNums)),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: V2Colors.textMuted,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
