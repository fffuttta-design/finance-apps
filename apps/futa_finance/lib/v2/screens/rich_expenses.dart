import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/month_cursor.dart';
import '../../data/nav_history.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/account_detail_screen.dart';
import '../../screens/card_detail_screen.dart';
import '../../screens/expense_input_screen.dart';
import '../../screens/subscription_list_screen.dart';
import '../../screens/transaction_detail_screen.dart';
import '../../utils/emoji_palette.dart';
import '../../utils/formatters.dart';
import '../../utils/modal_input.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/credit_card_reconcile.dart';
import '../widgets/expense_detail_table.dart';
import '../widgets/month_closing_bar.dart';
import '../widgets/month_nav_bar.dart';

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
  /// 大カテゴリ名 → アイコンキー（カテゴリ内訳のアイコン表示用）。
  Map<String, String?> _catIcons = {};
  bool _loading = true;

  /// 支出合計カードの内訳を展開しているか。
  bool _summaryOpen = false;

  /// 事業モードの諸経費/制作原価サブタブ（個人モードは null）。
  TabController? _subTab;

  // タブ横断で月を共有（切替で今月にリセットされないよう共有カーソルを初期値に）。
  late DateTime _month = MonthCursor.instance.month;

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
    final cats = await _settings.loadCategories();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _subs = subs.subscriptions;
      _payments = payments;
      _catIcons = {for (final m in cats.majors) m.name: m.iconKey};
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    MonthCursor.instance.month = _month; // タブ横断で共有
  }

  int _subsOf(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    return _subs.fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
  }

  /// 指定月に計上される固定費（サブスク）の明細（名前・金額・アイコン）。金額降順。
  /// サマリー展開の1行（ラベル＋金額）。
  /// 内訳セクションの小見出し（種類別／支払方法別）。
  Widget _breakdownHeader(IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 14, color: widget.accent),
          const SizedBox(width: 6),
          Text(label,
              style: V2Typography.micro.copyWith(
                  color: V2Colors.textSecondary, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _summaryLine(String label, int amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
                    color: V2Colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: V2Typography.tabularNums)),
          ],
        ),
      );

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

  /// 指定月に計上される固定費を、明細テーブルに混ぜる用の行に変換する。
  /// 日付＝請求日（billingDay／年払いは nextBillingDate）。無ければ月初。
  List<FixedCostRow> _fixedTableRows(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
    final rows = <FixedCostRow>[];
    for (final sub in _subs) {
      final amt = sub.plAmountForMonth(ym, curYm);
      if (amt <= 0) continue;
      DateTime date;
      if (sub.cycle == core.SubscriptionCycle.annually &&
          sub.nextBillingDate != null) {
        date = sub.nextBillingDate!;
      } else {
        final day = (sub.billingDay ?? 1).clamp(1, daysInMonth);
        date = DateTime(m.year, m.month, day);
      }
      // 小カテゴリ列に出す科目／グループ（会計科目を優先、無ければカテゴリ）。
      final label = (sub.plMajor ?? '').trim().isNotEmpty
          ? sub.plMajor!.trim()
          : (sub.category ?? '').trim();
      rows.add(FixedCostRow(
        id: sub.id,
        name: sub.name.trim().isEmpty ? '固定費' : sub.name.trim(),
        amount: amt,
        date: date,
        paymentMethod: sub.paymentMethod,
        categoryLabel: label,
        sortOrder: sub.sortOrder,
      ));
    }
    return rows;
  }

  /// 手動並び替えの保存。取引は取引の sortOrder、固定費はサブスクの sortOrder。
  Future<void> _saveReorder(List<ReorderedItem> dayInNewOrder) async {
    final subOrders = <String, double>{};
    for (int i = 0; i < dayInNewOrder.length; i++) {
      final item = dayInNewOrder[i];
      if (item.isFixed) {
        subOrders[item.subscriptionId!] = i.toDouble();
      } else {
        await _txRepo.update(item.txn!.copyWith(sortOrder: i.toDouble()));
      }
    }
    if (subOrders.isNotEmpty) {
      final cfg = await SubscriptionRepository.instance.load();
      final newSubs = cfg.subscriptions
          .map((s) => subOrders.containsKey(s.id)
              ? s.copyWith(sortOrder: subOrders[s.id])
              : s)
          .toList();
      await SubscriptionRepository.instance
          .save(core.SubscriptionConfig(subscriptions: newSubs));
    }
    if (mounted) await _load();
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

  /// ウォレット名から、その月の「実際額」を引く（カード/銀行どちらでも）。
  int? _initialActualFor(String name, String ym) {
    for (final c in _payments.creditCards) {
      if (c.name == name) return c.monthlyActualBillings[ym];
    }
    for (final b in _payments.bankAccounts) {
      if (b.name == name) return b.monthlyActualBillings[ym];
    }
    return null;
  }

  /// ウォレット（カード/銀行/現金/電子マネー）の実際額を保存する。
  Future<void> _saveWalletActual(String name, String ym, int? amount) async {
    Map<String, int> upd(Map<String, int> m) {
      final n = Map<String, int>.from(m);
      if (amount == null || amount <= 0) {
        n.remove(ym);
      } else {
        n[ym] = amount;
      }
      return n;
    }

    final cIdx = _payments.creditCards.indexWhere((c) => c.name == name);
    if (cIdx >= 0) {
      final cards = [..._payments.creditCards];
      cards[cIdx] = cards[cIdx]
          .copyWith(monthlyActualBillings: upd(cards[cIdx].monthlyActualBillings));
      await _settings.savePayments(_payments.copyWith(creditCards: cards));
      if (mounted) await _load();
      return;
    }
    final bIdx = _payments.bankAccounts.indexWhere((b) => b.name == name);
    if (bIdx >= 0) {
      final banks = [..._payments.bankAccounts];
      banks[bIdx] = banks[bIdx]
          .copyWith(monthlyActualBillings: upd(banks[bIdx].monthlyActualBillings));
      await _settings.savePayments(_payments.copyWith(bankAccounts: banks));
      if (mounted) await _load();
    }
  }

  /// ウォレットの行をタップ → まず詳細画面（明細一覧）へ。
  /// クレカ＝CardDetailScreen（そこから「突合」を選べる）。
  /// 銀行/現金/電子マネー＝AccountDetailScreen（通帳）。突合は不要・自力で追える。
  /// 未登録の支払方法（手入力のPayPay等）は詳細画面が無いので照合シートを直接開く。
  Future<void> _openCardReconcile(ReconcileWallet wallet) async {
    for (final c in _payments.creditCards) {
      if (c.name == wallet.name) {
        NavHistory.instance.push(context, (_) => CardDetailScreen(card: c),
            onReturn: () {
          if (mounted) _load();
        });
        return;
      }
    }
    for (final b in _payments.bankAccounts) {
      if (b.name == wallet.name) {
        NavHistory.instance.push(
            context, (_) => AccountDetailScreen(account: b), onReturn: () {
          if (mounted) _load();
        });
        return;
      }
    }
    // 未登録の支払方法：詳細画面が無いので、従来どおり簡易の照合シート。
    final ym = _ymKey;
    await showCardReconcileSheet(
      context,
      wallet: wallet,
      initialActual: _initialActualFor(wallet.name, ym),
      ym: ym,
      onSaveActual: (amount) => _saveWalletActual(wallet.name, ym, amount),
      onEditTxn: _edit,
      onDeleteTxn: _deleteTxn,
      onAddAdjustment: (amount, {description, date}) => _addCardAdjustment(
          wallet.name, amount,
          description: description, date: date),
    );
    if (mounted) await _load();
  }

  /// 差額ぶんの「調整取引」を追加する（記録漏れ補完）。
  /// 支払方法＝当ウォレット／日付＝表示月末をプリフィルした支出入力を開く。
  Future<void> _addCardAdjustment(String walletName, int amount,
      {String? description, DateTime? date}) async {
    final fallbackDate = DateTime(_month.year, _month.month + 1, 0);
    final changed = await showInputSheet<bool>(
      context,
      ExpenseInputScreen(
        initialPaymentMethod: walletName,
        initialAmount: amount > 0 ? amount : null,
        initialDate: date ?? fallbackDate,
        initialDescription: description ?? '差額調整',
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
              // 月セレクタ＋締めは、諸経費/制作原価タブより「上」に配置する。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V2Spacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: MonthNavBar(
                          label: '${_month.year}年${_month.month}月',
                          onPrev: () => _shiftMonth(-1),
                          onNext: () => _shiftMonth(1),
                        ),
                      ),
                    ),
                    MonthClosingBar(
                        month: _month,
                        snapshotExpense: keihiTotal + gaichuTotal,
                        dense: true),
                  ],
                ),
              ),
              const SizedBox(height: 4),
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
                        detailLabel: '経費明細',
                        showTopHeader: false),
                    _buildBody(
                        rows: gaichu,
                        showFixedAndCard: false,
                        title: null,
                        detailLabel: '制作原価明細',
                        showTopHeader: false),
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
    // 事業モードは月セレクタ＋締めをタブより上に出すため、本文側では隠す。
    bool showTopHeader = true,
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

    // 支払方法別（取引＋固定費）。サマリーの展開で「どの財布から出たか」を表示。
    final byPayment = <String, int>{};
    for (final t in rows) {
      final pm =
          t.paymentMethod.trim().isEmpty ? '未設定' : t.paymentMethod.trim();
      byPayment[pm] = (byPayment[pm] ?? 0) + t.amount;
    }
    if (showFixedAndCard) {
      final now = DateTime.now();
      final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final ym = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      for (final s in _subs) {
        final amt = s.plAmountForMonth(ym, curYm);
        if (amt <= 0) continue;
        final pm = (s.paymentMethod ?? '').trim().isEmpty
            ? '未設定'
            : s.paymentMethod!.trim();
        byPayment[pm] = (byPayment[pm] ?? 0) + amt;
      }
    }
    final paymentEntries = byPayment.entries.toList()
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
              // タブ上部：タイトル（個人モードのみ）＋ 中央に月セレクタ（資産タブと
              // 同じシンプルな見た目）＋ 右上に締め処理チップ。
              // 事業モードでは月セレクタをタブより上に出すため、ここは省略する。
              if (showTopHeader) ...[
                Row(
                  children: [
                    if (title != null)
                      Text(title,
                          style: V2Typography.h1
                              .copyWith(color: V2Colors.textPrimary)),
                    Expanded(
                      child: Center(
                        child: MonthNavBar(
                          label: '${_month.year}年${_month.month}月',
                          onPrev: () => _shiftMonth(-1),
                          onNext: () => _shiftMonth(1),
                        ),
                      ),
                    ),
                    MonthClosingBar(
                        month: _month, snapshotExpense: total, dense: true),
                  ],
                ),
                const SizedBox(height: V2Spacing.md),
              ],
              // サマリー（タップで内訳を展開）
              Container(
                decoration: BoxDecoration(
                  color: V2Colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: V2Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () =>
                          setState(() => _summaryOpen = !_summaryOpen),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(V2Spacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_month.month}月の$summaryLabel合計',
                                style: V2Typography.caption.copyWith(
                                    color: V2Colors.textSecondary)),
                            const SizedBox(height: 6),
                            Text(formatYen(total),
                                style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                    color: V2Colors.textPrimary,
                                    fontFeatures: V2Typography.tabularNums)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                // 「明細◯件＋固定費◯円」は内訳を開けば分かるので省略。
                                const Spacer(),
                                Text(_summaryOpen ? '内訳を閉じる' : '内訳を見る',
                                    style: V2Typography.micro
                                        .copyWith(color: widget.accent)),
                                Icon(
                                    _summaryOpen
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: widget.accent),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_summaryOpen) ...[
                      const Divider(height: 1, color: V2Colors.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(V2Spacing.lg, 12,
                            V2Spacing.lg, V2Spacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── 種類別（変動費 / 固定費）──
                            _breakdownHeader(Icons.donut_small_outlined, '種類別'),
                            const SizedBox(height: 6),
                            if (subTotal > 0)
                              _summaryLine('固定費（サブスク）', subTotal),
                            _summaryLine(
                                '変動費（各種支出${rows.length}件）', txTotal),
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: V2Colors.divider),
                            const SizedBox(height: 14),
                            // ── 支払方法別 ──
                            _breakdownHeader(
                                Icons.account_balance_wallet_outlined, '支払方法別'),
                            const SizedBox(height: 6),
                            for (final e in paymentEntries)
                              _summaryLine(e.key, e.value),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: V2Spacing.xl),
              // カテゴリ内訳（支出合計の直下）
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
                          // カテゴリのアイコンと色（固定費は合算なので汎用）。
                          iconKey: e.key == '固定費・サブスク'
                              ? null
                              : _catIcons[e.key],
                          barColor: e.key == '固定費・サブスク'
                              ? accent
                              : expenseCatColor(e.key),
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
                                  // 展開明細は金額の高い順に並べる。
                                  for (final t in ([
                                    ...?txnsByMajor[e.key]
                                  ]..sort((a, b) =>
                                      b.amount.compareTo(a.amount))))
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
                const SizedBox(height: V2Spacing.xl),
              ],
              // ウォレット（クレカ引落照合・棚卸し）— カテゴリ内訳の下
              if (showFixedAndCard) ...[
                CreditCardBillingSection(
                  cards: _payments.creditCards
                      .where((c) => !c.inactive)
                      .toList(),
                  bankAccounts: _payments.bankAccounts
                      .where((b) => !b.inactive)
                      .toList(),
                  transactions: _transactions,
                  subscriptions: _subs,
                  ym: _ymKey,
                  onOpenReconcile: _openCardReconcile,
                ),
                const SizedBox(height: V2Spacing.xl),
              ],
              // 毎月の固定費（引落予定）— 見出しはカード外・クレカ引落照合と同じスタイル
              if (fixedLines.isNotEmpty) ...[
                Padding(
                  // 右の合計は、下の各行の金額（カード余白12+矢印16+間隔4=32）に
                  // 合わせて内側に寄せ、カード右端からはみ出さないようにする。
                  padding: const EdgeInsets.only(right: 32, bottom: V2Spacing.sm),
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
                const SizedBox(height: V2Spacing.xl),
              ],
              // 明細（PC幅＝表形式。検索・並び替え・列幅は共通ウィジェットに集約）。
              // 固定費（引落予定）も淡色で混ぜて表示し、明細チェック時に
              // 「固定費が計上されているか」を同じ表で確認できるようにする。
              ExpenseDetailTable(
                title: detailLabel,
                rows: rows,
                onEditTxn: _edit,
                accent: accent,
                fixedRows: showFixedAndCard
                    ? _fixedTableRows(_month)
                    : const <FixedCostRow>[],
                onEditFixed: (f) => _editSubscription(f.id),
                emptyHint: '${_month.month}月の記録はまだありません',
                // 事業モードのみ、領収書/レシート保存済みチェック列（税理士提出用）。
                showReceiptCheck: _isBusiness,
                onToggleReceipt: (t, v) async {
                  await _txRepo.update(t.copyWith(receiptSaved: v));
                  if (mounted) await _load();
                },
                // 確認済み（検収）チェック：締め処理で1件ずつ確認する用途。
                onToggleReviewed: (t, v) async {
                  await _txRepo.update(t.copyWith(reviewed: v));
                  if (mounted) await _load();
                },
                // 同じ日付内の手動並び替え：新しい順で sortOrder を 0,1,2… と振る。
                // 取引は取引に、固定費はサブスクに保存する。
                onReorderDay: _saveReorder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _CatBar extends StatefulWidget {
  final String name;
  final int value;
  final double ratio;
  final Color accent;

  /// カテゴリのアイコンキー（絵文字/URL/Material名）。null は汎用アイコン。
  final String? iconKey;

  /// バーの色（カテゴリ色）。
  final Color barColor;

  /// 展開時に表示する内訳（取引行など）。空ならタップで展開しない。
  final List<Widget> details;
  const _CatBar({
    required this.name,
    required this.value,
    required this.ratio,
    required this.accent,
    required this.iconKey,
    required this.barColor,
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
                    // トグル矢印は出さず、行クリックで開閉する。
                    // カテゴリアイコン（色付き丸背景）。
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: widget.barColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: widget.iconKey != null &&
                              widget.iconKey!.isNotEmpty
                          ? categoryIconWidget(widget.iconKey,
                              size: 15, color: widget.barColor)
                          : Icon(Icons.event_repeat,
                              size: 14, color: widget.barColor),
                    ),
                    const SizedBox(width: 8),
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
                    valueColor: AlwaysStoppedAnimation(widget.barColor),
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

