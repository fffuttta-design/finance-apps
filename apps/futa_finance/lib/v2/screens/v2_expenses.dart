import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_mode.dart';
import '../../data/drive_receipt_service.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/receipt_image_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/formatters.dart';
import '../../utils/thousands_separator_input_formatter.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/subscription_edit_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 ネイティブ支出タブ（マネフォクラウド寄りのテーブル中心）。
///
/// レイアウト:
/// - 上部: 月切替バー + 統計（件数 / 合計）
/// - 中央上: 毎月引落予定（固定費 / 変動費）
/// - 中央下: 取引一覧テーブル（日付 / カテゴリ / 内容 / 支払方法 / 金額）
///
/// 機能は v1 と完全同等を目指すが、初版はテーブル表示 + 引落予定のみ。
/// 検索/フィルタ/カテゴリ別集計/グラフは順次追加予定。
class V2ExpensesScreen extends StatefulWidget {
  final Color accent;
  const V2ExpensesScreen({super.key, required this.accent});

  @override
  State<V2ExpensesScreen> createState() => _V2ExpensesScreenState();
}

class _V2ExpensesScreenState extends State<V2ExpensesScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;
  final _settings = SettingsRepository();
  final _subscriptionRepo = SubscriptionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig _payments =
      core.PaymentMethodsConfig.empty();
  core.SubscriptionConfig _subscriptions =
      core.SubscriptionConfig.empty();
  bool _loading = true;

  /// 表示月
  late DateTime _focused =
      DateTime(DateTime.now().year, DateTime.now().month);

  /// 表示中の月キー "YYYY-MM"（変動費の実額参照用）。
  String get _ymKey =>
      '${_focused.year}-${_focused.month.toString().padLeft(2, '0')}';

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
    final payments = await _settings.loadPayments();
    final subs = await _subscriptionRepo.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _subscriptions = subs;
      _loading = false;
    });
  }

  List<core.Transaction> get _monthExpenses {
    return _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.date.year == _focused.year &&
            t.date.month == _focused.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 当月の毎月引落予定（subscription の monthly）
  List<core.Subscription> get _monthlyCharges {
    final list = _subscriptions.subscriptions
        .where(
            (s) => s.cycle == core.SubscriptionCycle.monthly)
        .toList();
    list.sort((a, b) {
      final ad = a.billingDay ?? 32;
      final bd = b.billingDay ?? 32;
      return ad.compareTo(bd);
    });
    return list;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month + delta);
    });
  }

  /// 経費明細の全件一覧（並び替え・検索）を開く。
  Future<void> _openExpenseList() async {
    final isBusiness = AppModeManager.instance.current == AppMode.business;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseListScreen(
            title: isBusiness ? '経費明細一覧' : '支出明細一覧',
            month: _focused),
      ),
    );
    if (mounted) await _load();
  }

  /// 行タップ：経費はまず詳細画面を表示（そこから編集/削除）。それ以外は明細シート。
  Future<void> _showTxnSummary(core.Transaction t) async {
    if (t.type == core.TransactionType.expense) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(transaction: t)),
      );
      if (changed == true && mounted) await _load();
      return;
    }
    final hasReceipt = t.receiptUrl != null && t.receiptUrl!.trim().isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t.date.year}/${t.date.month}/${t.date.day}　'
                '${t.description.isEmpty ? t.paymentMethod : t.description}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '-${formatYen(t.amount)}　/　${t.category.major}'
                '${t.category.sub.isNotEmpty ? ' › ${t.category.sub}' : ''}　/　${t.paymentMethod}',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280)),
              ),
              if (t.memo != null && t.memo!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(t.memo!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF374151))),
              ],
              const SizedBox(height: 16),
              if (hasReceipt)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final raw = t.receiptUrl!.trim();
                      final fileId = DriveReceiptService.fileIdFromUrl(raw);
                      if (fileId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ReceiptImageScreen(fileId: fileId)),
                        );
                        return;
                      }
                      final uri = Uri.tryParse(raw);
                      if (uri != null) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('領収書を見る'),
                  ),
                )
              else
                const Text('領収書リンクは未登録です',
                    style:
                        TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
          ),
        ),
      ),
    );
  }

  /// 引落予定の項目タップ → その場で編集シート（設定カード）を直接開く。
  /// 設定画面に遷移せず、保存したら即リストへ反映する。
  Future<void> _openSubscriptionEdit(String id) async {
    final idx =
        _subscriptions.subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final paymentMethods = <String>[
      ..._payments.bankAccounts.map((b) => b.name),
      ..._payments.creditCards.map((c) => c.name),
    ];
    final categories = _subscriptions.categoriesInOrder
        .where((c) => c != core.SubscriptionConfig.uncategorizedKey)
        .toList();
    // 会計科目（PL科目）候補 = 現モードの大カテゴリ名（番号なし素の名前）。
    final catConfig = await _settings.loadCategories();
    final accountingMajors =
        catConfig.majors.map((m) => m.name).toList();
    if (!mounted) return;
    final edited = await showSubscriptionEditSheet(
      context,
      initial: _subscriptions.subscriptions[idx],
      paymentMethods: paymentMethods,
      categories: categories,
      accountingMajors: accountingMajors,
    );
    if (edited == null) return;
    final newList = [..._subscriptions.subscriptions];
    newList[idx] = edited;
    await _subscriptionRepo
        .save(_subscriptions.copyWith(subscriptions: newList));
    if (mounted) await _load();
  }

  /// 変動費の「その月の実額」をその場で入力（未入力は0／月ごと独立）。
  Future<void> _inputVariableActual(core.Subscription s) async {
    final ym = _ymKey;
    final current = s.monthlyActuals[ym] ?? 0;
    final prev = s.monthlyActuals[prevYmKey(ym)] ?? 0;
    final ctrl = NoComposingUnderlineController(
        text: current > 0 ? formatAmount(current) : '');
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${_focused.month}月の「${s.name}」'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [
            HalfWidthDigitsFormatter(),
            ThousandsSeparatorInputFormatter(),
          ],
          decoration: InputDecoration(
            labelText: '実額（円）',
            // プレースホルダは前月実額（無ければ非表示）。¥プレフィックスは外して窮屈さ解消。
            hintText: prev > 0 ? '前月 ${formatYen(prev)}' : null,
            // 下線だけだと“素のアンダーバー”に見えるので枠付きボックスにする。
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, -1),
              child: const Text('クリア')),
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, parseAmount(ctrl.text) ?? 0),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return; // キャンセル
    final idx = _subscriptions.subscriptions.indexWhere((x) => x.id == s.id);
    if (idx < 0) return;
    final m = Map<String, int>.from(s.monthlyActuals);
    if (result <= 0) {
      m.remove(ym);
    } else {
      m[ym] = result;
    }
    final list = [..._subscriptions.subscriptions];
    list[idx] = s.copyWith(monthlyActuals: m);
    await _subscriptionRepo
        .save(_subscriptions.copyWith(subscriptions: list));
    if (mounted) await _load();
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
    final expenses = _monthExpenses;
    final total = expenses.fold<int>(0, (s, t) => s + t.amount);
    // 固定費（毎月支出予定）の当月合計。一番上の月合計は「経費＋固定費」にする。
    final fixedTotal =
        _monthlyCharges.fold<int>(0, (s, c) => s + c.amountForMonth(_ymKey));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.xl, horizontal: V2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 月切替バー + 集計サマリー ─────────────────
          V2Card(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.lg, vertical: V2Spacing.md),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  '${_focused.year}年${_focused.month}月',
                  style: V2Typography.h2.copyWith(
                      color: V2Colors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () => _shiftMonth(1),
                ),
                const SizedBox(width: V2Spacing.lg),
                Text('${expenses.length} 件',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary)),
                const Spacer(),
                Text('合計（経費＋固定費）',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary)),
                const SizedBox(width: V2Spacing.sm),
                Text(formatYen(-(total + fixedTotal), withSign: true),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: V2Colors.negative,
                        fontFeatures: V2Typography.tabularNums)),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.sm),
          // ── 取引一覧（経費明細）を上に ────────────────────
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
                      // タイトルをタップ → 全件一覧（並び替え・検索）へ
                      Expanded(
                        child: InkWell(
                          onTap: _openExpenseList,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined,
                                    size: 18, color: widget.accent),
                                const SizedBox(width: V2Spacing.sm),
                                Text(isBusiness ? '経費明細' : '支出明細',
                                    style: V2Typography.h2),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    size: 18, color: V2Colors.textMuted),
                                const Text('一覧',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: V2Colors.textMuted)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 追加ボタンは廃止。代わりに経費明細の合計を表示。
                      Text('-${formatYen(total)}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: V2Colors.negative,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
                if (expenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: V2Spacing.sm),
                        Text('${_focused.month}月の支出記録なし',
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.textSecondary)),
                      ],
                    ),
                  )
                else
                  _ExpensesTable(
                    rows: expenses,
                    onTapRow: _showTxnSummary,
                  ),
              ],
            ),
          ),
          if (_monthlyCharges.isNotEmpty)
            const SizedBox(height: V2Spacing.lg),
          // ── 毎月支出予定（固定費 / 変動費）を経費明細の下に ──────
          _MonthlyChargesSection(
            charges: _monthlyCharges,
            onTapItem: _openSubscriptionEdit,
            isCurrentMonth: _focused.year == DateTime.now().year &&
                _focused.month == DateTime.now().month,
            ym: _ymKey,
            onInputVariable: _inputVariableActual,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 毎月引落予定セクション（固定費 / 変動費）
// ═════════════════════════════════════════════════

/// 毎月支出予定の並び替えモード。
enum _ChargeSort { amountDesc, amountAsc, majorAsc, majorDesc }

class _MonthlyChargesSection extends StatefulWidget {
  final List<core.Subscription> charges;
  final void Function(String id) onTapItem;
  final bool isCurrentMonth;

  /// 表示中の月キー "YYYY-MM"（変動費の実額参照用）。
  final String ym;

  /// 変動費の月額入力を開くコールバック。
  final void Function(core.Subscription s) onInputVariable;
  const _MonthlyChargesSection({
    required this.charges,
    required this.onTapItem,
    required this.isCurrentMonth,
    required this.ym,
    required this.onInputVariable,
  });

  @override
  State<_MonthlyChargesSection> createState() =>
      _MonthlyChargesSectionState();
}

class _MonthlyChargesSectionState extends State<_MonthlyChargesSection> {
  bool _fixedExpanded = true;
  bool _variableExpanded = true;
  _ChargeSort _sort = _ChargeSort.amountDesc;

  /// 並び替えを適用したコピーを返す。
  List<core.Subscription> _sorted(List<core.Subscription> list) {
    final l = [...list];
    int amt(core.Subscription s) => s.amountForMonth(widget.ym);
    String maj(core.Subscription s) => (s.plMajor ?? '').trim();
    int byMajor(core.Subscription a, core.Subscription b, bool asc) {
      final am = maj(a), bm = maj(b);
      // 未設定は常に末尾へ。
      if (am.isEmpty && bm.isEmpty) return 0;
      if (am.isEmpty) return 1;
      if (bm.isEmpty) return -1;
      return asc ? am.compareTo(bm) : bm.compareTo(am);
    }

    switch (_sort) {
      case _ChargeSort.amountDesc:
        l.sort((a, b) => amt(b).compareTo(amt(a)));
        break;
      case _ChargeSort.amountAsc:
        l.sort((a, b) => amt(a).compareTo(amt(b)));
        break;
      case _ChargeSort.majorAsc:
        l.sort((a, b) => byMajor(a, b, true));
        break;
      case _ChargeSort.majorDesc:
        l.sort((a, b) => byMajor(a, b, false));
        break;
    }
    return l;
  }

  String get _sortLabel {
    switch (_sort) {
      case _ChargeSort.amountDesc:
        return '金額↓';
      case _ChargeSort.amountAsc:
        return '金額↑';
      case _ChargeSort.majorAsc:
        return '科目↑';
      case _ChargeSort.majorDesc:
        return '科目↓';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.charges.isEmpty) return const SizedBox.shrink();
    final fixed = _sorted(widget.charges
        .where((s) =>
            s.amountType == core.SubscriptionAmountType.fixed)
        .toList());
    final variable = _sorted(widget.charges
        .where((s) =>
            s.amountType ==
            core.SubscriptionAmountType.variable)
        .toList());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: V2Spacing.sm),
          child: Row(
            children: [
              const Icon(Icons.event_repeat,
                  size: 18, color: Color(0xFFEA580C)),
              const SizedBox(width: V2Spacing.sm),
              Text('毎月支出予定',
                  style: V2Typography.h2
                      .copyWith(color: V2Colors.textPrimary)),
              const Spacer(),
              // 並び替え
              PopupMenuButton<_ChargeSort>(
                tooltip: '並び替え',
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: _ChargeSort.amountDesc,
                      child: Text('金額が高い順')),
                  PopupMenuItem(
                      value: _ChargeSort.amountAsc,
                      child: Text('金額が安い順')),
                  PopupMenuItem(
                      value: _ChargeSort.majorAsc,
                      child: Text('会計科目 昇順')),
                  PopupMenuItem(
                      value: _ChargeSort.majorDesc,
                      child: Text('会計科目 降順')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: V2Colors.surfaceMuted,
                    borderRadius:
                        BorderRadius.circular(V2Spacing.radiusSm),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_vert, size: 14),
                      const SizedBox(width: 4),
                      Text(_sortLabel,
                          style: V2Typography.caption.copyWith(
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 固定費カード
        if (fixed.isNotEmpty)
          _ChargeCard(
            title: '固定費（定額）',
            icon: Icons.lock_outline,
            accent: const Color(0xFF1A237E),
            bg: const Color(0xFFE0E7FF),
            charges: fixed,
            isVariable: false,
            ym: widget.ym,
            isCurrentMonth: widget.isCurrentMonth,
            expanded: _fixedExpanded,
            onToggle: () =>
                setState(() => _fixedExpanded = !_fixedExpanded),
            onTapItem: widget.onTapItem,
            onInputVariable: widget.onInputVariable,
          ),
        if (fixed.isNotEmpty && variable.isNotEmpty)
          const SizedBox(height: V2Spacing.lg),
        // 変動費カード（その月の実額。未入力は0）
        if (variable.isNotEmpty)
          _ChargeCard(
            title: '変動費',
            icon: Icons.bolt_outlined,
            accent: const Color(0xFFEA580C),
            bg: const Color(0xFFFFEDD5),
            charges: variable,
            isVariable: true,
            ym: widget.ym,
            isCurrentMonth: widget.isCurrentMonth,
            expanded: _variableExpanded,
            onToggle: () =>
                setState(() => _variableExpanded = !_variableExpanded),
            onTapItem: widget.onTapItem,
            onInputVariable: widget.onInputVariable,
          ),
      ],
    );
  }
}

/// 固定費 / 変動費 を1枚ずつのカードで表示する。
class _ChargeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Color bg;
  final List<core.Subscription> charges;
  final bool isVariable;
  final String ym;
  final bool isCurrentMonth;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String id) onTapItem;
  final void Function(core.Subscription s) onInputVariable;
  const _ChargeCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.bg,
    required this.charges,
    required this.isVariable,
    required this.ym,
    required this.isCurrentMonth,
    required this.expanded,
    required this.onToggle,
    required this.onTapItem,
    required this.onInputVariable,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal =
        charges.fold<int>(0, (s, c) => s + c.amountForMonth(ym));
    final today = DateTime.now();
    return V2Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(V2Spacing.lg,
                  V2Spacing.md, V2Spacing.lg, V2Spacing.md),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: V2Spacing.sm),
                  Text(title,
                      style: V2Typography.h2.copyWith(color: accent)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${charges.length}',
                        style: TextStyle(
                            fontSize: 11,
                            color: accent,
                            fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text(formatYen(subtotal),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: V2Colors.textPrimary,
                          fontFeatures: V2Typography.tabularNums)),
                  const SizedBox(width: 6),
                  Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: V2Colors.textSecondary),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final s in charges)
              _ChargeRow(
                s: s,
                isCurrentMonth: isCurrentMonth,
                today: today,
                isVariable: isVariable,
                ym: ym,
                monthAmount: s.amountForMonth(ym),
                onTap: () => onTapItem(s.id),
                onInputAmount:
                    isVariable ? () => onInputVariable(s) : null,
              ),
        ],
      ),
    );
  }
}

