import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/expense_input_screen.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/subscription_list_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/formatters.dart';
import '../../utils/modal_input.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/credit_card_reconcile.dart';

/// 新デザイン（リッチUI）の経費／支出タブ。
/// 月サマリー → カテゴリ内訳 → 明細リスト。既存 V2ExpensesScreen は温存。
class RichExpensesScreen extends StatefulWidget {
  final Color accent;
  const RichExpensesScreen({super.key, required this.accent});

  @override
  State<RichExpensesScreen> createState() => _RichExpensesScreenState();
}

class _RichExpensesScreenState extends State<RichExpensesScreen>
    with ModeAwareMixin, SingleTickerProviderStateMixin {
  final _txRepo = TransactionRepository.instance;
  final _settings = SettingsRepository();

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  List<core.Subscription> _subs = [];
  core.PaymentMethodsConfig _payments = core.PaymentMethodsConfig.empty();
  bool _loading = true;

  /// 事業モードの諸経費/制作原価サブタブ（個人モードは null）。
  TabController? _subTab;

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _ymKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isBusiness =>
      AppModeManager.instance.current == AppMode.business;

  /// 制作原価（外注費）判定。
  bool _isGaichu(core.Transaction t) => t.category.major.contains('外注費');

  void _rebuildSubTab() {
    _subTab?.dispose();
    _subTab = _isBusiness ? TabController(length: 2, vsync: this) : null;
  }

  @override
  void onModeChanged() {
    _rebuildSubTab();
    _load();
  }

  @override
  void initState() {
    super.initState();
    _rebuildSubTab();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subTab?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final subs = await SubscriptionRepository.instance.load();
    final payments = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _subs = subs.subscriptions;
      _payments = payments;
      _loading = false;
    });
  }

  /// クレカ照合に表示するカードが当月あるか（無ければセクション余白を出さない）。
  bool get _hasReconcileCards {
    final ym = _ymKey;
    for (final c in _payments.creditCards) {
      if (c.inactive) continue;
      if (c.monthlyActualBillings.containsKey(ym)) return true;
      final planned = _transactions
          .where((t) =>
              t.type == core.TransactionType.expense &&
              t.paymentMethod == c.name &&
              t.date.year == _month.year &&
              t.date.month == _month.month)
          .fold<int>(0, (s, t) => s + t.amount);
      if (planned > 0) return true;
    }
    return false;
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  int _subsOf(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    return _subs.fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
  }

  /// 指定月に計上される固定費（サブスク）の明細（名前・金額・アイコン）。金額降順。
  List<({String id, String name, int amount, String? iconUrl})>
      _fixedLinesForMonth(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final lines = <({String id, String name, int amount, String? iconUrl})>[];
    for (final sub in _subs) {
      final amt = sub.plAmountForMonth(ym, curYm);
      if (amt > 0) {
        lines.add((
          id: sub.id,
          name: sub.name.trim().isEmpty ? '固定費' : sub.name,
          amount: amt,
          iconUrl: sub.iconUrl,
        ));
      }
    }
    lines.sort((a, b) => b.amount.compareTo(a.amount));
    return lines;
  }

  /// 固定費（サブスク）の編集画面をディープリンクで開く。
  Future<void> _editSubscription(String id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => SubscriptionListScreen(initialEditId: id)),
    );
    if (mounted) await _load();
  }

  List<core.Transaction> get _monthExpenses => _transactions
      .where((t) =>
          t.type == core.TransactionType.expense &&
          t.date.year == _month.year &&
          t.date.month == _month.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> _edit(core.Transaction t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: t)),
    );
    if (changed == true && mounted) await _load();
  }

  /// 明細の削除（確認 → 削除 → 再読込）。
  Future<void> _deleteTxn(core.Transaction t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('この明細を削除しますか？'),
        content: Text(
            '「${t.description.isEmpty ? t.category.major : t.description}」'
            ' / -${formatYen(t.amount)}\nこの操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _txRepo.delete(t.id);
    if (mounted) await _load();
  }

  /// クレカの実際請求金額を保存する。
  Future<void> _saveCreditCardActual(
      core.RegisteredCreditCard card, String ym, int? amount) async {
    final idx = _payments.creditCards.indexWhere((c) => c.id == card.id);
    if (idx < 0) return;
    final m = Map<String, int>.from(card.monthlyActualBillings);
    if (amount == null || amount <= 0) {
      m.remove(ym);
    } else {
      m[ym] = amount;
    }
    final newCards = [..._payments.creditCards];
    newCards[idx] = card.copyWith(monthlyActualBillings: m);
    await _settings.savePayments(_payments.copyWith(creditCards: newCards));
    if (mounted) await _load();
  }

  /// クレカ引落の棚卸しシートを開く。
  Future<void> _openCardReconcile(core.RegisteredCreditCard card) async {
    final ym = _ymKey;
    await showCardReconcileSheet(
      context,
      card: card,
      ym: ym,
      onSaveActual: (amount) => _saveCreditCardActual(card, ym, amount),
      onEditTxn: _edit,
      onDeleteTxn: _deleteTxn,
      onAddAdjustment: (amount, {description, date}) => _addCardAdjustment(
          card, amount,
          description: description, date: date),
    );
    if (mounted) await _load();
  }

  /// 差額ぶんの「調整取引」を追加する（記録漏れ補完）。
  /// 支払方法＝当カード／日付＝表示月末をプリフィルした支出入力を開く。
  Future<void> _addCardAdjustment(
      core.RegisteredCreditCard card, int amount,
      {String? description, DateTime? date}) async {
    final fallbackDate = DateTime(_month.year, _month.month + 1, 0);
    final changed = await showInputSheet<bool>(
      context,
      ExpenseInputScreen(
        initialPaymentMethod: card.name,
        initialAmount: amount > 0 ? amount : null,
        initialDate: date ?? fallbackDate,
        initialDescription: description ?? 'クレカ差額調整',
      ),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // 事業モード: 諸経費 / 制作原価（外注費）サブタブ
    if (_isBusiness && _subTab != null) {
      final all = _monthExpenses;
      final gaichu = all.where(_isGaichu).toList();
      final keihi = all.where((t) => !_isGaichu(t)).toList();
      final keihiTotal =
          keihi.fold<int>(0, (s, t) => s + t.amount) + _subsOf(_month);
      final gaichuTotal = gaichu.fold<int>(0, (s, t) => s + t.amount);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    V2Spacing.md, V2Spacing.lg, V2Spacing.md, V2Spacing.sm),
                child: Text('経費',
                    style:
                        V2Typography.h1.copyWith(color: V2Colors.textPrimary)),
              ),
              TabBar(
                controller: _subTab,
                labelColor: widget.accent,
                unselectedLabelColor: V2Colors.textSecondary,
                indicatorColor: widget.accent,
                tabs: [
                  Tab(text: '諸経費　${formatYen(keihiTotal)}'),
                  Tab(text: '制作原価　${formatYen(gaichuTotal)}'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _subTab,
                  children: [
                    _buildBody(
                        rows: keihi,
                        showFixedAndCard: true,
                        title: null,
                        detailLabel: '経費明細'),
                    _buildBody(
                        rows: gaichu,
                        showFixedAndCard: false,
                        title: null,
                        detailLabel: '制作原価明細'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 個人モード（従来レイアウト）
    return _buildBody(
        rows: _monthExpenses,
        showFixedAndCard: true,
        title: '支出',
        detailLabel: '支出明細');
  }

  /// 支出本文（タブ共用）。title が null ならタイトル見出しは出さない（タブ側で表示済）。
  /// showFixedAndCard=false（制作原価タブ）では固定費・クレカ照合を出さない。
  Widget _buildBody({
    required List<core.Transaction> rows,
    required bool showFixedAndCard,
    required String? title,
    required String detailLabel,
  }) {
    final accent = widget.accent;
    final summaryLabel = detailLabel.replaceAll('明細', '');
    final txTotal = rows.fold<int>(0, (s, t) => s + t.amount);
    final subTotal = showFixedAndCard ? _subsOf(_month) : 0;
    final total = txTotal + subTotal;
    final fixedLines = showFixedAndCard
        ? _fixedLinesForMonth(_month)
        : <({String id, String name, int amount, String? iconUrl})>[];

    // カテゴリ内訳（大カテゴリ別・固定費込み）＋ドリルダウン用の取引一覧。
    final byMajor = <String, int>{};
    final txnsByMajor = <String, List<core.Transaction>>{};
    for (final t in rows) {
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.amount;
      (txnsByMajor[major] ??= []).add(t);
    }
    if (subTotal > 0) {
      byMajor['固定費・サブスク'] = (byMajor['固定費・サブスク'] ?? 0) + subTotal;
    }
    final majorEntries = byMajor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.lg, horizontal: V2Spacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(title,
                    style:
                        V2Typography.h1.copyWith(color: V2Colors.textPrimary)),
                const SizedBox(height: V2Spacing.md),
              ],
              // サマリー
              Container(
                padding: const EdgeInsets.all(V2Spacing.lg),
                decoration: BoxDecoration(
                  color: V2Colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: V2Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${_month.month}月の$summaryLabel合計',
                            style: V2Typography.caption
                                .copyWith(color: V2Colors.textSecondary)),
                        const Spacer(),
                        _MiniStepper(
                          label: '${_month.year}年${_month.month}月',
                          onPrev: () => _shiftMonth(-1),
                          onNext: () => _shiftMonth(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(formatYen(total),
                        style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: V2Colors.textPrimary,
                            fontFeatures: V2Typography.tabularNums)),
                    const SizedBox(height: 6),
                    Text(
                        '明細 ${rows.length}件'
                        '${subTotal > 0 ? ' ＋ 固定費 ${formatYen(subTotal)}' : ''}',
                        style: V2Typography.micro
                            .copyWith(color: V2Colors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: V2Spacing.md),
              // クレカ引落照合・棚卸し（支出合計のすぐ下・目立つ位置）
              if (showFixedAndCard) ...[
                CreditCardBillingSection(
                  cards: _payments.creditCards
                      .where((c) => !c.inactive)
                      .toList(),
                  transactions: _transactions,
                  subscriptions: _subs,
                  ym: _ymKey,
                  onOpenReconcile: _openCardReconcile,
                ),
                if (_hasReconcileCards) const SizedBox(height: V2Spacing.md),
              ],
              // カテゴリ内訳（見出しはカード外・クレカ引落照合と同じスタイル）
              if (majorEntries.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.donut_small_outlined,
                          size: 18, color: V2Colors.textSecondary),
                      const SizedBox(width: V2Spacing.sm),
                      Text('カテゴリ内訳',
                          style: V2Typography.h2
                              .copyWith(color: V2Colors.textPrimary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(V2Spacing.md),
                  decoration: BoxDecoration(
                    color: V2Colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in majorEntries.take(8))
                        _CatBar(
                          name: e.key,
                          value: e.value,
                          ratio: total == 0 ? 0 : e.value / total,
                          accent: accent,
                          // 展開時の内訳はホームと同じシンプルな1行（日付＋名前＋金額）。
                          details: e.key == '固定費・サブスク'
                              ? [
                                  for (final f in fixedLines)
                                    _CatDetailRow(
                                        label: f.name,
                                        amount: f.amount,
                                        onTap: () => _editSubscription(f.id)),
                                ]
                              : [
                                  for (final t
                                      in (txnsByMajor[e.key] ?? const []))
                                    _CatDetailRow(
                                        label: t.description.trim().isEmpty
                                            ? formatMonthDay(t.date)
                                            : '${formatMonthDay(t.date)}  ${t.description.trim()}',
                                        amount: t.amount,
                                        onTap: () => _edit(t)),
                                ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
              ],
              // 毎月の固定費（引落予定）— 見出しはカード外・クレカ引落照合と同じスタイル
              if (fixedLines.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.repeat,
                          size: 18, color: V2Colors.textSecondary),
                      const SizedBox(width: V2Spacing.sm),
                      Text('毎月の固定費（引落予定）',
                          style: V2Typography.h2
                              .copyWith(color: V2Colors.textPrimary)),
                      const Spacer(),
                      Text(formatYen(subTotal),
                          style: V2Typography.bodyStrong.copyWith(
                              color: V2Colors.textPrimary,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(V2Spacing.md),
                  decoration: BoxDecoration(
                    color: V2Colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < fixedLines.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: V2Colors.divider),
                        InkWell(
                          onTap: () => _editSubscription(fixedLines[i].id),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                BrandLogo(
                                  iconUrl: fixedLines[i].iconUrl,
                                  fallbackIcon: Icons.subscriptions_outlined,
                                  size: 20,
                                  borderRadius: 5,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(fixedLines[i].name,
                                      style: V2Typography.body,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Text(formatYen(fixedLines[i].amount),
                                    style: V2Typography.caption.copyWith(
                                        color: V2Colors.textSecondary,
                                        fontFeatures:
                                            V2Typography.tabularNums)),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    size: 16, color: V2Colors.textMuted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
              ],
              // 明細（左アクセント＋大›小バッジ＋支払チップの独立カード）
              Row(
                children: [
                  Text(detailLabel,
                      style: V2Typography.h2
                          .copyWith(color: V2Colors.textPrimary)),
                  const Spacer(),
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExpenseListScreen(
                            title: '$detailLabel一覧',
                            month: _month,
                          ),
                        ),
                      );
                      await _load();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Text('一覧',
                              style: V2Typography.caption
                                  .copyWith(color: accent)),
                          Icon(Icons.chevron_right, size: 16, color: accent),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.sm),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: V2Colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: 8),
                        Text('${_month.month}月の記録はまだありません',
                            style: V2Typography.caption
                                .copyWith(color: V2Colors.textSecondary)),
                      ],
                    ),
                  ),
                )
              else
                for (final t in rows) _ExpenseRow(t: t, onTap: () => _edit(t)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MiniStepper(
      {required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon: const Icon(Icons.chevron_left, color: V2Colors.textSecondary),
          onPressed: onPrev,
        ),
        Text(label,
            style:
                V2Typography.bodyStrong.copyWith(color: V2Colors.textPrimary)),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon:
              const Icon(Icons.chevron_right, color: V2Colors.textSecondary),
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _CatBar extends StatefulWidget {
  final String name;
  final int value;
  final double ratio;
  final Color accent;

  /// 展開時に表示する内訳（取引行など）。空ならタップで展開しない。
  final List<Widget> details;
  const _CatBar({
    required this.name,
    required this.value,
    required this.ratio,
    required this.accent,
    this.details = const [],
  });

  @override
  State<_CatBar> createState() => _CatBarState();
}

class _CatBarState extends State<_CatBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.details.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: canExpand ? () => setState(() => _open = !_open) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              children: [
                Row(
                  children: [
                    if (canExpand)
                      Icon(_open ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: V2Colors.textMuted),
                    if (canExpand) const SizedBox(width: 2),
                    Expanded(
                      child: Text(widget.name,
                          style: V2Typography.body,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text('${(widget.ratio * 100).round()}%',
                        style: V2Typography.micro
                            .copyWith(color: V2Colors.textMuted)),
                    const SizedBox(width: 10),
                    Text(formatYen(widget.value),
                        style: V2Typography.caption.copyWith(
                            color: V2Colors.textSecondary,
                            fontFeatures: V2Typography.tabularNums)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: widget.ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: V2Colors.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(widget.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.details),
          ),
      ],
    );
  }
}

/// カテゴリ内訳の展開内訳1行（ホームと同じシンプルな見た目）。任意でタップ編集。
class _CatDetailRow extends StatelessWidget {
  final String label;
  final int amount;
  final VoidCallback? onTap;
  const _CatDetailRow(
      {required this.label, required this.amount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(formatYen(amount),
                style: V2Typography.caption.copyWith(
                    color: V2Colors.textSecondary,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      ),
    );
  }
}

// ── 明細行のリッチ表示（左アクセント＋大›小バッジ＋支払チップ） ──

/// 大カテゴリ名から安定した色を作る。
Color _richCatColor(String major) {
  final m = major.trim();
  if (m.isEmpty) return const Color(0xFF9CA3AF);
  var h = 0;
  for (final c in m.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.45).toColor();
}

/// 支払方法に合うアイコン。
IconData _richPaymentIcon(String method) {
  final s = method.toLowerCase();
  if (method.contains('現金')) return Icons.payments_outlined;
  if (method.contains('カード') ||
      method.contains('クレカ') ||
      method.contains('オリコ') ||
      s.contains('card') ||
      s.contains('visa')) {
    return Icons.credit_card;
  }
  if (method.contains('銀行') ||
      method.contains('振込') ||
      method.contains('引落')) {
    return Icons.account_balance_outlined;
  }
  if (s.contains('suica') ||
      s.contains('paypay') ||
      method.contains('電子') ||
      method.contains('チャージ')) {
    return Icons.contactless_outlined;
  }
  return Icons.payment_outlined;
}

/// 「大カテゴリ › 小カテゴリ」の色付きバッジ。
Widget _richCatBadge(core.Category c, Color color) {
  final major = c.major.trim();
  final sub = c.sub.trim();
  final label = (major.isEmpty && sub.isEmpty)
      ? '未分類'
      : (sub.isEmpty ? major : '$major › $sub');
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.30)),
    ),
    child: Text(label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: HSLColor.fromColor(color).withLightness(0.32).toColor())),
  );
}

/// 支払方法チップ（アイコン＋名称）。
Widget _richPaymentChip(String method) {
  final m = method.trim();
  if (m.isEmpty) return const SizedBox.shrink();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_richPaymentIcon(m), size: 12, color: const Color(0xFF64748B)),
        const SizedBox(width: 3),
        Text(m,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B))),
      ],
    ),
  );
}

class _ExpenseRow extends StatelessWidget {
  final core.Transaction t;
  final VoidCallback onTap;
  const _ExpenseRow({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = _richCatColor(t.category.major);
    final sub = t.category.sub.trim();
    final major = t.category.major.trim();
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (sub.isNotEmpty ? sub : (major.isNotEmpty ? major : '未分類'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: V2Colors.border),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(formatMonthDay(t.date),
                                style: V2Typography.micro.copyWith(
                                    color: V2Colors.textSecondary,
                                    fontFeatures: V2Typography.tabularNums)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title,
                                    style: V2Typography.body.copyWith(
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 3,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _richCatBadge(t.category, accent),
                                    _richPaymentChip(t.paymentMethod),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('-${formatYen(t.amount)}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: V2Colors.negative,
                                  fontFeatures: V2Typography.tabularNums)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
