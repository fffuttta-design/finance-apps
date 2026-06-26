import 'dart:async';
import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/backup_repository.dart';
import '../../data/csv_picker.dart';
import '../../data/settings_repository.dart';
import '../../data/store_category_classifier.dart';
import '../../data/transaction_repository.dart';
import '../../screens/card_csv_import_screen.dart';
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
/// [onAddAdjustment] 支出を追加（差額ぶん／明細コピペ突合の記録漏れ補完で使用）。
///   description/date を渡すと支出入力にプリフィルする。
Future<void> showCardReconcileSheet(
  BuildContext context, {
  required core.RegisteredCreditCard card,
  required String ym,
  required Future<void> Function(int? amount) onSaveActual,
  required Future<void> Function(core.Transaction t) onEditTxn,
  required Future<void> Function(core.Transaction t) onDeleteTxn,
  required Future<void> Function(int amount, {String? description, DateTime? date})
      onAddAdjustment,
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

  /// 支出を追加（差額ぶん／突合の記録漏れ補完）。description/date でプリフィル。
  final Future<void> Function(int amount, {String? description, DateTime? date})
      onAddAdjustment;

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

  /// 貼り付けたカード明細（突合用）。空なら突合UIは出さない。
  List<_StmtLine> _pasted = [];

  /// 荒療治（CSVで置き換え）の実行中フラグ。
  bool _replacing = false;

  /// 記録漏れ行のインライン編集状態（明細行ごと：店名・科目）。
  final Map<_StmtLine, _LineEdit> _edits = {};

  /// カテゴリ候補（現モード・休眠除く）。
  List<String> _majors = [];
  Map<String, List<String>> _catMenu = {};

  /// AIが科目を推定中。
  bool _proposing = false;

  @override
  void initState() {
    super.initState();
    _actual = widget.card.monthlyActualBillings[widget.ym];
    _load();
    _loadCats();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _all = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final e in _edits.values) {
      e.dispose();
    }
    super.dispose();
  }

  /// カテゴリ候補を読み込む（ドロップダウン＋AI推定用）。
  Future<void> _loadCats() async {
    try {
      final cfg = await SettingsRepository().loadCategories();
      final menu = <String, List<String>>{};
      final majors = <String>[];
      for (final m in cfg.majors) {
        if (m.inactive) continue;
        menu[m.name] = m.subs;
        // 大カテゴリ名の重複はドロップダウンの assert を誘発するので一意化。
        if (!majors.contains(m.name)) majors.add(m.name);
      }
      if (!mounted) return;
      setState(() {
        _catMenu = menu;
        _majors = majors;
      });
    } catch (_) {}
  }

  /// CSV/貼り付け明細をセットし、行ごとの編集状態を作って科目をAI提案する。
  void _setPasted(List<_StmtLine> lines) {
    for (final e in _edits.values) {
      e.dispose();
    }
    _edits.clear();
    for (final l in lines) {
      _edits[l] = _LineEdit(name: l.name);
    }
    _setPasted(lines);
    _propose();
  }

  /// 記録漏れ行の店名から会計科目をAIで一括提案する。
  Future<void> _propose() async {
    if (_pasted.isEmpty || _catMenu.isEmpty) return;
    setState(() => _proposing = true);
    final lines = List<_StmtLine>.from(_pasted);
    final names = [for (final l in lines) _edits[l]?.nameCtrl.text ?? l.name];
    List<Map<String, String>?> cats;
    try {
      cats = await StoreCategoryClassifier.instance.classify(names, _catMenu);
    } catch (_) {
      cats = List<Map<String, String>?>.filled(names.length, null);
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < lines.length && i < cats.length; i++) {
        final c = cats[i];
        final e = _edits[lines[i]];
        if (c != null && e != null) {
          e.major = c['major'];
          e.sub = c['sub'] ?? '';
        }
      }
      _proposing = false;
    });
  }

  /// 記録漏れ1件を、編集後の店名・科目で支出として追加する。
  Future<void> _addMissing(_StmtLine line) async {
    final e = _edits[line];
    final name = (e?.nameCtrl.text ?? line.name).trim();
    if (name.isEmpty) return;
    final minDate = AppModeManager.instance.current.minDate;
    final date = line.date ?? DateTime(_year, _month);
    if (date.isBefore(minDate)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${minDate.year}年${minDate.month}月より前は登録できません')));
      return;
    }
    final tx = core.Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: date,
      type: core.TransactionType.expense,
      category: core.Category(major: e?.major ?? '未分類', sub: e?.sub ?? ''),
      paymentMethod: widget.card.name,
      description: name,
      amount: line.amount,
      store: name,
    );
    await _txRepo.add(tx);
    await _load();
  }

  /// 記録漏れをまとめて追加する。
  Future<void> _addAllMissing(List<_StmtLine> missing) async {
    if (missing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('記録漏れをまとめて追加'),
        content: Text('編集後の店名・科目で ${missing.length}件を追加します。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('追加する')),
        ],
      ),
    );
    if (ok != true) return;
    for (final l in missing) {
      await _addMissing(l);
    }
  }

  /// 記録漏れ1行のインライン編集UI（店名編集＋科目ドロップダウン＋追加）。
  Widget _missingEditRow(_StmtLine line) {
    final e = _edits.putIfAbsent(line, () => _LineEdit(name: line.name));
    return Padding(
      padding: const EdgeInsets.fromLTRB(V2Spacing.md, 8, V2Spacing.md, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                    line.date != null
                        ? '${line.date!.month}/${line.date!.day}'
                        : '—',
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textSecondary)),
              ),
              // 店名（編集可）
              Expanded(
                child: TextField(
                  controller: e.nameCtrl,
                  onChanged: (_) => setState(() {}),
                  style: V2Typography.body,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatYen(line.amount),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.negative,
                      fontFeatures: V2Typography.tabularNums)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 34),
              // 科目（AI提案・変更可）
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _majors.contains(e.major) ? e.major : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.auto_awesome, size: 15),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 30, minHeight: 0),
                    hintText: '科目（未分類）',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                  items: [
                    for (final m in _majors)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => setState(() {
                    e.major = v;
                    e.sub = '';
                  }),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 38),
                ),
                onPressed: () => _addMissing(line),
                child: const Text('追加', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
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

  /// カード明細をコピペ → 解析して突合用にセット。
  Future<void> _pasteStatement() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('カード明細を貼り付け'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  '【確実な方法】CSVファイルを開いて全選択(Ctrl+A)→コピー(Ctrl+C)→'
                  'ここに貼り付け(Ctrl+V)してください。CSVの中身そのままでOKです。\n'
                  '（カード会社サイトの明細をコピペしてもOK。1行＝1明細）',
                  style:
                      TextStyle(fontSize: 11, color: V2Colors.textSecondary)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 12,
                minLines: 6,
                decoration: const InputDecoration(
                  hintText: 'CSVの中身をそのまま貼り付け、または\n'
                      '2026/06/15  Amazon.co.jp  3,980 …',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('突合する')),
        ],
      ),
    );
    if (ok != true) return;
    // まずCSV(カンマ区切り)として解析。だめなら自由文として金額拾い。
    var lines = _parseCardCsv(ctrl.text, _year);
    if (lines.isEmpty) lines = _parseStatement(ctrl.text, _year);
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('金額を読み取れる明細が見つかりませんでした')));
      return;
    }
    _setPasted(lines);
  }

  /// カード明細CSVを選択 → Shift-JIS/UTF-8 を判定して解析 → 突合用にセット。
  Future<void> _importCsv() async {
    final picked = await pickCsvFile();
    if (!mounted) return;
    if (picked == null) return; // キャンセル or 取得失敗
    final bytes = picked.bytes;
    final content = _decodeCsvBytes(bytes);
    final lines = _parseCardCsv(content, _year);
    if (!mounted) return;
    if (lines.isEmpty) {
      // 何が読めなかったか分かるよう、デコード結果の先頭を見せる固定ダイアログ。
      final preview = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(4)
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('CSVを読み取れませんでした'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${picked.name}（${bytes.length}バイト）',
                    style: const TextStyle(
                        fontSize: 12, color: V2Colors.textSecondary)),
                const SizedBox(height: 8),
                const Text('読み取った先頭行（文字化けしていたらエンコーディングの問題です）:',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: const Color(0xFFF1F5F9),
                  child: Text(preview.isEmpty ? '(空)' : preview,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる')),
          ],
        ),
      );
      return;
    }
    _setPasted(lines);
  }

  /// CSV期間ラベル（"5/1〜5/31" など。日付不明なら "全期間"）。
  String _rangeLabel(DateTime? lo, DateTime? hi) {
    if (lo == null || hi == null) return '全期間';
    return '${lo.month}/${lo.day}〜${hi.month}/${hi.day}';
  }

  /// 【荒療治】CSV明細を「正」として取り込むプレビュー画面へ遷移する。
  /// プレビューで店名の編集・AIによる科目提案・下書き保存を行い、確定で
  /// CSV期間内の既存カード取引を削除→編集後の内容で一括記帳する。
  Future<void> _openCsvImport() async {
    final lines = [
      for (final l in _pasted) CardCsvLine(l.date, l.name, l.amount),
    ];
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CardCsvImportScreen(
          card: widget.card,
          ym: widget.ym,
          lines: lines,
        ),
      ),
    );
    if (done == true && mounted) {
      for (final e in _edits.values) {
        e.dispose();
      }
      _edits.clear();
      setState(() => _pasted = []);
      await _load();
    }
  }

  /// 【荒療治・CSV不要】この月・このカードの取引をまとめて初期化（削除）する。
  /// 「全部消してから明細を正として入れ直す」運用の最初の一歩。実行前に自動バックアップ。
  Future<void> _initializeMonth(List<core.Transaction> txns) async {
    if (txns.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$_month月の${widget.card.name}を初期化しますか？'),
        content: Text(
            '「${widget.card.name}」払いの$_year年$_month月の取引 ${txns.length}件を'
            'すべて削除します。\n\n'
            'この操作は元に戻せません。実行直前に自動バックアップを取ります。\n'
            '削除後、正しい明細をCSV取り込みや手入力で入れ直してください。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: Text('${txns.length}件を削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _replacing = true);
    try {
      try {
        await BackupRepository.instance
            .savePreImportSnapshot(reason: 'pre-card-init');
      } catch (_) {}
      var deleted = 0;
      for (final t in txns) {
        try {
          await _txRepo.delete(t.id);
          deleted++;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _replacing = false);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('初期化完了：$deleted件を削除しました')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _replacing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('初期化に失敗しました: $e')));
    }
  }

  /// 明細コピペ／CSV → 突合UI（ボタン＋結果）。
  Widget _statementSection() {
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _importCsv,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(_pasted.isEmpty ? 'CSVを読み込んで突合' : 'CSVを読み込み直す'),
            ),
          ),
          const SizedBox(width: V2Spacing.sm),
          OutlinedButton.icon(
            onPressed: _pasteStatement,
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('貼り付け'),
          ),
        ],
      ),
    ];

    if (_pasted.isNotEmpty) {
      // 突合対象 = このカード払いの取引のうち「貼り付け明細がカバーする期間」のもの。
      // （請求月と利用月はズレるため、表示中の月では絞らない。明細の日付範囲±2日で照合）
      DateTime? minD, maxD;
      for (final l in _pasted) {
        if (l.date == null) continue;
        if (minD == null || l.date!.isBefore(minD)) minD = l.date;
        if (maxD == null || l.date!.isAfter(maxD)) maxD = l.date;
      }
      final lo = minD?.subtract(const Duration(days: 2));
      final hi = maxD?.add(const Duration(days: 2));
      final pool = _all.where((t) {
        if (t.type != core.TransactionType.expense) return false;
        if (t.paymentMethod != widget.card.name) return false;
        if (lo != null && t.date.isBefore(lo)) return false;
        if (hi != null && t.date.isAfter(hi)) return false;
        return true;
      }).toList();

      // 金額で突合（記録1件は1回まで）。
      final used = <int>{};
      final missing = <_StmtLine>[]; // 明細にあり・記録なし＝記録漏れ
      int matchedCount = 0;
      for (final line in _pasted) {
        int found = -1;
        for (int i = 0; i < pool.length; i++) {
          if (used.contains(i)) continue;
          if (pool[i].amount == line.amount) {
            found = i;
            break;
          }
        }
        if (found >= 0) {
          used.add(found);
          matchedCount++;
        } else {
          missing.add(line);
        }
      }
      final extra = <core.Transaction>[]; // 記録あり・明細なし＝要確認
      for (int i = 0; i < pool.length; i++) {
        if (!used.contains(i)) extra.add(pool[i]);
      }
      final pastedTotal = _pasted.fold<int>(0, (s, l) => s + l.amount);
      final missingTotal = missing.fold<int>(0, (s, l) => s + l.amount);

      children.add(const SizedBox(height: V2Spacing.md));
      // サマリー
      children.add(Container(
        padding: const EdgeInsets.all(V2Spacing.md),
        decoration: BoxDecoration(
          color: V2Colors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: V2Colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('貼り付け ${_pasted.length}件 / ${formatYen(pastedTotal)}',
                style: V2Typography.caption
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _chip('一致 $matchedCount件', V2Colors.positive),
              _chip('記録漏れ ${missing.length}件', V2Colors.negative),
              _chip('要確認 ${extra.length}件', V2Colors.warning),
            ]),
          ],
        ),
      ));

      // ── 荒療治: この明細でカード取引を丸ごと置き換える ──
      // 棚卸しのコストが高すぎる時の最終手段。CSV期間の既存カード取引を削除し、
      // CSVの各行を新規取引として取り込む（科目は店名からAI推定）。
      children.add(const SizedBox(height: V2Spacing.sm));
      children.add(Container(
        padding: const EdgeInsets.all(V2Spacing.sm),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDBA74)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('荒療治：この明細を正として置き換える',
                style: V2Typography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A3412))),
            const SizedBox(height: 2),
            Text(
                'CSVの期間内（${_rangeLabel(lo, hi)}）の「${widget.card.name}」既存取引を削除し、'
                'CSV ${_pasted.length}件を新規取り込み（科目は店名からAI推定）。実行前に自動バックアップ。',
                style: V2Typography.caption
                    .copyWith(color: const Color(0xFF9A3412), fontSize: 11)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openCsvImport(),
                icon: const Icon(Icons.sync_problem, size: 18),
                label: Text(
                    'CSVで置き換える（プレビュー・既存${pool.length}件を削除）'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C)),
              ),
            ),
          ],
        ),
      ));

      // 記録漏れ（明細にあるが記録に無い）→ その場で店名・科目を直して追加
      if (missing.isNotEmpty) {
        children.add(const SizedBox(height: V2Spacing.sm));
        children.add(Row(children: [
          const Icon(Icons.error_outline,
              size: 16, color: V2Colors.negative),
          const SizedBox(width: 6),
          Expanded(
            child: Text('記録漏れ（明細にあるが未記録）合計 ${formatYen(missingTotal)}',
                style: V2Typography.caption.copyWith(
                    color: V2Colors.negative, fontWeight: FontWeight.w700)),
          ),
          if (_proposing)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _propose,
              icon: const Icon(Icons.auto_awesome, size: 15),
              label: const Text('AIで科目提案', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
        ]));
        children.add(Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 4),
          child: Text('店名を直し、科目を選んで「追加」。AIが科目を提案します。',
              style: V2Typography.micro.copyWith(color: V2Colors.textMuted)),
        ));
        children.add(const SizedBox(height: 6));
        children.add(Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < missing.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: V2Colors.divider),
                _missingEditRow(missing[i]),
              ],
            ],
          ),
        ));
        // 記録漏れをまとめて追加
        children.add(const SizedBox(height: 8));
        children.add(SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _addAllMissing(missing),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: Text('記録漏れ ${missing.length}件をまとめて追加'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
          ),
        ));
      }

      // 要確認（記録にあるが明細に無い）→ 二重計上等の確認
      if (extra.isNotEmpty) {
        children.add(const SizedBox(height: V2Spacing.sm));
        children.add(Row(children: [
          const Icon(Icons.help_outline, size: 16, color: V2Colors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text('要確認（記録にあるが明細に無い）',
                style: V2Typography.caption.copyWith(
                    color: const Color(0xFF92400E),
                    fontWeight: FontWeight.w700)),
          ),
        ]));
        children.add(const SizedBox(height: 6));
        children.add(Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFCD34D)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < extra.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: V2Colors.divider),
                _ReconcileTxnRow(
                  txn: extra[i],
                  onEdit: () => widget.onEditTxn(extra[i]),
                  onDelete: () => widget.onDeleteTxn(extra[i]),
                ),
              ],
            ],
          ),
        ));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

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
                // 明細コピペ → 突合（記録漏れを炙り出す）
                Text('明細コピペで突合', style: V2Typography.h2),
                const SizedBox(height: V2Spacing.sm),
                _statementSection(),
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
                // 荒療治：この月のこのカード取引を丸ごと初期化（削除）。
                // CSV無しでも使える独立ボタン。明細があるときだけ表示。
                if (txns.isNotEmpty) ...[
                  const SizedBox(height: V2Spacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _replacing ? null : () => _initializeMonth(txns),
                      icon: _replacing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(_replacing
                          ? '初期化中…'
                          : '$_month月の${widget.card.name}を初期化（${txns.length}件を削除）'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
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

// ═════════════════════════════════════════════════
// 明細コピペの解析・突合
// ═════════════════════════════════════════════════

/// 貼り付けたカード明細の1行（日付・店名・金額）。
class _StmtLine {
  final DateTime? date;
  final String name;
  final int amount;
  const _StmtLine(this.date, this.name, this.amount);
}

/// 記録漏れ行のインライン編集状態（編集後の店名・会計科目）。
class _LineEdit {
  final TextEditingController nameCtrl;
  String? major;
  String sub = '';
  _LineEdit({required String name})
      : nameCtrl = TextEditingController(text: name);
  void dispose() => nameCtrl.dispose();
}

/// カード明細テキストを行ごとに解析する。
/// 各行から金額（末尾の数字／¥付き）と日付・店名を推定。金額が取れない行は無視。
List<_StmtLine> _parseStatement(String text, int year) {
  // 末尾の金額（¥/\/￥ や 円 を許容、3桁区切りカンマ可）。
  final amountRe = RegExp(r'[¥\\￥]?\s*([0-9][0-9,]*)\s*円?\s*$');
  // 日付（YYYY/MM/DD / MM/DD / YYYY年MM月DD日 等）。
  final dateRe =
      RegExp(r'(\d{1,4})\s*[/\-.年]\s*(\d{1,2})(?:\s*[/\-.月]\s*(\d{1,2}))?');
  // 合計・残高など明細でない行を除外。
  final skipRe = RegExp(
      r'(合計|小計|お支払|支払金額|請求(額|金額)|ご利用可能|利用可能|繰越|残高|キャッシング|手数料合計|お引き落とし|前回|今回)');

  final out = <_StmtLine>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (skipRe.hasMatch(line)) continue;
    final am = amountRe.firstMatch(line);
    if (am == null) continue;
    final amt = int.tryParse(am.group(1)!.replaceAll(',', '')) ?? 0;
    if (amt <= 0) continue;

    DateTime? date;
    final dm = dateRe.firstMatch(line);
    if (dm != null) {
      final g1 = int.parse(dm.group(1)!);
      final g2 = int.parse(dm.group(2)!);
      if (dm.group(3) != null) {
        // YYYY/MM/DD（2桁年は2000年代へ）
        final y = g1 < 100 ? 2000 + g1 : g1;
        date = DateTime(y, g2, int.parse(dm.group(3)!));
      } else {
        // MM/DD（年は明細の対象年）
        date = DateTime(year, g1, g2);
      }
    }

    var name = line;
    if (dm != null) name = name.replaceFirst(dm.group(0)!, ' ');
    name = name.replaceFirst(am.group(0)!, ' ').trim();
    // 余分な区切り文字を整理
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    out.add(_StmtLine(date, name.isEmpty ? '明細' : name, amt));
  }
  return out;
}

// ── カード明細CSVの解析 ──

/// 金額セルか判定し、正なら金額を返す。「¥ / \ / ￥ ＋ 数字(カンマ可)」のセルだけを
/// 金額とみなす。これで「2026年6月」のような期間列を金額と誤検出しない。
int? _yenAmount(String cell) {
  final c = cell.trim();
  if (c.isEmpty) return null;
  final f = c[0];
  if (f != '\\' && f != '¥' && f != '￥') return null;
  final rest = c.substring(1).replaceAll(',', '');
  if (rest.isEmpty || !RegExp(r'^\d+$').hasMatch(rest)) return null;
  final v = int.tryParse(rest);
  return (v != null && v > 0) ? v : null;
}

/// カード明細CSVを解析して明細行リストにする。
///
/// **ヘッダー行に依存しない**（Shift-JISデコーダが前文/ヘッダーを落としても拾えるよう、
/// 「1列目が日付の行」を明細とみなす）。
/// 対応様式: ① Orico「ご利用明細」(日付列＋「¥/\付き金額」列) ② 三井住友等(日付/店名/金額)
List<_StmtLine> _parseCardCsv(String content, int year) {
  final rows =
      const LineSplitter().convert(content).map(_splitCsvLine).toList();

  // ── 主方式: 1列目が日付の行を拾い、金額は「¥/\/￥付きの最初の正値」を採用 ──
  // （前文・ヘッダー行は日付にならないので自然に除外される）
  final out = <_StmtLine>[];
  for (final c in rows) {
    if (c.isEmpty) continue;
    final date = _parseAnyDate(c[0], year);
    if (date == null) continue;
    int amt = 0;
    for (int j = 1; j < c.length; j++) {
      final v = _yenAmount(c[j]);
      if (v != null) {
        amt = v;
        break;
      }
    }
    if (amt <= 0) continue;
    final name = c.length > 1 ? c[1].trim() : '';
    out.add(_StmtLine(date, name.isEmpty ? '明細' : name, amt));
  }
  if (out.isNotEmpty) return out;

  // ── フォールバック: 1列目=日付 / 2列目=店名 / 3列目=金額（¥記号なしの様式） ──
  final out2 = <_StmtLine>[];
  for (final c in rows) {
    if (c.length < 3) continue;
    final date = _parseAnyDate(c[0], year);
    if (date == null) continue;
    final amt = _yen(c[2]);
    if (amt <= 0) continue;
    final name = c[1].trim();
    out2.add(_StmtLine(date, name.isEmpty ? '明細' : name, amt));
  }
  return out2;
}

/// CSVバイト列を文字列にデコードする。
/// UTF-8 として「文字化け（U+FFFD）なく」読めればそれを採用。読めなければ
/// Shift-JIS（カード明細の大半）→ 最後の保険で Latin-1 の順で試す。
String _decodeCsvBytes(List<int> bytes) {
  // UTF-8（厳密）。例外なく＆置換文字を含まなければ採用。
  try {
    final u = utf8.decode(bytes);
    if (!u.contains('�')) return u;
  } catch (_) {}
  // Shift-JIS（cp932相当）。日本のカード明細はほぼこれ。
  try {
    final s = shiftJis.decode(bytes);
    if (s.trim().isNotEmpty) return s;
  } catch (_) {}
  return latin1.decode(bytes, allowInvalid: true);
}

/// CSVの1行をダブルクオート対応で分割。
List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQ = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQ && i + 1 < line.length && line[i + 1] == '"') {
        sb.write('"');
        i++;
      } else {
        inQ = !inQ;
      }
    } else if (ch == ',' && !inQ) {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out;
}

/// 金額セルから数字だけ抜いて整数化（¥ \ ￥ , 円 " 等を除去）。
int _yen(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// 日付セルを解析（yyyy/mm/dd・yyyy-mm-dd・yyyy年m月d日・mm/dd）。
DateTime? _parseAnyDate(String s, int year) {
  final t = s.trim();
  var m = RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{1,2})[/\-](\d{1,2})$').firstMatch(t);
  if (m != null) {
    return DateTime(year, int.parse(m[1]!), int.parse(m[2]!));
  }
  return null;
}