/// "YYYY-MM" の前月キーを返す。
String prevYmKey(String ym) {
  final parts = ym.split('-');
  var y = int.parse(parts[0]);
  var m = int.parse(parts[1]) - 1;
  if (m < 1) {
    m = 12;
    y -= 1;
  }
  return '$y-${m.toString().padLeft(2, '0')}';
}

class _ChargeRow extends StatelessWidget {
  final core.Subscription s;
  final bool isCurrentMonth;
  final DateTime today;
  final VoidCallback onTap;

  /// 変動費かどうか。変動費は当月の実額（未入力は0）を入力ピルで表示。
  final bool isVariable;

  /// 表示中の月キー "YYYY-MM"（前月実額の参照に使う）。
  final String ym;

  /// 表示中の月の金額（固定費=定額、変動費=その月の実額。未入力は0）。
  final int monthAmount;

  /// 変動費の月額入力を開く（変動費のみ非null）。
  final VoidCallback? onInputAmount;
  const _ChargeRow({
    required this.s,
    required this.isCurrentMonth,
    required this.today,
    required this.onTap,
    this.isVariable = false,
    required this.ym,
    required this.monthAmount,
    this.onInputAmount,
  });

  @override
  Widget build(BuildContext context) {
    final day = s.billingDay;
    String? statusLabel;
    Color? statusColor;
    if (isCurrentMonth && day != null) {
      if (day < today.day) {
        statusLabel = '引落済';
        statusColor = V2Colors.positive;
      } else if (day == today.day) {
        statusLabel = '今日';
        statusColor = V2Colors.negative;
      } else {
        final left = day - today.day;
        statusLabel = 'あと$left日';
        statusColor =
            left <= 3 ? V2Colors.warning : V2Colors.info;
      }
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: V2Colors.divider, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(day == null ? '' : '$day日',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.textSecondary,
                      fontFeatures: V2Typography.tabularNums)),
            ),
            BrandLogo(
              iconUrl: s.iconUrl,
              fallbackIcon: Icons.subscriptions_outlined,
              size: 22,
              borderRadius: 4,
            ),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: V2Typography.body),
                  if (s.paymentMethod != null &&
                      s.paymentMethod!.isNotEmpty)
                    Text(s.paymentMethod!,
                        style: V2Typography.micro.copyWith(
                            color: V2Colors.textMuted)),
                ],
              ),
            ),
            if (statusLabel != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor!.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
              ),
              const SizedBox(width: V2Spacing.sm),
            ],
            if (isVariable) ...[
              // 変動費: 当月の実額をタップ入力。未入力は¥0。前月の実額を薄く併記。
              Builder(builder: (_) {
                final prev = s.monthlyActuals[prevYmKey(ym)] ?? 0;
                if (prev <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('前月 ${formatYen(prev)}',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                );
              }),
              InkWell(
                onTap: onInputAmount,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: monthAmount > 0
                        ? const Color(0xFFFFEDD5)
                        : V2Colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: monthAmount > 0
                            ? const Color(0xFFEA580C)
                            : V2Colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatYen(monthAmount),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: monthAmount > 0
                                  ? const Color(0xFFEA580C)
                                  : V2Colors.textMuted,
                              fontFeatures: V2Typography.tabularNums)),
                      const SizedBox(width: 3),
                      Icon(Icons.edit,
                          size: 12,
                          color: monthAmount > 0
                              ? const Color(0xFFEA580C)
                              : V2Colors.textMuted),
                    ],
                  ),
                ),
              ),
            ] else
              Text(formatYen(monthAmount),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.textPrimary,
                      fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 取引一覧テーブル（マネフォクラウド寄り）
// ═════════════════════════════════════════════════

/// 一覧の表示単位。単品（single）か、同じレシートのまとめ（group）。
class _Unit {
  final core.Transaction? single;
  final String? receiptId;
  final List<core.Transaction>? members;
  const _Unit.single(this.single)
      : receiptId = null,
        members = null;
  const _Unit.group(this.receiptId, this.members) : single = null;
  bool get isGroup => members != null;
  int get total => single != null
      ? single!.amount
      : members!.fold<int>(0, (s, t) => s + t.amount);
}

class _ExpensesTable extends StatefulWidget {
  final List<core.Transaction> rows;
  final void Function(core.Transaction t) onTapRow;
  const _ExpensesTable({
    required this.rows,
    required this.onTapRow,
  });

  @override
  State<_ExpensesTable> createState() => _ExpensesTableState();
}

class _ExpensesTableState extends State<_ExpensesTable> {
  /// 展開中のレシート（receiptId）。タップで内訳を開閉。
  final Set<String> _expanded = {};

  /// 同じ receiptId が2件以上 → まとめ（group）、それ以外 → 単品（single）。
  /// 並び順は元の rows の順（親はその最初の品目の位置）を保つ。
  List<_Unit> get _units {
    final rows = widget.rows;
    final counts = <String, int>{};
    for (final t in rows) {
      final rid = t.receiptId;
      if (rid != null && rid.isNotEmpty) {
        counts[rid] = (counts[rid] ?? 0) + 1;
      }
    }
    final units = <_Unit>[];
    final seen = <String>{};
    for (final t in rows) {
      final rid = t.receiptId;
      if (rid != null && rid.isNotEmpty && (counts[rid] ?? 0) >= 2) {
        if (seen.add(rid)) {
          units.add(_Unit.group(
              rid, rows.where((x) => x.receiptId == rid).toList()));
        }
      } else {
        units.add(_Unit.single(t));
      }
    }
    return units;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final u in _units)
          if (u.isGroup)
            _ReceiptGroupRow(
              members: u.members!,
              total: u.total,
              expanded: _expanded.contains(u.receiptId),
              onToggle: () => setState(() {
                if (!_expanded.remove(u.receiptId)) {
                  _expanded.add(u.receiptId!);
                }
              }),
              onTapChild: widget.onTapRow,
            )
          else
            _ExpenseRow(
              t: u.single!,
              onTap: () => widget.onTapRow(u.single!),
            ),
      ],
    );
  }
}

