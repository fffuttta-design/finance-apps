import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/expense_input_screen.dart';
import '../../screens/expense_list_screen.dart';
import '../../screens/income_input_screen.dart';
import '../../screens/transfer_input_screen.dart';
import '../../utils/formatters.dart';
import '../../utils/modal_input.dart';
import '../../utils/thousands_separator_input_formatter.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/date_weekday_text.dart';
import '../../widgets/subscription_edit_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/credit_card_reconcile.dart';
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
    with ModeAwareMixin, SingleTickerProviderStateMixin {
  TabController? _subTabController;
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
  void onModeChanged() {
    _rebuildSubTabController();
    _load();
  }

  bool get _isBusiness =>
      AppModeManager.instance.current == AppMode.business;

  void _rebuildSubTabController() {
    _subTabController?.dispose();
    if (_isBusiness) {
      _subTabController = TabController(length: 2, vsync: this);
    } else {
      _subTabController = null;
    }
  }

  @override
  void initState() {
    super.initState();
    // Web/Electron で行を右クリックしたとき、ブラウザ標準メニューが
    // 編集・削除メニューに被らないよう無効化する。
    if (kIsWeb) BrowserContextMenu.disableContextMenu();
    _rebuildSubTabController();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subTabController?.dispose();
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

  /// 当月の支出＋振替（明細一覧の表示用）。
  /// 合計（経費）は _monthExpenses のみで計算し、振替は金額に足さない。
  List<core.Transaction> get _monthEntries {
    return _transactions
        .where((t) =>
            (t.type == core.TransactionType.expense ||
                t.type == core.TransactionType.transfer) &&
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

  /// 明細の編集：種別ごとの入力画面（各項目を編集できる画面）を開く。
  /// 詳細画面は廃止し、右クリック/長押しのコンテキストメニューからここを呼ぶ。
  Future<void> _editTxn(core.Transaction t) async {
    bool? changed;
    if (t.type == core.TransactionType.transfer) {
      // 振替は専用エディタで編集（汎用の支出エディタは振替を扱えない）。
      changed = await showTransferInputModal(context, editing: t);
    } else if (t.type == core.TransactionType.expense) {
      changed =
          await showInputSheet<bool>(context, ExpenseInputScreen(editing: t));
    } else {
      // 収入
      changed =
          await showInputSheet<bool>(context, IncomeInputScreen(editing: t));
    }
    if (changed == true && mounted) await _load();
  }

  /// 明細の削除：確認ダイアログ → 削除 → 再読込。
  Future<void> _deleteTxn(core.Transaction t) async {
    final signed = t.type == core.TransactionType.expense
        ? '-${formatYen(t.amount)}'
        : formatYen(t.amount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('この明細を削除しますか？'),
        content: Text(
            '「${t.description.isEmpty ? t.category.major : t.description}」'
            ' / $signed\nこの操作は取り消せません。'),
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
    try {
      await TransactionRepository.instance.delete(t.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
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
      cards[cIdx] = cards[cIdx].copyWith(
          monthlyActualBillings: upd(cards[cIdx].monthlyActualBillings));
      await _settings.savePayments(_payments.copyWith(creditCards: cards));
      if (mounted) await _load();
      return;
    }
    final bIdx = _payments.bankAccounts.indexWhere((b) => b.name == name);
    if (bIdx >= 0) {
      final banks = [..._payments.bankAccounts];
      banks[bIdx] = banks[bIdx].copyWith(
          monthlyActualBillings: upd(banks[bIdx].monthlyActualBillings));
      await _settings.savePayments(_payments.copyWith(bankAccounts: banks));
      if (mounted) await _load();
    }
  }

  /// ウォレット照合シートを開く。
  Future<void> _openCardReconcile(ReconcileWallet wallet) async {
    final ym = _ymKey;
    await showCardReconcileSheet(
      context,
      wallet: wallet,
      initialActual: _initialActualFor(wallet.name, ym),
      ym: ym,
      onSaveActual: (amount) => _saveWalletActual(wallet.name, ym, amount),
      onEditTxn: _editTxn,
      onDeleteTxn: _deleteTxn,
      onAddAdjustment: (amount, {description, date}) => _addCardAdjustment(
          wallet.name, amount,
          description: description, date: date),
    );
    if (mounted) await _load();
  }

  /// 差額ぶんの「調整取引」を追加する。支払方法＝当ウォレット。
  Future<void> _addCardAdjustment(String walletName, int amount,
      {String? description, DateTime? date}) async {
    final fallbackDate = DateTime(_focused.year, _focused.month + 1, 0);
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

  /// 外注費カテゴリ判定（大カテゴリが "0.外注費" 相当）。
  bool _isGaichu(core.Transaction t) =>
      t.category.major.contains('外注費');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final expenses = _monthExpenses;
    final entries = _monthEntries;
    final total = expenses.fold<int>(0, (s, t) => s + t.amount);
    final fixedTotal =
        _monthlyCharges.fold<int>(0, (s, c) => s + c.amountForMonth(_ymKey));

    // 月切替バー（諸経費/外注費 共通）
    final monthBar = V2Card(
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
            style: V2Typography.h2.copyWith(color: V2Colors.textPrimary),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: () => _shiftMonth(1),
          ),
          Text('合計',
              style: V2Typography.caption
                  .copyWith(color: V2Colors.textSecondary)),
          const SizedBox(width: V2Spacing.sm),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                  formatYen(-(total + fixedTotal), withSign: true),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: V2Colors.negative,
                      fontFeatures: V2Typography.tabularNums)),
            ),
          ),
        ],
      ),
    );

    // 事業モード: 諸経費/外注費 サブタブ
    if (_isBusiness && _subTabController != null) {
      final gaichuEntries =
          entries.where(_isGaichu).toList();
      final gaichuExpenses =
          expenses.where(_isGaichu).toList();
      final shokeihiEntries =
          entries.where((t) => !_isGaichu(t)).toList();
      final shokeihiExpenses =
          expenses.where((t) => !_isGaichu(t)).toList();
      final shokeihiTotal =
          shokeihiExpenses.fold<int>(0, (s, t) => s + t.amount);
      final gaichuTotal =
          gaichuExpenses.fold<int>(0, (s, t) => s + t.amount);

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                V2Spacing.md, V2Spacing.xl, V2Spacing.md, 0),
            child: monthBar,
          ),
          const SizedBox(height: V2Spacing.sm),
          // サブタブバー
          Container(
            color: V2Colors.surface,
            child: TabBar(
              controller: _subTabController,
              labelColor: widget.accent,
              unselectedLabelColor: V2Colors.textSecondary,
              indicatorColor: widget.accent,
              tabs: [
                Tab(
                    text:
                        '諸経費　${formatYen(shokeihiTotal + fixedTotal)}'),
                Tab(text: '外注費　${formatYen(gaichuTotal)}'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _subTabController,
              children: [
                // ── 諸経費タブ ──
                _buildScrollBody(
                  entries: shokeihiEntries,
                  total: shokeihiTotal,
                  label: '諸経費明細',
                  showFixed: true,
                  showCardBilling: true,
                ),
                // ── 外注費タブ ──
                _buildScrollBody(
                  entries: gaichuEntries,
                  total: gaichuTotal,
                  label: '外注費明細',
                  showFixed: false,
                  showCardBilling: false,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 個人モード: 従来レイアウト（月切替バーを上部に含む）
    return _buildScrollBody(
      entries: entries,
      total: total,
      label: '支出明細',
      showFixed: true,
      showCardBilling: true,
      topWidget: Padding(
        padding: const EdgeInsets.only(bottom: V2Spacing.sm),
        child: monthBar,
      ),
    );
  }

  /// スクロールコンテンツ本体。諸経費・外注費・個人モードで共用。
  Widget _buildScrollBody({
    required List<core.Transaction> entries,
    required int total,
    required String label,
    required bool showFixed,
    required bool showCardBilling,
    Widget? topWidget,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.xl, horizontal: V2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topWidget != null) topWidget,
          // ── クレカ引落照合 ────────────────────
          if (showCardBilling) ...[
            CreditCardBillingSection(
              cards: _payments.creditCards
                  .where((c) => !c.inactive)
                  .toList(),
              bankAccounts: _payments.bankAccounts
                  .where((b) => !b.inactive)
                  .toList(),
              transactions: _transactions,
              subscriptions: _subscriptions.subscriptions,
              ym: _ymKey,
              onOpenReconcile: _openCardReconcile,
            ),
            const SizedBox(height: V2Spacing.lg),
          ],
          // ── 毎月支出予定 ──────────────────
          if (showFixed && _monthlyCharges.isNotEmpty) ...[
            _MonthlyChargesSection(
              charges: _monthlyCharges,
              onTapItem: _openSubscriptionEdit,
              isCurrentMonth: _focused.year == DateTime.now().year &&
                  _focused.month == DateTime.now().month,
              ym: _ymKey,
              onInputVariable: _inputVariableActual,
            ),
            const SizedBox(height: V2Spacing.lg),
          ],
          // ── 取引一覧 ────────────────────
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
                      Icon(Icons.receipt_long_outlined,
                          size: 18, color: widget.accent),
                      const SizedBox(width: V2Spacing.sm),
                      Expanded(
                          child: Text(label, style: V2Typography.h2)),
                      Text('-${formatYen(total)}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: V2Colors.negative,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: V2Spacing.sm),
                        Text('${_focused.month}月の記録なし',
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.textSecondary)),
                      ],
                    ),
                  )
                else
                  _ExpensesTable(
                    rows: entries,
                    onEditTxn: _editTxn,
                    onDeleteTxn: _deleteTxn,
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
// 毎月引落予定セクション（固定費 / 変動費）
// ═════════════════════════════════════════════════

/// 毎月支出予定の並び替えモード。
enum _ChargeSort { amountDesc, amountAsc, majorAsc, majorDesc, dayAsc, dayDesc }

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

    int byDay(core.Subscription a, core.Subscription b, bool asc) {
      final ad = a.billingDay, bd = b.billingDay;
      // 引落日 未設定は常に末尾へ。
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return asc ? ad.compareTo(bd) : bd.compareTo(ad);
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
      case _ChargeSort.dayAsc:
        l.sort((a, b) => byDay(a, b, true));
        break;
      case _ChargeSort.dayDesc:
        l.sort((a, b) => byDay(a, b, false));
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
      case _ChargeSort.dayAsc:
        return '引落日↑';
      case _ChargeSort.dayDesc:
        return '引落日↓';
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
                      value: _ChargeSort.dayAsc,
                      child: Text('引落日が早い順')),
                  PopupMenuItem(
                      value: _ChargeSort.dayDesc,
                      child: Text('引落日が遅い順')),
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

/// 明細行のコンテキストメニュー（編集 / 削除）を画面位置に表示する。
/// PC=右クリック、スマホ=長押し の両方からここを呼ぶ。
Future<void> _showTxnContextMenu(
  BuildContext context,
  Offset globalPos, {
  required core.Transaction txn,
  required void Function(core.Transaction) onEdit,
  required void Function(core.Transaction) onDelete,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: const [
      PopupMenuItem(
        value: 'edit',
        child: Row(children: [
          Icon(Icons.edit_outlined, size: 18, color: Color(0xFF374151)),
          SizedBox(width: 10),
          Text('編集'),
        ]),
      ),
      PopupMenuItem(
        value: 'delete',
        child: Row(children: [
          Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
          SizedBox(width: 10),
          Text('削除', style: TextStyle(color: Color(0xFFDC2626))),
        ]),
      ),
    ],
  );
  if (selected == 'edit') {
    onEdit(txn);
  } else if (selected == 'delete') {
    onDelete(txn);
  }
}

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
  // 明細の編集・削除（右クリック/長押しのコンテキストメニューから呼ぶ）。
  final void Function(core.Transaction t) onEditTxn;
  final void Function(core.Transaction t) onDeleteTxn;
  const _ExpensesTable({
    required this.rows,
    required this.onEditTxn,
    required this.onDeleteTxn,
  });

  @override
  State<_ExpensesTable> createState() => _ExpensesTableState();
}

/// 並び替えモード。
enum _ExpenseSort {
  dateDesc,   // 日付 新→旧（既定）
  dateAsc,    // 日付 古→新
  amountDesc, // 金額 高→低
  amountAsc,  // 金額 低→高
  majorAsc,   // カテゴリ順
}

extension _ExpenseSortLabel on _ExpenseSort {
  String get label {
    switch (this) {
      case _ExpenseSort.dateDesc:   return '日付 新→旧';
      case _ExpenseSort.dateAsc:    return '日付 古→新';
      case _ExpenseSort.amountDesc: return '金額 高→低';
      case _ExpenseSort.amountAsc:  return '金額 低→高';
      case _ExpenseSort.majorAsc:   return 'カテゴリ順';
    }
  }
}

class _ExpensesTableState extends State<_ExpensesTable> {
  _ExpenseSort _sort = _ExpenseSort.dateDesc;

  /// 展開中のまとめ行（receiptId）。トグルで開閉する。
  final Set<String> _expanded = {};

  void _toggleExpand(String receiptId) {
    setState(() {
      if (!_expanded.remove(receiptId)) _expanded.add(receiptId);
    });
  }

  /// rows をソートしてから unit に変換。
  List<_Unit> get _units {
    final rows = List<core.Transaction>.from(widget.rows);
    switch (_sort) {
      case _ExpenseSort.dateDesc:
        rows.sort((a, b) => b.date.compareTo(a.date));
      case _ExpenseSort.dateAsc:
        rows.sort((a, b) => a.date.compareTo(b.date));
      case _ExpenseSort.amountDesc:
        rows.sort((a, b) => b.amount.compareTo(a.amount));
      case _ExpenseSort.amountAsc:
        rows.sort((a, b) => a.amount.compareTo(b.amount));
      case _ExpenseSort.majorAsc:
        rows.sort((a, b) => a.category.major.compareTo(b.category.major));
    }
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

  /// 日付ヘッダーをタップしたときのソートトグル。
  void _toggleDateSort() {
    setState(() {
      _sort = _sort == _ExpenseSort.dateDesc
          ? _ExpenseSort.dateAsc
          : _ExpenseSort.dateDesc;
    });
  }

  /// 金額ヘッダーをタップしたときのソートトグル。
  void _toggleAmountSort() {
    setState(() {
      _sort = _sort == _ExpenseSort.amountDesc
          ? _ExpenseSort.amountAsc
          : _ExpenseSort.amountDesc;
    });
  }

  /// モバイル用：並び替えチップ行。
  Widget _sortChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(V2Spacing.md, 0, V2Spacing.md, V2Spacing.sm),
      child: Row(
        children: _ExpenseSort.values.map((s) {
          final selected = _sort == s;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _sort = s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? V2Colors.accent.withValues(alpha: 0.12) : V2Colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? V2Colors.accent : V2Colors.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    color: selected ? V2Colors.accent : V2Colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    if (isWide) {
      return _WideExpenseTable(
        units: _units,
        expanded: _expanded,
        onToggleExpand: _toggleExpand,
        onEditTxn: widget.onEditTxn,
        onDeleteTxn: widget.onDeleteTxn,
        sort: _sort,
        onToggleDateSort: _toggleDateSort,
        onToggleAmountSort: _toggleAmountSort,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sortChips(),
        for (final u in _units)
          if (u.isGroup)
            _ReceiptGroupRow(
              members: u.members!,
              total: u.total,
              expanded: _expanded.contains(u.receiptId),
              onToggle: () => _toggleExpand(u.receiptId!),
              onEditTxn: widget.onEditTxn,
              onDeleteTxn: widget.onDeleteTxn,
            )
          else
            _ExpenseRow(
              t: u.single!,
              onEditTxn: widget.onEditTxn,
              onDeleteTxn: widget.onDeleteTxn,
            ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// PC ワイド表示：表形式レイアウト（幅 ≥ 700px）
// ─────────────────────────────────────────────────────────

/// 列ドラッグハンドル。
/// ⚠️ behavior:opaque を付けないと「中央の細い線」しか掴めず、ほぼ無反応になる。
/// 全幅をヒット領域にして掴みやすくする。
class _ColHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  const _ColHandle({required this.onDrag});
  static const double w = 12;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: SizedBox(
          width: w,
          height: 24,
          child: Center(
            child: Container(
                width: 1.5,
                height: 16,
                color: const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
  }
}

class _WideExpenseTable extends StatefulWidget {
  final List<_Unit> units;

  /// 展開中のまとめ行（receiptId）。
  final Set<String> expanded;
  final void Function(String receiptId) onToggleExpand;
  final void Function(core.Transaction) onEditTxn;
  final void Function(core.Transaction) onDeleteTxn;
  final _ExpenseSort sort;
  final VoidCallback onToggleDateSort;
  final VoidCallback onToggleAmountSort;

  const _WideExpenseTable({
    required this.units,
    required this.expanded,
    required this.onToggleExpand,
    required this.onEditTxn,
    required this.onDeleteTxn,
    required this.sort,
    required this.onToggleDateSort,
    required this.onToggleAmountSort,
  });

  @override
  State<_WideExpenseTable> createState() => _WideExpenseTableState();
}

class _WideExpenseTableState extends State<_WideExpenseTable> {
  // 親カテ / 子カテ / タイトル / 支払い方法 / 金額（px）。全列ドラッグで可変。
  final List<double> _w = [120.0, 110.0, 240.0, 140.0, 104.0];
  // ホバー中の行キー（単品=t.id、まとめ見出し='g:'+rid、内訳='m:'+t.id）。
  final Set<String> _hovered = {};

  // タイトル列の先頭に置くトグル/インデント枠の固定幅（行同士の桁を揃える）。
  static const double _leadW = 22;

  static const double _dateW = 78;
  static const double _hPad = 14;
  static const double _minColW = 50;
  static const Color _borderColor = Color(0xFFCBD5E1);

  static const _hStyle = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8));

  // ドラッグ: i列とi+1列の間のハンドル。i+1が無ければi列のみ伸縮。
  void _onDrag(int i, double dx) {
    setState(() {
      final next = i + 1;
      if (next < _w.length) {
        final maxDelta = _w[next] - _minColW;
        final minDelta = _minColW - _w[i];
        final d = dx.clamp(minDelta, maxDelta);
        _w[i] += d;
        _w[next] -= d;
      } else {
        _w[i] = (_w[i] + dx).clamp(_minColW, 500.0);
      }
    });
  }

  static Color _catColor(String key) {
    if (key.isEmpty) return const Color(0xFF94A3B8);
    int hash = 0;
    for (final c in key.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1.0, (hash % 360).toDouble(), 0.55, 0.48)
        .toColor();
  }

  static String _bare(String s) {
    final m = RegExp(r'^\d+\.').firstMatch(s);
    return m != null ? s.substring(m.end).trim() : s;
  }

  /// 背景色付きカテゴリバッジ。
  static Widget _catBadge(String text, Color color) {
    if (text.isEmpty) return const Text('—', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          overflow: TextOverflow.ellipsis),
    );
  }

  // ── ヘッダー行 ──────────────────────────────────
  Widget _sortIcon(_ExpenseSort asc, _ExpenseSort desc) {
    final s = widget.sort;
    if (s == asc) return const Icon(Icons.arrow_upward, size: 11, color: Color(0xFF64748B));
    if (s == desc) return const Icon(Icons.arrow_downward, size: 11, color: Color(0xFF64748B));
    return const Icon(Icons.unfold_more, size: 11, color: Color(0xFFCBD5E1));
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: _borderColor, width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        GestureDetector(
          onTap: widget.onToggleDateSort,
          child: SizedBox(
            width: _dateW + _hPad,
            child: Padding(
              padding: const EdgeInsets.only(left: _hPad),
              child: Row(children: [
                const Text('日付', style: _hStyle),
                const SizedBox(width: 3),
                _sortIcon(_ExpenseSort.dateAsc, _ExpenseSort.dateDesc),
              ]),
            ),
          ),
        ),
        SizedBox(width: _ColHandle.w),
        SizedBox(width: _w[0], child: const Text('親カテゴリ', style: _hStyle, overflow: TextOverflow.ellipsis)),
        _ColHandle(onDrag: (dx) => _onDrag(0, dx)),
        SizedBox(width: _w[1], child: const Text('子カテゴリ', style: _hStyle, overflow: TextOverflow.ellipsis)),
        _ColHandle(onDrag: (dx) => _onDrag(1, dx)),
        SizedBox(width: _w[2], child: const Text('タイトル', style: _hStyle, overflow: TextOverflow.ellipsis)),
        _ColHandle(onDrag: (dx) => _onDrag(2, dx)),
        SizedBox(width: _w[3], child: const Text('支払い方法', style: _hStyle, overflow: TextOverflow.ellipsis)),
        _ColHandle(onDrag: (dx) => _onDrag(3, dx)),
        GestureDetector(
          onTap: widget.onToggleAmountSort,
          child: SizedBox(
            width: _w[4] + _hPad,
            child: Padding(
              padding: const EdgeInsets.only(right: _hPad),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _sortIcon(_ExpenseSort.amountAsc, _ExpenseSort.amountDesc),
                const SizedBox(width: 3),
                const Text('金額', textAlign: TextAlign.right, style: _hStyle),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // タイトル列先頭のリード（行の桁を揃える固定枠）。
  Widget _chevron(bool expanded) => Icon(
      expanded ? Icons.expand_more : Icons.chevron_right,
      size: 18,
      color: const Color(0xFF64748B));
  static const Widget _leadEmpty = SizedBox.shrink();
  static const Widget _memberMark = Padding(
    padding: EdgeInsets.only(left: 4),
    child: Icon(Icons.subdirectory_arrow_right,
        size: 13, color: Color(0xFFB6C0CC)),
  );

  // ── 行共通レイアウト helper ──────────────────────
  Widget _rowLayout({
    required String rowKey,
    required DateTime date,
    required Widget majorCell,
    required Widget subCell,
    required Widget leading,
    required Widget titleCell,
    required Widget payCell,
    required String amountText,
    required bool isTransfer,
    required bool isLast,
    Color? bg,
    VoidCallback? onTap,
    core.Transaction? menuTxn,
  }) {
    final hov = _hovered.contains(rowKey);
    void openMenu(Offset pos) {
      if (menuTxn == null) return;
      _showTxnContextMenu(context, pos,
          txn: menuTxn,
          onEdit: widget.onEditTxn,
          onDelete: widget.onDeleteTxn);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered.add(rowKey)),
      onExit: (_) => setState(() => _hovered.remove(rowKey)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapDown:
            menuTxn == null ? null : (d) => openMenu(d.globalPosition),
        onLongPressStart:
            menuTxn == null ? null : (d) => openMenu(d.globalPosition),
        child: Container(
          decoration: BoxDecoration(
            color: hov ? V2Colors.hover : (bg ?? V2Colors.surface),
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(color: _borderColor, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: _dateW + _hPad,
              child: Padding(
                padding: const EdgeInsets.only(left: _hPad),
                child:
                    dateWeekdayText(date, baseStyle: V2Typography.numericCell),
              ),
            ),
            SizedBox(width: _ColHandle.w),
            SizedBox(width: _w[0], child: majorCell),
            SizedBox(width: _ColHandle.w),
            SizedBox(width: _w[1], child: subCell),
            SizedBox(width: _ColHandle.w),
            SizedBox(
              width: _w[2],
              child: Row(children: [
                SizedBox(width: _leadW, child: leading),
                Expanded(child: titleCell),
              ]),
            ),
            SizedBox(width: _ColHandle.w),
            SizedBox(width: _w[3], child: payCell),
            SizedBox(width: _ColHandle.w),
            SizedBox(
              width: _w[4] + _hPad,
              child: Padding(
                padding: const EdgeInsets.only(right: _hPad),
                child: Text(
                  amountText,
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                    color: isTransfer ? V2Colors.textBody : V2Colors.negative,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── 単品行 ──────────────────────────────────────
  // 左クリックは何もしない。右クリック/長押しで編集・削除メニュー。
  Widget _singleRow(core.Transaction t, {required bool isLast}) {
    final isTransfer = t.type == core.TransactionType.transfer;
    final majorRaw = t.category.major.trim();
    final sub = t.category.sub.trim();
    final color = _catColor(majorRaw);
    final bare = _bare(majorRaw);

    return _rowLayout(
      rowKey: 's:${t.id}',
      date: t.date,
      majorCell: isTransfer
          ? const SizedBox.shrink()
          : _catBadge(bare, color),
      subCell: isTransfer
          ? Row(children: [
              const Icon(Icons.swap_horiz, size: 13, color: V2Colors.info),
              const SizedBox(width: 3),
              Text('振替',
                  style:
                      V2Typography.caption.copyWith(color: V2Colors.info)),
            ])
          : Text(sub.isEmpty ? '—' : sub,
              style: V2Typography.caption
                  .copyWith(color: V2Colors.textSecondary),
              overflow: TextOverflow.ellipsis),
      leading: _leadEmpty,
      titleCell: Text(
        t.description.isEmpty ? '—' : t.description,
        style: V2Typography.body.copyWith(fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
      payCell: Text(t.paymentMethod,
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          overflow: TextOverflow.ellipsis),
      amountText: isTransfer
          ? formatYen(t.amount)
          : '-${formatYen(t.amount)}',
      isTransfer: isTransfer,
      isLast: isLast,
      menuTxn: t,
    );
  }

  // ── 内訳行（まとめを展開したときの各品目）──────────────
  Widget _memberRow(core.Transaction t, {required bool isLast}) {
    final sub = t.category.sub.trim();
    final majorRaw = t.category.major.trim();
    final color = _catColor(majorRaw);
    final bare = _bare(majorRaw);

    return _rowLayout(
      rowKey: 'm:${t.id}',
      date: t.date,
      majorCell: _catBadge(bare, color),
      subCell: Text(sub.isEmpty ? '—' : sub,
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          overflow: TextOverflow.ellipsis),
      leading: _memberMark,
      titleCell: Text(
        t.description.isEmpty ? '—' : t.description,
        style: V2Typography.body.copyWith(
            fontWeight: FontWeight.w500, color: V2Colors.textSecondary),
        overflow: TextOverflow.ellipsis,
      ),
      payCell: Text(t.paymentMethod,
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          overflow: TextOverflow.ellipsis),
      amountText: '-${formatYen(t.amount)}',
      isTransfer: false,
      isLast: isLast,
      bg: const Color(0xFFF8FAFC),
      menuTxn: t,
    );
  }

  // ── まとめ見出し行 ────────────────────────────────
  // タップ（先頭トグル）で内訳を開閉。見出し自体は編集・削除しない。
  Widget _groupHeaderRow(_Unit u, {required bool isLast}) {
    final members = u.members!;
    final first = members.first;
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final title = store.isNotEmpty ? store : 'まとめ記録';

    final counts = <String, int>{};
    for (final t in members) {
      final m = t.category.major.trim();
      if (m.isNotEmpty) counts[m] = (counts[m] ?? 0) + 1;
    }
    final dominant = counts.isEmpty
        ? ''
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final color = _catColor(dominant);
    final bare = _bare(dominant);
    final subs = members.map((t) => t.category.sub.trim()).toSet();
    final sub = subs.length == 1 && subs.first.isNotEmpty ? subs.first : '—';
    final methods = members.map((t) => t.paymentMethod).toSet();
    final isExpanded = widget.expanded.contains(u.receiptId);

    return _rowLayout(
      rowKey: 'g:${u.receiptId}',
      date: first.date,
      majorCell: _catBadge(bare, color),
      subCell: Text(sub,
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          overflow: TextOverflow.ellipsis),
      leading: _chevron(isExpanded),
      titleCell: Row(children: [
        Expanded(
          child: Text(title,
              style:
                  V2Typography.body.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Text('${members.length}件',
            style: V2Typography.micro
                .copyWith(color: V2Colors.textSecondary)),
      ]),
      payCell: Text(methods.length == 1 ? methods.first : '複数',
          style: V2Typography.caption
              .copyWith(color: V2Colors.textSecondary),
          overflow: TextOverflow.ellipsis),
      amountText: '-${formatYen(u.total)}',
      isTransfer: false,
      isLast: isLast,
      onTap: () => widget.onToggleExpand(u.receiptId!),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 行を平坦化（まとめは見出し＋展開時は内訳）。最後の行だけ下線を消す。
    final rows = <Widget Function(bool isLast)>[];
    for (final u in widget.units) {
      if (u.isGroup) {
        rows.add((isLast) => _groupHeaderRow(u, isLast: isLast));
        if (widget.expanded.contains(u.receiptId)) {
          for (final m in u.members!) {
            rows.add((isLast) => _memberRow(m, isLast: isLast));
          }
        }
      } else {
        rows.add((isLast) => _singleRow(u.single!, isLast: isLast));
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: V2Spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: _borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            for (int i = 0; i < rows.length; i++) rows[i](i == rows.length - 1),
          ],
        ),
      ),
    );
  }
}

/// レシートまとめの親行（枠付きカード）。先頭トグルで内訳を開閉。
/// 内訳の各品目を長押し/右クリックで編集・削除。
/// 品目ごとは別取引なので、分析・集計はカテゴリ別に正しく分かれる。
class _ReceiptGroupRow extends StatelessWidget {
  final List<core.Transaction> members;
  final int total;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(core.Transaction) onEditTxn;
  final void Function(core.Transaction) onDeleteTxn;
  const _ReceiptGroupRow({
    required this.members,
    required this.total,
    required this.expanded,
    required this.onToggle,
    required this.onEditTxn,
    required this.onDeleteTxn,
  });

  /// 件数カウントが最多の大カテゴリを返す（同率は最初に現れたもの優先）。
  String _dominantMajor() {
    final counts = <String, int>{};
    for (final t in members) {
      final m = t.category.major.trim();
      if (m.isNotEmpty) counts[m] = (counts[m] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// 大カテゴリ名の先頭 "N." プレフィックスを除去。
  String _bareMajor(String s) {
    final m = RegExp(r'^\d+\.').firstMatch(s);
    return m != null ? s.substring(m.end).trim() : s;
  }

  /// 大カテゴリ名からハッシュで安定した色を生成。
  Color _categoryColor(String key) {
    if (key.isEmpty) return V2Colors.textSecondary;
    int hash = 0;
    for (final c in key.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1.0, (hash % 360).toDouble(), 0.55, 0.48)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final first = members.first;
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    // 店舗が無ければ「まとめ記録」を見出しに。
    final title = store.isNotEmpty ? store : 'まとめ記録';

    final dominant = _dominantMajor();
    final bareCategory = _bareMajor(dominant);
    // カテゴリラベル：最多大カテゴリ > 小カテゴリ（全件同一のみ）
    final subs = members.map((t) => t.category.sub.trim()).toSet();
    final subLabel = subs.length == 1 && subs.first.isNotEmpty ? subs.first : '';
    final categoryLabel = bareCategory.isEmpty
        ? '未分類'
        : (subLabel.isEmpty ? bareCategory : '$bareCategory > $subLabel');

    return Container(
      margin: const EdgeInsets.fromLTRB(V2Spacing.md, 0, V2Spacing.md, 8),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 見出し（タップで開閉）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 52,
                    child: dateWeekdayText(first.date,
                        baseStyle: V2Typography.numericCell),
                  ),
                  const SizedBox(width: V2Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title,
                                  style: V2Typography.body.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            Text('${members.length}件',
                                style: V2Typography.micro.copyWith(
                                    color: V2Colors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: _categoryColor(dominant),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                categoryLabel,
                                style: V2Typography.micro
                                    .copyWith(color: V2Colors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: V2Spacing.sm),
                  Text('-${formatYen(total)}',
                      style: V2Typography.numericCell.copyWith(
                          color: V2Colors.negative,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          // 内訳（展開時のみ）。各品目を長押し/右クリックで編集・削除。
          if (expanded)
            for (final m in members) _memberTile(context, m),
        ],
      ),
    );
  }

  /// 内訳の1品目。
  Widget _memberTile(BuildContext context, core.Transaction t) {
    void openMenu(Offset pos) => _showTxnContextMenu(context, pos,
        txn: t, onEdit: onEditTxn, onDelete: onDeleteTxn);
    final cat = _bareMajor(t.category.major.trim());
    final sub = t.category.sub.trim();
    final label = cat.isEmpty
        ? '未分類'
        : (sub.isEmpty ? cat : '$cat > $sub');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) => openMenu(d.globalPosition),
      onLongPressStart: (d) => openMenu(d.globalPosition),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          border: Border(top: BorderSide(color: V2Colors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(36, 8, V2Spacing.md, 8),
        child: Row(
          children: [
            const Icon(Icons.subdirectory_arrow_right,
                size: 14, color: Color(0xFFB6C0CC)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.description.isEmpty ? '—' : t.description,
                      style: V2Typography.body.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                  Text(label,
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('-${formatYen(t.amount)}',
                style: V2Typography.numericCell.copyWith(
                    color: V2Colors.negative,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatefulWidget {
  final core.Transaction t;
  // 左タップは何もしない。長押し/右クリックで編集・削除メニュー。
  final void Function(core.Transaction) onEditTxn;
  final void Function(core.Transaction) onDeleteTxn;
  const _ExpenseRow({
    required this.t,
    required this.onEditTxn,
    required this.onDeleteTxn,
  });

  @override
  State<_ExpenseRow> createState() => _ExpenseRowState();
}

class _ExpenseRowState extends State<_ExpenseRow> {
  bool _hover = false;

  String _categoryLabel() {
    final major = _bareMajor(widget.t.category.major.trim());
    final sub = widget.t.category.sub.trim();
    if (major.isEmpty && sub.isEmpty) return '未分類';
    if (sub.isEmpty) return major;
    return '$major > $sub';
  }

  /// 先頭の "N." 番号プレフィックスを除去。
  String _bareMajor(String s) {
    final m = RegExp(r'^\d+\.').firstMatch(s);
    return m != null ? s.substring(m.end).trim() : s;
  }

  /// 大カテゴリ名からハッシュで安定した色を生成（HSL）。
  Color _categoryColor() {
    final key = _bareMajor(widget.t.category.major.trim());
    if (key.isEmpty) return V2Colors.textSecondary;
    int hash = 0;
    for (final c in key.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.48).toColor();
  }

  @override
  Widget build(BuildContext context) {
    // 振替は「支出」と区別して表示する（バッジ色・金額色・符号）。
    final isTransfer = widget.t.type == core.TransactionType.transfer;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => _showTxnContextMenu(context, d.globalPosition,
            txn: widget.t,
            onEdit: widget.onEditTxn,
            onDelete: widget.onDeleteTxn),
        onLongPressStart: (d) => _showTxnContextMenu(context, d.globalPosition,
            txn: widget.t,
            onEdit: widget.onEditTxn,
            onDelete: widget.onDeleteTxn),
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
              // 日付（M/D(曜)）。土=青/日=赤。
              SizedBox(
                width: 58,
                child: dateWeekdayText(widget.t.date,
                    baseStyle: V2Typography.numericCell),
              ),
              const SizedBox(width: V2Spacing.sm),
              // 中央: 1行目=取引内容、2行目=カテゴリ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.t.description.isEmpty
                          ? '—'
                          : widget.t.description,
                      style: V2Typography.body.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (isTransfer) ...[
                          const Icon(Icons.swap_horiz,
                              size: 11, color: V2Colors.info),
                          const SizedBox(width: 2),
                          Text('振替',
                              style: V2Typography.micro
                                  .copyWith(color: V2Colors.info)),
                        ] else ...[
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: _categoryColor(),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _categoryLabel(),
                              style: V2Typography.micro.copyWith(
                                  color: V2Colors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              // 金額（右）。振替はお金の移動なのでマイナスを付けず中立色に。
              Text(
                isTransfer
                    ? formatYen(widget.t.amount)
                    : '-${formatYen(widget.t.amount)}',
                style: V2Typography.numericCell.copyWith(
                    color:
                        isTransfer ? V2Colors.textBody : V2Colors.negative,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
