import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/month_closing_repository.dart';
import '../../data/month_cursor.dart';
import '../../data/nav_history.dart';
import '../../data/settings_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../data/ui_preferences.dart';
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

/// サマリーの「高額明細」に出す下限（実質負担がこの額以上の取引を並べる）。
const int _kBigAmount = 10000;

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
  // 月締めの状態（締め済みの月は本体をグレーアウトするのに使う）。
  core.MonthClosingConfig _closing = core.MonthClosingConfig.empty();
  bool _loading = true;

  bool get _isMonthClosed =>
      _closing.forMonth(_month.year, _month.month)?.isClosed ?? false;

  /// この月に「締め済み」のウォレット名（口座 `w:` / カード `card:` 複合キーから抽出）。
  Set<String> get _closedWalletNames {
    final suffix = ':$_ymKey';
    final names = <String>{};
    for (final c in _closing.closings) {
      if (!c.isClosed) continue;
      final k = c.yearMonth;
      if (!k.endsWith(suffix)) continue;
      if (k.startsWith('w:')) {
        names.add(k.substring(2, k.length - suffix.length));
      } else if (k.startsWith('card:')) {
        names.add(k.substring(5, k.length - suffix.length));
      }
    }
    return names;
  }

  /// 支出合計カードの内訳を展開しているか。
  bool _summaryOpen = false;

  /// 事業モードの諸経費/制作原価サブタブ（個人モードは null）。
  TabController? _subTab;

  // タブ横断で月を共有（切替で今月にリセットされないよう共有カーソルを初期値に）。
  late DateTime _month = MonthCursor.instance.month;

  String get _ymKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  /// 全体締めの前に締めておくべきウォレット（当月に動きがあるものだけ）。
  /// 締めキーは account_detail / card_detail と同じ w:/card: 形式。
  List<({String key, String label})> _walletsToClose() {
    final y = _month.year, mo = _month.month;
    final monthTx = _transactions
        .where((t) => t.date.year == y && t.date.month == mo)
        .toList();
    final out = <({String key, String label})>[];
    for (final b in _payments.bankAccounts) {
      if (b.inactive) continue;
      final active = monthTx.any((t) =>
          t.paymentMethod == b.name ||
          t.transferFromAccount == b.name ||
          t.transferToAccount == b.name);
      if (active) out.add((key: 'w:${b.name}:$_ymKey', label: b.name));
    }
    for (final c in _payments.creditCards) {
      if (c.inactive) continue;
      final active = monthTx.any((t) =>
          t.paymentMethod == c.name || t.transferToAccount == c.name);
      if (active) out.add((key: 'card:${c.name}:$_ymKey', label: c.name));
    }
    return out;
  }

  bool get _isBusiness =>
      AppModeManager.instance.current == AppMode.business;

  /// 制作原価判定。大分類が「外注費／売上原価／制作原価」いずれかを含めば原価扱い。
  /// （既存データは大分類が「売上原価」表記のものがあるため両対応する）
  bool _isGaichu(core.Transaction t) {
    final m = t.category.major;
    return m.contains('外注費') || m.contains('売上原価') || m.contains('制作原価');
  }

  // ── 家賃（個人モードのハズレ値）を隠す機能 ──────────────────
  /// 家賃とみなすキーワード。ユーザーは「家賃＝共同生活費」として運用しているため
  /// 「共同生活費」等も同一視して除外対象にする。
  /// 「ナカネ」は共同生活費（家賃）の振込先名義（摘要「振込 ナカネ ハルカ」）。
  /// 銀行CSV取込の家賃振込を"家賃を除く"で拾うために含める。
  static const _rentKeywords = ['家賃', '共同生活費', '共同生活', 'ナカネ'];

  /// 文字列がいずれかの家賃キーワードを含むか。
  bool _matchesRent(String? s) =>
      s != null && _rentKeywords.any((k) => s.contains(k));

  /// 家賃の取引か（大／小カテゴリ・摘要のいずれかにキーワードを含む）。
  bool _isRentTx(core.Transaction t) =>
      _matchesRent(t.category.sub) ||
      _matchesRent(t.category.major) ||
      _matchesRent(t.description);

  /// 家賃の固定費（サブスク）か（名称／カテゴリ／会計科目にキーワードを含む）。
  bool _isRentSub(core.Subscription s) =>
      _matchesRent(s.name) ||
      _matchesRent(s.category) ||
      _matchesRent(s.plMajor);

  /// 家賃を隠す表示が有効か（個人モードのみ・設定 ON のとき）。
  bool get _rentHidden => !_isBusiness && UiPreferences.instance.hideRent;

  // ── 税務顧問料（事業モードのハズレ値）を隠す機能 ──────────────
  /// 税務顧問料とみなすキーワード（大/小カテゴリ・摘要のいずれかに含めば対象）。
  /// ⚠️ 実データの摘要は「VS税務顧問」（"料"なし）なので "税務顧問" で拾う
  /// （"税務顧問料" だと一致しない）。"顧問料"/"税理士" も念のため残す。
  static const _advisoryKeywords = ['税務顧問', '顧問料', '税理士'];

  bool _matchesAdvisory(String? s) =>
      s != null && _advisoryKeywords.any((k) => s.contains(k));

  /// 税務顧問料の取引か。
  bool _isAdvisoryTx(core.Transaction t) =>
      _matchesAdvisory(t.category.sub) ||
      _matchesAdvisory(t.category.major) ||
      _matchesAdvisory(t.description);

  /// 税務顧問料の固定費（サブスク）か（顧問料を固定費登録している場合に対応）。
  bool _isAdvisorySub(core.Subscription s) =>
      _matchesAdvisory(s.name) ||
      _matchesAdvisory(s.category) ||
      _matchesAdvisory(s.plMajor);

  /// 税務顧問料を隠す表示が有効か（事業モードのみ・設定 ON のとき）。
  bool get _advisoryHidden =>
      _isBusiness && UiPreferences.instance.hideAdvisory;

  /// 表示に使うサブスク一覧（家賃を隠す時は家賃サブスクを除外）。
  /// 締めスナップショット等「実額」が要る箇所は _subs（全件）を明示的に使う。
  List<core.Subscription> get _visibleSubs {
    var list = _subs;
    if (_rentHidden) list = list.where((s) => !_isRentSub(s)).toList();
    if (_advisoryHidden) {
      list = list.where((s) => !_isAdvisorySub(s)).toList();
    }
    return list;
  }

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
    MonthCursor.instance.addListener(_onMonthCursor);
    UiPreferences.instance.addListener(_onUiPrefs);
  }

  /// UI 表示設定（家賃を隠す等）が変わったら再描画する。
  void _onUiPrefs() {
    if (mounted) setState(() {});
  }

  /// 他タブで月が変わったら追従（6月を見ていれば別タブでも6月維持）。
  void _onMonthCursor() {
    final m = MonthCursor.instance.month;
    if (!mounted) return;
    if (m.year != _month.year || m.month != _month.month) {
      setState(() => _month = DateTime(m.year, m.month));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subTab?.dispose();
    MonthCursor.instance.removeListener(_onMonthCursor);
    UiPreferences.instance.removeListener(_onUiPrefs);
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final subs = await SubscriptionRepository.instance.load();
    final payments = await _settings.loadPayments();
    final cats = await _settings.loadCategories();
    final closing = await MonthClosingRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _subs = subs.subscriptions;
      _payments = payments;
      _catIcons = {for (final m in cats.majors) m.name: m.iconKey};
      _closing = closing;
      _loading = false;
    });
  }


  /// 名前の正規化（実取引との照合用）。
  String _normName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[（）()【】\[\]・:：\s　]'), '');

  /// その月に「実取引が存在する」固定費サブスクのID集合。
  /// 実取引があるサブスクは、予定行を出さず・二重計上もしない（実取引を採用）。
  /// 照合＝同月の支出取引を、①名前一致 ②金額一致 の順で1対1に割り当てる。
  Set<String> _matchedSubIds(DateTime m,
      [List<core.Subscription>? subsOverride]) {
    final subsList = subsOverride ?? _visibleSubs;
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final txns = _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.date.year == m.year &&
            t.date.month == m.month)
        .toList();
    final claimed = <String>{};
    final matched = <String>{};
    for (final sub in subsList) {
      final exp = sub.isVariable ? sub.monthlyActuals[ym] : sub.amount;
      final nname = _normName(sub.name);
      core.Transaction? hit;
      if (nname.isNotEmpty) {
        for (final t in txns) {
          if (claimed.contains(t.id)) continue;
          final nd = _normName(t.description);
          if (nd.isNotEmpty && (nd.contains(nname) || nname.contains(nd))) {
            hit = t;
            break;
          }
        }
      }
      if (hit == null && exp != null && exp > 0) {
        for (final t in txns) {
          if (claimed.contains(t.id)) continue;
          if (t.amount == exp) {
            hit = t;
            break;
          }
        }
      }
      if (hit != null) {
        claimed.add(hit.id);
        matched.add(sub.id);
      }
    }
    return matched;
  }

  int _subsOf(DateTime m, [List<core.Subscription>? subsOverride]) {
    final subsList = subsOverride ?? _visibleSubs;
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final matched = _matchedSubIds(m, subsList);
    return subsList.fold<int>(
        0,
        (s, sub) => matched.contains(sub.id)
            ? s
            : s + sub.plAmountForMonth(ym, curYm));
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

  /// [onTap] を渡すと行全体を押せる（高額明細＝押すとその明細の編集を開く）。
  Widget _summaryLine(String label, int amount, {VoidCallback? onTap}) {
    final row = Padding(
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
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }

  /// この月が対象の変動費か（月払い・範囲内・当月まで）。未入力でも「入力待ち」で出す判定用。
  bool _variableActiveInMonth(core.Subscription sub, String ym, String curYm) {
    if (ym.compareTo(curYm) > 0) return false;
    if (sub.startYearMonth != null &&
        ym.compareTo(sub.startYearMonth!) < 0) {
      return false;
    }
    if (sub.endYearMonth != null && ym.compareTo(sub.endYearMonth!) > 0) {
      return false;
    }
    return sub.cycle == core.SubscriptionCycle.monthly;
  }

  List<
      ({
        String id,
        String name,
        int amount,
        String? iconUrl,
        int? billingDay,
        bool pending
      })> _fixedLinesForMonth(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final lines = <({
      String id,
      String name,
      int amount,
      String? iconUrl,
      int? billingDay,
      bool pending
    })>[];
    final matched = _matchedSubIds(m);
    for (final sub in _visibleSubs) {
      // 実取引がある固定費は予定行を出さない（実取引を採用）。
      if (matched.contains(sub.id)) continue;
      final amt = sub.plAmountForMonth(ym, curYm);
      // 変動費で対象月だが未入力＝「入力待ち」として出す。
      final pending = sub.isVariable &&
          !sub.monthlyActuals.containsKey(ym) &&
          _variableActiveInMonth(sub, ym, curYm);
      if (amt <= 0 && !pending) continue;
      lines.add((
        id: sub.id,
        name: sub.name.trim().isEmpty ? '固定費' : sub.name,
        amount: amt,
        iconUrl: sub.iconUrl,
        billingDay: sub.billingDay,
        pending: pending,
      ));
    }
    // 入力待ちは末尾、それ以外は金額の高い順。
    lines.sort((a, b) {
      if (a.pending != b.pending) return a.pending ? 1 : -1;
      return b.amount.compareTo(a.amount);
    });
    return lines;
  }

  /// 変動費のその月の金額を手入力して保存する（入力待ち行から呼ぶ）。
  Future<void> _inputVariableAmount(String subId) async {
    final ctrl = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('今月の金額を入力'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
              prefixText: '¥ ', labelText: '金額（円）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(
                  ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
              if (n != null) Navigator.pop(dctx, n);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (v == null) return;
    final cfg = await SubscriptionRepository.instance.load();
    final newSubs = cfg.subscriptions.map((s) {
      if (s.id != subId) return s;
      final map = Map<String, int>.from(s.monthlyActuals);
      map[_ymKey] = v;
      return s.copyWith(monthlyActuals: map);
    }).toList();
    await SubscriptionRepository.instance
        .save(core.SubscriptionConfig(subscriptions: newSubs));
    if (mounted) await _load();
  }

  /// 指定月に計上される固定費を、明細テーブルに混ぜる用の行に変換する。
  /// 日付＝請求日（billingDay／年払いは nextBillingDate）。無ければ月初。
  List<FixedCostRow> _fixedTableRows(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
    final rows = <FixedCostRow>[];
    final matched = _matchedSubIds(m);
    for (final sub in _visibleSubs) {
      // 実取引がある固定費は予定行を出さない（実取引を採用）。
      if (matched.contains(sub.id)) continue;
      final amt = sub.plAmountForMonth(ym, curYm);
      // 変動費で対象月だが未入力＝「入力待ち」として明細にも出す。
      final pending = sub.isVariable &&
          !sub.monthlyActuals.containsKey(ym) &&
          _variableActiveInMonth(sub, ym, curYm);
      if (amt <= 0 && !pending) continue;
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
        reviewed: sub.reviewedMonths[ym] ?? false,
        pending: pending,
      ));
    }
    return rows;
  }

  /// 手動並び替えの保存。取引は取引の sortOrder、固定費はサブスクの sortOrder。
  Future<void> _saveReorder(List<ReorderedItem> dayInNewOrder) async {
    final subOrders = <String, double>{};
    final txnUpdates = <core.Transaction>[];
    for (int i = 0; i < dayInNewOrder.length; i++) {
      final item = dayInNewOrder[i];
      if (item.isFixed) {
        subOrders[item.subscriptionId!] = i.toDouble();
      } else {
        txnUpdates.add(item.txn!.copyWith(sortOrder: i.toDouble()));
      }
    }
    // 取引は updateMany で一括更新＝通知は1回だけ（並び替え中のチラつき防止）。
    // 画面は即反映され、サーバ書き込みは裏で完了。失敗時のみ再読込。
    if (txnUpdates.isNotEmpty) {
      unawaited(_txRepo.updateMany(txnUpdates).catchError((_) {
        if (mounted) _load();
      }));
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
      if (mounted) await _load();
    }
  }

  /// 固定費の確認済み（表示中の月）をトグルして保存する。
  Future<void> _toggleFixedReviewed(String subId, bool value) async {
    final cfg = await SubscriptionRepository.instance.load();
    final newSubs = cfg.subscriptions.map((s) {
      if (s.id != subId) return s;
      final m = Map<String, bool>.from(s.reviewedMonths);
      if (value) {
        m[_ymKey] = true;
      } else {
        m.remove(_ymKey);
      }
      return s.copyWith(reviewedMonths: m);
    }).toList();
    await SubscriptionRepository.instance
        .save(core.SubscriptionConfig(subscriptions: newSubs));
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
      final keihiAll = all.where((t) => !_isGaichu(t)).toList();
      // 税務顧問料を隠す設定なら諸経費の「表示」から除く。
      // 締めスナップショットには実額（顧問料込み）を記録する。
      final keihi = _advisoryHidden
          ? keihiAll.where((t) => !_isAdvisoryTx(t)).toList()
          : keihiAll;
      final subTotal = _subsOf(_month);           // 表示（隠す設定を反映）
      final subTotalFull = _subsOf(_month, _subs); // 締め用（実額・全件）
      final keihiTotal =
          keihi.fold<int>(0, (s, t) => s + t.effectiveAmount) + subTotal;
      final keihiFullTotal =
          keihiAll.fold<int>(0, (s, t) => s + t.effectiveAmount) + subTotalFull;
      final gaichuTotal = gaichu.fold<int>(0, (s, t) => s + t.effectiveAmount);
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
              // 月の切替はトップバーの共有月ナビに集約。ここは締めボタンだけ右に。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V2Spacing.md),
                child: Row(
                  children: [
                    // 事業モード：税務顧問料を除外して見るトグル。
                    _advisoryToggleChip(),
                    const Spacer(),
                    MonthClosingBar(
                        month: _month,
                        snapshotExpense: keihiFullTotal + gaichuTotal,
                        dense: true,
                        walletsToClose: _walletsToClose(),
                        onChanged: _load),
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
                    _grey(_buildBody(
                        rows: keihi,
                        showFixedAndCard: true,
                        title: null,
                        detailLabel: '経費明細',
                        showTopHeader: false)),
                    _grey(_buildBody(
                        rows: gaichu,
                        showFixedAndCard: false,
                        receiptLabel: '請求書',
                        teamSortDefault: true,
                        title: null,
                        detailLabel: '制作原価明細',
                        showTopHeader: false)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 個人モード（従来レイアウト）。家賃を隠す設定なら明細から家賃を除く。
    final personalRows = _rentHidden
        ? _monthExpenses.where((t) => !_isRentTx(t)).toList()
        : _monthExpenses;
    // 締めスナップショットは常に家賃込みの実額を記録する（隠していても正しい額を残す）。
    final snapshotFull = _rentHidden
        ? _monthExpenses.fold<int>(0, (s, t) => s + t.effectiveAmount) +
            _subsOf(_month, _subs)
        : null;
    return _grey(_buildBody(
        rows: personalRows,
        showFixedAndCard: true,
        title: '支出',
        detailLabel: '支出明細',
        snapshotExpenseFull: snapshotFull));
  }

  /// 締め処理済みの月は本文に「薄い暖色（セピア）のトーン」を重ねて「もう確定」を示す。
  /// 青は読みにくかったので、読みやすさ優先で不透明度を上げ、色味も落ち着いた暖色に。
  /// 家賃を除外して見るトグル（個人モードの支出タブ）。
  /// 家賃はハズレ値で他の支出が霞むため、ワンタップで表示/非表示を切替える。
  Widget _rentToggleChip() {
    final hidden = _rentHidden;
    return InkWell(
      onTap: () async {
        await UiPreferences.instance
            .setHideRent(!UiPreferences.instance.hideRent);
        if (mounted) setState(() {});
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hidden
              ? widget.accent.withValues(alpha: 0.12)
              : V2Colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: hidden ? widget.accent : V2Colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                hidden
                    ? Icons.visibility_off_outlined
                    : Icons.home_outlined,
                size: 15,
                color: hidden ? widget.accent : V2Colors.textSecondary),
            const SizedBox(width: 6),
            Text(hidden ? '家賃を除外中' : '家賃を除く',
                style: V2Typography.micro.copyWith(
                    color:
                        hidden ? widget.accent : V2Colors.textSecondary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// 税務顧問料を除外して見るトグル（事業モードの経費タブ）。
  /// 顧問料は毎月ほぼ固定の大きめ費用で、他の経費の増減が霞むため隠せるようにする。
  Widget _advisoryToggleChip() {
    final hidden = _advisoryHidden;
    return InkWell(
      onTap: () async {
        await UiPreferences.instance
            .setHideAdvisory(!UiPreferences.instance.hideAdvisory);
        if (mounted) setState(() {});
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hidden
              ? widget.accent.withValues(alpha: 0.12)
              : V2Colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: hidden ? widget.accent : V2Colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                hidden
                    ? Icons.visibility_off_outlined
                    : Icons.account_balance_outlined,
                size: 15,
                color: hidden ? widget.accent : V2Colors.textSecondary),
            const SizedBox(width: 6),
            Text(hidden ? '税務顧問料を除外中' : '税務顧問料を除く',
                style: V2Typography.micro.copyWith(
                    color:
                        hidden ? widget.accent : V2Colors.textSecondary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _grey(Widget child) => _isMonthClosed
      ? ColoredBox(
          color: const Color(0xFFF6E7C9),
          child: Opacity(opacity: 0.72, child: child),
        )
      : child;

  /// 支出本文（タブ共用）。title が null ならタイトル見出しは出さない（タブ側で表示済）。
  /// showFixedAndCard=false（制作原価タブ）では固定費・クレカ照合を出さない。
  Widget _buildBody({
    required List<core.Transaction> rows,
    required bool showFixedAndCard,
    required String? title,
    required String detailLabel,
    // 証憑列/ボタンの呼び名（制作原価タブは「請求書」）。
    String receiptLabel = '領収書',
    // 制作原価タブは既定を「小カテゴリ昇順→場所降順」の複合順にする。
    bool teamSortDefault = false,
    // 事業モードは月セレクタ＋締めをタブより上に出すため、本文側では隠す。
    bool showTopHeader = true,
    // 締めスナップショットに記録する実額（家賃を隠していても実額を残すため）。
    // null なら表示中の合計（total）をそのまま使う。
    int? snapshotExpenseFull,
  }) {
    final accent = widget.accent;
    final summaryLabel = detailLabel.replaceAll('明細', '');
    final txTotal = rows.fold<int>(0, (s, t) => s + t.effectiveAmount);
    final subTotal = showFixedAndCard ? _subsOf(_month) : 0;
    final total = txTotal + subTotal;
    final fixedLines = showFixedAndCard
        ? _fixedLinesForMonth(_month)
        : <({
            String id,
            String name,
            int amount,
            String? iconUrl,
            int? billingDay,
            bool pending
          })>[];

    // カテゴリ内訳（大カテゴリ別・固定費込み）＋ドリルダウン用の取引一覧。
    final byMajor = <String, int>{};
    final txnsByMajor = <String, List<core.Transaction>>{};
    for (final t in rows) {
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.effectiveAmount;
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
      byPayment[pm] = (byPayment[pm] ?? 0) + t.effectiveAmount;
    }
    if (showFixedAndCard) {
      final now = DateTime.now();
      final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final ym = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      // ⚠ 実明細としてもう記録済みの固定費は足さない（rows に入っているので二重計上になる）。
      //   種類別の合計(_subsOf)は同じ _matchedSubIds で除外しているのに、ここだけ
      //   全件足していたため「支払方法別のオリコだけウォレットより多い」ズレが出ていた。
      final matched = _matchedSubIds(_month);
      for (final s in _visibleSubs) {
        if (matched.contains(s.id)) continue;
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

    // 高額明細（1万円以上）。「今月なににお金が飛んだか」をサマリーの展開だけで
    // つかめるようにする（カテゴリ内訳を1つずつ開かなくて済む）。金額降順。
    // 実質負担（立替を引いた額）で判定＝立替で戻る分は高額扱いしない。
    final bigRows = rows.where((t) => t.effectiveAmount >= _kBigAmount).toList()
      ..sort((a, b) => b.effectiveAmount.compareTo(a.effectiveAmount));

    // 支出本文のセクション群。
    // ※ 以前ここを ListView 化して画面外を間引く最適化を入れたが、シェルが本文へ渡す
    //   制約の都合でスマホの明細が真っ白（レイアウト例外）になったため、確実に表示できる
    //   SingleChildScrollView に戻した。スクロール軽量化は別途安全な方法で行う。
    final children = <Widget>[
              // タブ上部：タイトル（個人モードのみ）＋ 中央に月セレクタ（資産タブと
              // 同じシンプルな見た目）＋ 右上に締め処理チップ。
              // 事業モードでは月セレクタをタブより上に出すため、ここは省略する。
              // 月の切替はトップバーの共有月ナビに集約。ここは締めボタンだけ右に。
              if (showTopHeader) ...[
                Row(
                  children: [
                    // 個人モードのみ：家賃を除外して見るトグル。
                    if (!_isBusiness) _rentToggleChip(),
                    const Spacer(),
                    MonthClosingBar(
                        month: _month,
                        snapshotExpense: snapshotExpenseFull ?? total,
                        dense: true,
                        walletsToClose: _walletsToClose(),
                        onChanged: _load),
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
                            // ── 高額明細（1万円以上）──
                            if (bigRows.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              const Divider(height: 1, color: V2Colors.divider),
                              const SizedBox(height: 14),
                              _breakdownHeader(Icons.priority_high,
                                  '高額明細（1万円以上・${bigRows.length}件）'),
                              const SizedBox(height: 6),
                              for (final t in bigRows)
                                _summaryLine(
                                  t.description.trim().isEmpty
                                      ? formatMonthDay(t.date)
                                      : '${formatMonthDay(t.date)}  ${t.description.trim()}',
                                  t.effectiveAmount,
                                  // 押したらその明細を開く（金額の確認→そのまま直せる）。
                                  onTap: () => _edit(t),
                                ),
                            ],
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
                                  for (final f
                                      in fixedLines.where((x) => !x.pending))
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
                  // 全カード/口座を渡し、表示可否はウィジェット側で判定する
                  // （アクティブ=常に表示／休眠=当月に動きがある時だけ表示）。
                  cards: _payments.creditCards,
                  bankAccounts: _payments.bankAccounts,
                  transactions: _transactions,
                  subscriptions: _subs,
                  ym: _ymKey,
                  onOpenReconcile: _openCardReconcile,
                  closedWalletNames: _closedWalletNames,
                ),
                const SizedBox(height: V2Spacing.xl),
              ],
              // 毎月の固定費（引落予定）— 見出しはカード外。合計は枠内フッターに。
              if (fixedLines.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: V2Spacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.repeat,
                          size: 18, color: V2Colors.textSecondary),
                      SizedBox(width: V2Spacing.sm),
                      Text('毎月の固定費（引落予定）',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: V2Colors.textPrimary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: V2Spacing.md),
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
                          onTap: fixedLines[i].pending
                              ? () => _inputVariableAmount(fixedLines[i].id)
                              : () => _editSubscription(fixedLines[i].id),
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(fixedLines[i].name,
                                          style: V2Typography.body,
                                          overflow: TextOverflow.ellipsis),
                                      // 3-1: 毎月の支払日を表示。
                                      if (fixedLines[i].billingDay != null)
                                        Text('毎月${fixedLines[i].billingDay}日',
                                            style: V2Typography.micro.copyWith(
                                                color: V2Colors.textMuted)),
                                    ],
                                  ),
                                ),
                                // 3-3: 入力待ち（変動費）はバッジ、そうでなければ金額。
                                if (fixedLines[i].pending)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('入力待ち',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFB45309))),
                                  )
                                else
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
                      // 3-2: 合計をカード枠内のフッターに置く（枠外のはみ出し解消）。
                      const Divider(height: 1, color: V2Colors.divider),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Text('合計',
                                style: V2Typography.bodyStrong.copyWith(
                                    color: V2Colors.textPrimary)),
                            const Spacer(),
                            Text(formatYen(subTotal),
                                style: V2Typography.bodyStrong.copyWith(
                                    color: V2Colors.textPrimary,
                                    fontFeatures: V2Typography.tabularNums)),
                          ],
                        ),
                      ),
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
                receiptLabel: receiptLabel,
                defaultTeamSort: teamSortDefault,
                fixedRows: showFixedAndCard
                    ? _fixedTableRows(_month)
                    : const <FixedCostRow>[],
                // 入力待ち（変動費）はタップで金額入力、それ以外は編集画面へ。
                onEditFixed: (f) => f.pending
                    ? _inputVariableAmount(f.id)
                    : _editSubscription(f.id),
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
                // 固定費の確認済み（月別）。
                onToggleReviewedFixed: (f, v) =>
                    _toggleFixedReviewed(f.id, v),
                // 同じ日付内の手動並び替え：新しい順で sortOrder を 0,1,2… と振る。
                // 取引は取引に、固定費はサブスクに保存する。
                onReorderDay: _saveReorder,
              ),
            ];
    // 幅広（PC/Windows＝サイドバー版シェル、画面幅≥700）だけ ListView にして、
    // 画面外の行（Webの<img>プラットフォームビュー）を描画対象から外し、スクロールを
    // 軽くする。狭い幅（スマホ＝下タブ版シェル）は本文へ渡る制約の都合で ListView が
    // 真っ白になるため、従来どおり SingleChildScrollView（＝現行の確実な方式）にする。
    // 判定はシェル選択と同じ MediaQuery 幅<700 を使うので、スマホ側は現状と完全に同一。
    final wide = MediaQuery.sizeOf(context).width >= 700;
    if (wide) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.symmetric(
                vertical: V2Spacing.lg, horizontal: V2Spacing.md),
            children: children,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.lg, horizontal: V2Spacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
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