/// レシートまとめの親行（枠付きカード・タップで内訳を開閉）。
/// 品目ごとは別取引なので、分析・集計はカテゴリ別に正しく分かれる。
class _ReceiptGroupRow extends StatelessWidget {
  final List<core.Transaction> members;
  final int total;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(core.Transaction t) onTapChild;
  const _ReceiptGroupRow({
    required this.members,
    required this.total,
    required this.expanded,
    required this.onToggle,
    required this.onTapChild,
  });

  String _catLabel(core.Category c) {
    final major = c.major.trim();
    final sub = c.sub.trim();
    if (major.isEmpty && sub.isEmpty) return '未分類';
    if (sub.isEmpty) return major;
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    final first = members.first;
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    // 店舗が無ければ、カテゴリ大分類（混在時は「まとめ記録」）を見出しに。
    final majors = members.map((t) => t.category.major.trim()).toSet();
    final title = store.isNotEmpty
        ? store
        : (majors.length == 1 && majors.first.isNotEmpty
            ? majors.first
            : 'まとめ記録');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        margin:
            const EdgeInsets.fromLTRB(V2Spacing.md, 0, V2Spacing.md, 8),
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: V2Colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 38,
                  child: Text('${first.date.month}/${first.date.day}',
                      style: V2Typography.numericCell),
                ),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: V2Colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('🧾 ${members.length}件',
                            style: V2Typography.micro),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(title,
                            style: V2Typography.body,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: V2Spacing.sm),
                // トグルアイコンは出さない（金額位置を単品行と揃えるため）。
                // 行タップで開閉する挙動はそのまま。
                Text('-${formatYen(total)}',
                    style: V2Typography.numericCell.copyWith(
                        color: V2Colors.negative,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              for (final t in members)
                InkWell(
                  onTap: () => onTapChild(t),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 0, 2),
                    child: Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right_rounded,
                            size: 15, color: Color(0xFFC7CCD6)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: V2Colors.surfaceMuted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(_catLabel(t.category),
                              style: V2Typography.micro),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.description.isEmpty ? '—' : t.description,
                            style: V2Typography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('-${formatYen(t.amount)}',
                            style: V2Typography.numericCell.copyWith(
                                color: V2Colors.negative,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatefulWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  const _ExpenseRow({
    required this.t,
    required this.onTap,
  });

  @override
  State<_ExpenseRow> createState() => _ExpenseRowState();
}

class _ExpenseRowState extends State<_ExpenseRow> {
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
            color: _hover ? V2Colors.hover : V2Colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: V2Colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 日付（M/D）
              SizedBox(
                width: 38,
                child: Text(
                    '${widget.t.date.month}/${widget.t.date.day}',
                    style: V2Typography.numericCell),
              ),
              const SizedBox(width: V2Spacing.sm),
              // 中央: カテゴリバッジ＋内容（支払方法は非表示）
              Expanded(
                child: Row(
                  children: [
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
              // 金額（右・固定幅なしで見切れ防止）
              Text(
                '-${formatYen(widget.t.amount)}',
                style: V2Typography.numericCell.copyWith(
                    color: V2Colors.negative,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
