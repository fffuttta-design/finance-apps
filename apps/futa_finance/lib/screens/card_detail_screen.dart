import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/month_closing_repository.dart';
import '../data/month_cursor.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/subscription_repository.dart';
import '../data/transaction_repository.dart';
import '../v2/theme/mode_accent.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../v2/widgets/credit_card_reconcile.dart';
import '../v2/widgets/expense_detail_table.dart';
import '../widgets/brand_logo.dart';
import 'expense_input_screen.dart';
import 'transaction_detail_screen.dart';
import 'subscription_list_screen.dart';

/// クレジットカード詳細（利用明細）画面。
/// 銀行通帳の AccountDetailScreen に相当するクレカ版。
///
/// 機能:
/// - 月セレクター（取引のある月 + 当月）
/// - サマリー: 当月利用合計（大）/ 件数 / 引落予定日
/// - 利用履歴: その月のカード利用一覧（日付→明細→金額）
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.card});

  final core.RegisteredCreditCard card;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

const double _kContentMaxWidth = 1000;

class _CardDetailScreenState extends State<CardDetailScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];
  List<core.Subscription> _subs = [];
  DateTime? _selectedMonth;

  /// 日付範囲での絞り込み（設定中は月選択より優先）。null なら月モード。
  DateTimeRange? _range;

  /// 初回ロードで「利用のある最新月」を初期選択にしたか（以後はユーザー操作を尊重）。
  bool _monthPicked = false;
  // 月締め処理中フラグ（ボタン多重押し防止）。
  bool _busyCardClose = false;
  // 明細の並び替え「編集」モード（銀行の通帳と同じ挙動）。
  // ・OFF（既定）：保存したカスタム順で固定表示（未設定は日付順フォールバック・ハンドルなし）。
  // ・ON：ハンドルでドラッグ並び替え＋「日付順に並べ直す」。
  bool _cardCustom = false;
  // カード×月ごとの「締め済み」状態（明示的にボタンを押したときだけ立つ）。
  core.MonthClosingConfig _closing = core.MonthClosingConfig.empty();
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// 編集後のカードスナップショット（paymentDay変更時に画面に即反映するため）。
  /// null なら widget.card を使う。
  core.RegisteredCreditCard? _updatedCard;
  core.RegisteredCreditCard get _card => _updatedCard ?? widget.card;

  @override
  void initState() {
    super.initState();
    // タブで選択中の月で開く（6月を見ていたら詳細も6月から）。
    _selectedMonth = MonthCursor.instance.month;
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _all = list);
    });
    // 他画面で payments が更新された時、このカードの最新値を反映する
    // （引落日を保存 → 戻る → 再表示で消える問題を防ぐ）
    PaymentsChangeNotifier.instance.addListener(_refreshCardFromPayments);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    PaymentsChangeNotifier.instance.removeListener(_refreshCardFromPayments);
    super.dispose();
  }

  Future<void> _refreshCardFromPayments() async {
    try {
      final cfg = await SettingsRepository.instance.loadPayments();
      core.RegisteredCreditCard? found;
      for (final c in cfg.creditCards) {
        if (c.id == widget.card.id) {
          found = c;
          break;
        }
      }
      if (found == null || !mounted) return;
      setState(() => _updatedCard = found);
    } catch (_) {}
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    final subs = await SubscriptionRepository.instance.load();
    final closing = await MonthClosingRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _all = list;
      _subs = subs.subscriptions;
      _closing = closing;
      // 初回だけ初期月を確定。
      // ・過去月を選んで開いたとき（＝共有カーソルが当月以外）は、その月を尊重。
      // ・当月（＝特に月指定していない）のときだけ「利用のある最新月」を既定にする。
      if (!_monthPicked) {
        _monthPicked = true;
        final sel = MonthCursor.instance.month;
        final now = DateTime.now();
        final isCurrent = sel.year == now.year && sel.month == now.month;
        _selectedMonth = isCurrent ? _defaultMonth() : sel;
      }
    });
  }

  /// 初期表示する月。当月に利用があれば当月、無ければ利用のある最新月。
  /// 利用が全く無ければ当月のまま。
  DateTime _defaultMonth() {
    final now = DateTime.now();
    final cur = DateTime(now.year, now.month);
    final name = _card.name;
    final months = <DateTime>{};
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.paymentMethod != name) continue;
      months.add(DateTime(t.date.year, t.date.month));
    }
    if (months.isEmpty || months.contains(cur)) return cur;
    return months.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// このカードに紐づく固定費（支払方法が一致）を、明細テーブルに混ぜる行に変換。
  /// [month] が null（全期間）のときは月が定まらないので出さない。
  List<FixedCostRow> _cardFixedRows(DateTime? month) {
    if (month == null) return const [];
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    // 過去の月は「実際に発行された明細（実取引）」だけを見る。固定費の予定行は
    // 当月以降のみ出す。開始月が未設定の固定費が過去に遡って計上され、利用合計を
    // 膨らませていた問題への対処（固定費はその月の決済日になって発行される想定）。
    if (ym.compareTo(curYm) < 0) return const [];
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final name = _card.name;
    final rows = <FixedCostRow>[];
    for (final sub in _subs) {
      if ((sub.paymentMethod ?? '').trim() != name) continue;
      // 既に「実明細化」された固定費は monthTxns（実取引）側に出るので、
      // ここでは出さない（利用合計の二重計上を防ぎ、ウォレット一覧と一致させる）。
      if (_all.any((t) => t.id == 'fixedcost_${sub.id}_$ym')) continue;
      final amt = sub.plAmountForMonth(ym, curYm);
      final pending = sub.isVariable &&
          !sub.monthlyActuals.containsKey(ym) &&
          sub.cycle == core.SubscriptionCycle.monthly &&
          (sub.startYearMonth == null ||
              ym.compareTo(sub.startYearMonth!) >= 0) &&
          (sub.endYearMonth == null ||
              ym.compareTo(sub.endYearMonth!) <= 0) &&
          ym.compareTo(curYm) <= 0;
      if (amt <= 0 && !pending) continue;
      DateTime date;
      if (sub.cycle == core.SubscriptionCycle.annually &&
          sub.nextBillingDate != null) {
        date = sub.nextBillingDate!;
      } else {
        final day = (sub.billingDay ?? 1).clamp(1, daysInMonth);
        date = DateTime(month.year, month.month, day);
      }
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

  /// 変動費（入力待ち）の今月の金額を手入力して保存する。
  Future<void> _inputCardVariableAmount(String subId) async {
    final m = _selectedMonth;
    if (m == null) return;
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final ctrl = NoComposingUnderlineController();
    final v = await showDialog<int>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('今月の金額を入力'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [
            HalfWidthDigitsFormatter(),
            ThousandsSeparatorInputFormatter(),
          ],
          decoration: const InputDecoration(
              prefixText: '¥ ', labelText: '金額（円）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final n = parseAmount(ctrl.text);
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
      map[ym] = v;
      return s.copyWith(monthlyActuals: map);
    }).toList();
    await SubscriptionRepository.instance
        .save(core.SubscriptionConfig(subscriptions: newSubs));
    if (mounted) await _load();
  }

  /// 固定費の確認済み（選択中の月）をトグルして保存する。
  ///
  /// チェックは即座に反映（楽観的更新）。以前は保存→_load() の往復を待って
  /// いたため、反映が遅れて「チェックが入らない」ように見えることがあった。
  Future<void> _toggleFixedReviewed(String subId, bool value) async {
    final m = _selectedMonth;
    if (m == null) return;
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    core.Subscription apply(core.Subscription s) {
      if (s.id != subId) return s;
      final map = Map<String, bool>.from(s.reviewedMonths);
      if (value) {
        map[ym] = true;
      } else {
        map.remove(ym);
      }
      return s.copyWith(reviewedMonths: map);
    }

    // ① ローカル _subs を即更新（チェックがすぐ入る／外れる）。
    setState(() => _subs = _subs.map(apply).toList());
    // ② 永続化は裏で。失敗時のみ再読込して元に戻す。
    try {
      final cfg = await SubscriptionRepository.instance.load();
      final newSubs = cfg.subscriptions.map(apply).toList();
      await SubscriptionRepository.instance
          .save(core.SubscriptionConfig(subscriptions: newSubs));
    } catch (_) {
      if (mounted) await _load();
    }
  }

  /// カード×月の締めキー（月グローバル・口座の締めと衝突しない接頭辞付き）。
  String _cardMonthKey(DateTime m) =>
      'card:${_card.name}:${m.year}-${m.month.toString().padLeft(2, '0')}';

  bool get _isCardMonthClosed {
    final m = _selectedMonth;
    if (m == null || _range != null) return false;
    final key = _cardMonthKey(m);
    return _closing.closings.any((c) => c.yearMonth == key && c.isClosed);
  }

  Future<void> _setCardClosedFlag(DateTime m, bool closed) async {
    final key = _cardMonthKey(m);
    final existing = _closing.closings.firstWhere(
      (c) => c.yearMonth == key,
      orElse: () => core.MonthClosing(yearMonth: key),
    );
    final updated = closed
        ? existing.copyWith(closedAt: DateTime.now())
        : existing.copyWith(clearClosedAt: true);
    await MonthClosingRepository.instance.save(_closing.upsert(updated));
  }

  /// この月を締める＝この月の利用（取引＋固定費）を全部「確認済み」にして締めフラグを立てる。
  Future<void> _closeCardMonth(
      List<core.Transaction> monthTxns, List<FixedCostRow> fixed) async {
    final m = _selectedMonth;
    if (m == null) return;
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final total = monthTxns.length + fixed.length;
    if (total == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('${m.month}月を締めますか？'),
        content: Text(
            '「${_card.name}」の${m.year}年${m.month}月の利用 $total件を、'
            'すべて「確認済み（金額に間違いなし）」にします。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('締める')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyCardClose = true);
    await _setCardMonthReviewed(monthTxns, fixed, ym, true);
    await _setCardClosedFlag(m, true);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _busyCardClose = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${m.month}月を締めました')));
  }

  /// 締めを解除＝締めフラグを外す（確認チェックはそのまま残す）。
  Future<void> _reopenCardMonth(
      List<core.Transaction> monthTxns, List<FixedCostRow> fixed) async {
    final m = _selectedMonth;
    if (m == null) return;
    setState(() => _busyCardClose = true);
    await _setCardClosedFlag(m, false);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _busyCardClose = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${m.month}月の締めを解除しました')));
  }

  /// 取引の reviewed と、固定費の reviewedMonths[ym] をまとめて value に。
  Future<void> _setCardMonthReviewed(List<core.Transaction> monthTxns,
      List<FixedCostRow> fixed, String ym, bool value) async {
    final txUpdates = monthTxns
        .where((t) => t.reviewed != value)
        .map((t) => t.copyWith(reviewed: value))
        .toList();
    if (txUpdates.isNotEmpty) {
      await TransactionRepository.instance.updateMany(txUpdates);
    }
    if (fixed.isNotEmpty) {
      final subIds = fixed.map((f) => f.id).toSet();
      final cfg = await SubscriptionRepository.instance.load();
      final newSubs = cfg.subscriptions.map((s) {
        if (!subIds.contains(s.id)) return s;
        final map = Map<String, bool>.from(s.reviewedMonths);
        if (value) {
          map[ym] = true;
        } else {
          map.remove(ym);
        }
        return s.copyWith(reviewedMonths: map);
      }).toList();
      await SubscriptionRepository.instance
          .save(core.SubscriptionConfig(subscriptions: newSubs));
    }
  }

  /// カードの月締めバー（月モードのみ）。全部確認済みなら締め済み表示。
  Widget _cardCloseMonthBar(
      List<core.Transaction> monthTxns, List<FixedCostRow> fixed) {
    if (_selectedMonth == null || _range != null) {
      return const SizedBox.shrink();
    }
    final total = monthTxns.length + fixed.length;
    if (total == 0) return const SizedBox.shrink();
    final done = monthTxns.where((t) => t.reviewed).length +
        fixed.where((f) => f.reviewed).length;
    // 締め済みは「ユーザーが締めボタンを押したとき」だけ（チェック全部でも自動では締めない）。
    final closed = _isCardMonthClosed;
    return Container(
      color: closed ? const Color(0xFFE7F6EF) : const Color(0xFFF7F8FA),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(closed ? Icons.verified : Icons.fact_check_outlined,
              size: 18,
              color: closed
                  ? const Color(0xFF059669)
                  : const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              closed
                  ? '${_selectedMonth!.month}月は締め済み（全$total件 確認済み）'
                  : '確認済み $done/$total件',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: closed
                      ? const Color(0xFF059669)
                      : const Color(0xFF6B7280)),
            ),
          ),
          // 並び順トグル（締めボタンの隣・固定位置。スクロールで消えない）。
          // 銀行の通帳と同じ：ふだんは保存したカスタム順で固定表示、ボタンONで
          // 並び替え編集（ハンドル表示）。ONのまま画面から離れても並びは保存される。
          Tooltip(
            message: _cardCustom
                ? '並び替え中（ハンドルをドラッグ）。もう一度押すとこの並びで固定'
                : 'カスタム順で並び替える（この並びで固定される）',
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _cardCustom = !_cardCustom),
              icon: Icon(_cardCustom ? Icons.check : Icons.swap_vert,
                  size: 16,
                  color: _cardCustom
                      ? const Color(0xFF059669)
                      : const Color(0xFF6B7280)),
              label: Text(_cardCustom ? '並び替え中' : 'カスタム順',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _cardCustom
                          ? const Color(0xFF059669)
                          : const Color(0xFF6B7280))),
              style: OutlinedButton.styleFrom(
                backgroundColor:
                    _cardCustom ? const Color(0xFFECFDF5) : null,
                side: BorderSide(
                    color: _cardCustom
                        ? const Color(0xFF059669)
                        : const Color(0xFFD1D5DB)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (closed)
            TextButton(
              onPressed: _busyCardClose
                  ? null
                  : () => _reopenCardMonth(monthTxns, fixed),
              child: const Text('締め解除'),
            )
          else
            FilledButton.icon(
              onPressed: _busyCardClose
                  ? null
                  : () => _closeCardMonth(monthTxns, fixed),
              icon: _busyCardClose
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle, size: 16),
              label: Text('${_selectedMonth!.month}月を締める'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  visualDensity: VisualDensity.compact),
            ),
        ],
      ),
    );
  }

  /// 手動並び替えの保存。取引は取引の sortOrder、固定費はサブスクの sortOrder。
  ///
  /// 通帳（銀行）と同じ「ドロップ位置を即ローカル反映 → 書き込みは裏で」方式。
  /// ⚠ 以前は取引を unawaited 更新しつつ固定費側で `await _load()` していたため、
  ///   取引の書き込みが未反映のまま再読込が走り、取引=旧順・固定費=新順の
  ///   チグハグな状態で並び替わり、さらに stream 通知でもう一度並び替わって
  ///   「一気に動かず、上から辿って徐々にその位置に来る」挙動になっていた。
  ///   ここでは _all / _subs を1回の setState で新順に確定させ、再読込レースを断つ。
  Future<void> _saveReorder(List<ReorderedItem> dayInNewOrder) async {
    final subOrders = <String, double>{};
    final txnOrders = <String, double>{};
    for (int i = 0; i < dayInNewOrder.length; i++) {
      final item = dayInNewOrder[i];
      if (item.isFixed) {
        subOrders[item.subscriptionId!] = i.toDouble();
      } else {
        txnOrders[item.txn!.id] = i.toDouble();
      }
    }
    // ① ドロップ位置をその場で確定（再読込を待たない＝チラつき/戻りを防ぐ）。
    setState(() {
      if (txnOrders.isNotEmpty) {
        _all = [
          for (final t in _all)
            txnOrders.containsKey(t.id)
                ? t.copyWith(sortOrder: txnOrders[t.id])
                : t,
        ];
      }
      if (subOrders.isNotEmpty) {
        _subs = [
          for (final s in _subs)
            subOrders.containsKey(s.id)
                ? s.copyWith(sortOrder: subOrders[s.id])
                : s,
        ];
      }
    });
    // ② 永続化は裏で（失敗時のみ再読込）。
    if (txnOrders.isNotEmpty) {
      final txnUpdates = [
        for (final t in _all) if (txnOrders.containsKey(t.id)) t,
      ];
      unawaited(TransactionRepository.instance
          .updateMany(txnUpdates)
          .catchError((_) {
        if (mounted) _load();
      }));
    }
    if (subOrders.isNotEmpty) {
      unawaited(SubscriptionRepository.instance
          .save(core.SubscriptionConfig(subscriptions: _subs))
          .catchError((_) {
        if (mounted) _load();
      }));
    }
  }

  /// 固定費行タップ → サブスク編集を開いて再読込。
  Future<void> _editCardFixed(String id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => SubscriptionListScreen(initialEditId: id)),
    );
    if (mounted) await _load();
  }

  /// このカードに紐づく取引（paymentMethod が一致）。
  List<core.Transaction> _cardTransactions() {
    final name = _card.name;
    return _all.where((t) {
      return t.type == core.TransactionType.expense &&
          t.paymentMethod == name;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 月選択肢: 当月 + 取引月（降順）+ 全期間。
  List<DateTime?> _availableMonths() {
    final name = _card.name;
    final set = <DateTime>{};
    final now = DateTime.now();
    set.add(DateTime(now.year, now.month));
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.paymentMethod != name) continue;
      set.add(DateTime(t.date.year, t.date.month));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return [null, ...list];
  }

  @override
  Widget build(BuildContext context) {
    final allTxns = _cardTransactions();
    final List<core.Transaction> monthTxns;
    if (_range != null) {
      // 日付範囲での絞り込み（◯月◯日〜◯月◯日）。
      final s = DateTime(_range!.start.year, _range!.start.month,
          _range!.start.day);
      final e = DateTime(_range!.end.year, _range!.end.month,
          _range!.end.day, 23, 59, 59);
      monthTxns = allTxns
          .where((t) => !t.date.isBefore(s) && !t.date.isAfter(e))
          .toList();
    } else if (_selectedMonth == null) {
      monthTxns = allTxns;
    } else {
      monthTxns = allTxns
          .where((t) =>
              t.date.year == _selectedMonth!.year &&
              t.date.month == _selectedMonth!.month)
          .toList();
    }
    // このカードの固定費（月モードのみ）。利用合計にも含めて、支出タブの
    // ウォレット一覧（取引＋固定費で計算）と数字を一致させる。
    final cardFixed = _range != null
        ? const <FixedCostRow>[]
        : _cardFixedRows(_selectedMonth);
    final monthTotal = monthTxns.fold<int>(0, (s, t) => s + t.amount) +
        cardFixed.fold<int>(0, (s, f) => s + f.amount);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_card.iconUrl != null && _card.iconUrl!.isNotEmpty)
              BrandLogo(
                  iconUrl: _card.iconUrl,
                  fallbackEmoji: '💳',
                  size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_card.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          // 支出を記録ボタン。HOME画面の「記録」ボタンと同じデザイン
          // （モードのアクセント色で塗った角丸ピル＋白い「＋記録」）にそろえる。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Tooltip(
              message: '支出を記録（このカード払い）',
              child: Material(
                color: V2ModeAccent.of(AppModeManager.instance.current),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _addExpenseForCard,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('記録',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined,
                color: Color(0xFF1A237E)),
            tooltip: 'クレカ棚卸し（突合）',
            onPressed: _openReconcile,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final content = Column(
            children: [
              // 共通: サマリー（利用合計/件数/引落予定日）
              _summaryCard(monthTotal),
              // タブバー（コンパクト：アイコン＋テキストを横並びで低く）
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFFDC2626),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: const Color(0xFFDC2626),
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  tabs: const [
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 16),
                          SizedBox(width: 6),
                          Text('明細'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.show_chart, size: 16),
                          SizedBox(width: 6),
                          Text('請求推移'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // ── タブ1: その月の明細 ──
                    Column(
                      children: [
                        _monthSelector(),
                        _cardCloseMonthBar(monthTxns, cardFixed),
                        const Divider(height: 1),
                        // 締め済みの月は本文（明細）を薄く（グレーアウト）。
                        Expanded(
                          // 締め済みは薄い青のトーンを重ねて背景と区別。
                          child: ColoredBox(
                            color: _isCardMonthClosed
                                ? const Color(0xFFF6E7C9)
                                : Colors.transparent,
                            child: Opacity(
                            opacity: _isCardMonthClosed ? 0.72 : 1.0,
                          // PC幅は支出明細と同じ表（検索・並び替え・列幅）。
                          // スマホ幅は従来のカード型リスト。
                          child: constraints.maxWidth >= 900
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 16, 16, 0),
                                  child: ExpenseDetailTable(
                                    // タイトル＋検索ボックスを上部に固定し、
                                    // 明細本体だけをスクロールさせる。
                                    stickyHeader: true,
                                    title: '明細',
                                    rows: monthTxns,
                                    onEditTxn: _editCardTxn,
                                    accent: const Color(0xFFDC2626),
                                    // 固定費は月モードのときだけ混ぜる
                                    // （範囲指定はまたぐ月が曖昧なので出さない）。
                                    fixedRows: cardFixed,
                                    onEditFixed: (f) => f.pending
                                        ? _inputCardVariableAmount(f.id)
                                        : _editCardFixed(f.id),
                                    // 領収書チェック（事業モードのみ・税理士提出用）。
                                    // 支出タブの明細表と同じ列をクレカ明細にも出す。
                                    showReceiptCheck:
                                        AppModeManager.instance.current ==
                                            AppMode.business,
                                    onToggleReceipt: (t, v) async {
                                      await TransactionRepository.instance
                                          .update(t.copyWith(receiptSaved: v));
                                      if (mounted) await _load();
                                    },
                                    onToggleReviewed: (t, v) async {
                                      await TransactionRepository.instance
                                          .update(t.copyWith(reviewed: v));
                                      if (mounted) await _load();
                                    },
                                    onToggleReviewedFixed: (f, v) =>
                                        _toggleFixedReviewed(f.id, v),
                                    onReorderDay: _saveReorder,
                                    // 銀行の通帳と同じく常にカスタム順で表示
                                    // （未設定は日付順フォールバック）。ボタンONの
                                    // ときだけハンドルで並び替え可能にする。
                                    customOrder: true,
                                    customEditable: _cardCustom,
                                    emptyHint: 'この期間の利用はありません',
                                  ),
                                )
                              : _historyList(monthTxns),
                          ),
                          ),
                        ),
                      ],
                    ),
                    // ── タブ2: 月別請求推移 ──
                    _monthlyBillingPage(),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth >= 900) {
            // Row+Spacer で中央寄せ（Align+SizedBox(height) より安定）
            return Row(
              children: [
                const Spacer(),
                SizedBox(width: _kContentMaxWidth, child: content),
                const Spacer(),
              ],
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _monthSelector() {
    final months = _availableMonths();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const Text('期間: ',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          if (_range == null)
            // 月モード：月プルダウン。
            DropdownButton<DateTime?>(
              value: _selectedMonth,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF111827)),
              items: months.map((m) {
                final label = m == null ? '全期間' : '${m.year}年${m.month}月';
                return DropdownMenuItem<DateTime?>(
                    value: m, child: Text(label));
              }).toList(),
              onChanged: (v) => setState(() {
                _selectedMonth = v;
                // 詳細で月を変えたら共有カーソルにも反映（戻っても揃う）。
                if (v != null) MonthCursor.instance.month = v;
              }),
            )
          else
            // 範囲モード：選択中の期間をチップ表示（✕で月モードに戻る）。
            InputChip(
              label: Text(
                '${_range!.start.month}/${_range!.start.day}〜'
                '${_range!.end.month}/${_range!.end.day}',
                style: const TextStyle(fontSize: 12),
              ),
              avatar: const Icon(Icons.date_range, size: 16),
              onDeleted: () => setState(() => _range = null),
              visualDensity: VisualDensity.compact,
            ),
          const Spacer(),
          // 期間指定（◯月◯日〜◯月◯日）ボタン。
          TextButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(_range == null ? '期間指定' : '期間を変更',
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1A237E),
                visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  /// 日付範囲（◯月◯日〜◯月◯日）を選ぶ。設定すると月選択より優先される。
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final base = _selectedMonth ?? DateTime(now.year, now.month);
    final initial = _range ??
        DateTimeRange(
          start: DateTime(base.year, base.month, 1),
          end: DateTime(base.year, base.month + 1, 0),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      helpText: '期間を選択',
      saveText: '決定',
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
    }
  }

  Widget _summaryCard(int monthTotal) {
    final paymentDay = _card.paymentDay;
    // 件数は下の明細セクションに出るので、ここは「利用合計」と「引落予定日」を
    // 高さを揃えて横並びにする（IntrinsicHeight）。
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 利用合計（主役）
            Expanded(
              flex: 2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                      width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('利用合計',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(formatYen(monthTotal),
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 引落予定日（タップで編集）
            Expanded(
              flex: 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _editPaymentDay,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('引落予定日',
                                style: TextStyle(
                                    fontSize: 10, color: Color(0xFF9CA3AF))),
                            const SizedBox(width: 2),
                            const Icon(Icons.edit,
                                size: 10, color: Color(0xFF9CA3AF)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                            paymentDay == null ? '未設定' : '毎月 $paymentDay 日',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: paymentDay == null
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF1A237E))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyList(List<core.Transaction> txns) {
    if (txns.isEmpty) {
      return const Center(
        child: Text('この期間の利用はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    return ListView.separated(
      itemCount: txns.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final t = txns[i];
        return _historyRow(t);
      },
    );
  }

  Widget _historyRow(core.Transaction t) {
    final dateLabel =
        '${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}';
    final yearLabel = '${t.date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          // 日付
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        fontFamily: 'monospace')),
                Text(yearLabel,
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 明細（カテゴリ + 説明）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${t.category.major}${t.category.sub.isNotEmpty ? ' · ${t.category.sub}' : ''}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 金額
          Text(
            '-${formatYen(t.amount)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  // ─── 月別請求推移ページ（タブ2の本体） ──
  Widget _monthlyBillingPage() {
    final name = _card.name;
    final billing = <String, int>{};
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.paymentMethod != name) continue;
      final ym =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      billing[ym] = (billing[ym] ?? 0) + t.amount;
    }
    if (billing.isEmpty) {
      return const Center(
        child: Text('まだ利用履歴がありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    final entries = billing.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    // 全体の最大値を取得（バー幅の正規化用）
    final maxAmount =
        entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        return _billingRow(e.key, e.value, maxAmount: maxAmount);
      },
    );
  }

  Widget _billingRow(String yearMonth, int amount,
      {required int maxAmount}) {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final paymentDay = _card.paymentDay;
    String? billingLabel;
    if (paymentDay != null) {
      final billYear = month == 12 ? year + 1 : year;
      final billMonth = month == 12 ? 1 : month + 1;
      billingLabel =
          '$billYear/${billMonth.toString().padLeft(2, '0')}/${paymentDay.toString().padLeft(2, '0')} 引落';
    }
    final ratio = maxAmount > 0 ? (amount / maxAmount).clamp(0.0, 1.0) : 0.0;
    return InkWell(
      onTap: () {
        setState(() => _selectedMonth = DateTime(year, month));
        // 明細タブに切替（その月の利用を見られるよう）
        _tabController.animateTo(0);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$year年$month月',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                ),
                Text(formatYen(amount),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: Color(0xFFDC2626))),
              ],
            ),
            const SizedBox(height: 6),
            // 棒グラフ（金額比較で視覚化）
            Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
            if (billingLabel != null) ...[
              const SizedBox(height: 4),
              Text(billingLabel,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1A237E),
                      fontFamily: 'monospace')),
            ],
          ],
        ),
      ),
    );
  }

  /// 明細テーブル行タップ → 取引を編集して再読込。
  /// 締め済みの月の取引を変更しようとしたとき、確認アラートを出す。
  /// 「変更する」を選んだときだけ true。
  Future<bool> _confirmEditClosed(core.Transaction t) async {
    final key = _cardMonthKey(DateTime(t.date.year, t.date.month));
    final closed = _closing.closings.any((c) => c.yearMonth == key && c.isClosed);
    if (!closed) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('締め済みの月です'),
        content: Text(
            '${t.date.month}月は締め済みです。この取引の金額や内容を変更すると、'
            '締めた月の集計・請求が変わります。それでも変更しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('変更する'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editCardTxn(core.Transaction t) async {
    if (!await _confirmEditClosed(t)) return;
    if (!mounted) return;
    // 支出タブ（rich_expenses の _edit）と同じく、まず明細の詳細画面を出す。
    // ⚠ ここだけ編集フォームを直接開いていたため、同じ「鉛筆」でも
    //   クレカ明細だけ挙動が違っていた。詳細画面から編集/削除へ進む。
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: t)),
    );
    if (mounted) await _load();
  }

  /// このカード払いの支出を新規記録する（明細を1件ずつ確認中の記録漏れ補完用）。
  /// 支払方法はこのカードにプリセット。過去月を表示中ならその月末を初期日付にする。
  Future<void> _addExpenseForCard() async {
    final now = DateTime.now();
    DateTime? preset;
    if (_selectedMonth != null &&
        !(_selectedMonth!.year == now.year &&
            _selectedMonth!.month == now.month)) {
      preset = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 0);
    }
    await showInputSheet<bool>(
      context,
      ExpenseInputScreen(
        initialPaymentMethod: _card.name,
        initialDate: preset,
      ),
    );
    if (mounted) await _load();
  }

  // ─── クレカ棚卸し（突合）──
  /// この詳細画面から突合シートを開く。対象月は期間セレクタの選択月
  /// （全期間のときは当月）。CSV突合・実際額入力・記録漏れ補完はここで行う。
  Future<void> _openReconcile() async {
    final now = DateTime.now();
    final m = _selectedMonth ?? DateTime(now.year, now.month);
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    final c = _card;
    final wallet = ReconcileWallet(
      name: c.name,
      iconUrl: c.iconUrl,
      fallbackIcon: Icons.credit_card,
      isCard: true,
      subtitle: c.paymentDay != null
          ? '引き落とし日：毎月${c.paymentDay}日'
          : 'クレジットカード',
    );
    await showCardReconcileSheet(
      context,
      wallet: wallet,
      initialActual: c.monthlyActualBillings[ym],
      ym: ym,
      onSaveActual: (amount) => _saveActual(ym, amount),
      onEditTxn: (t) async {
        await showInputSheet<bool>(context, ExpenseInputScreen(editing: t));
      },
      onDeleteTxn: (t) async {
        await TransactionRepository.instance.delete(t.id);
      },
      onAddAdjustment: (amount, {description, date}) async {
        final fallback = DateTime(m.year, m.month + 1, 0);
        await showInputSheet<bool>(
          context,
          ExpenseInputScreen(
            initialPaymentMethod: c.name,
            initialAmount: amount > 0 ? amount : null,
            initialDate: date ?? fallback,
            initialDescription: description ?? '差額調整',
          ),
        );
      },
    );
    if (mounted) await _load();
  }

  /// 実際請求額（カード会社通知）を保存／クリアする。
  Future<void> _saveActual(String ym, int? amount) async {
    final cfg = await SettingsRepository.instance.loadPayments();
    final cards = cfg.creditCards.map((c) {
      if (c.name != _card.name) return c;
      final map = Map<String, int>.from(c.monthlyActualBillings);
      if (amount == null) {
        map.remove(ym);
      } else {
        map[ym] = amount;
      }
      return c.copyWith(monthlyActualBillings: map);
    }).toList();
    await SettingsRepository.instance
        .savePayments(cfg.copyWith(creditCards: cards));
    if (!mounted) return;
    setState(() {
      final map = Map<String, int>.from(_card.monthlyActualBillings);
      if (amount == null) {
        map.remove(ym);
      } else {
        map[ym] = amount;
      }
      _updatedCard = _card.copyWith(monthlyActualBillings: map);
    });
    PaymentsChangeNotifier.instance.notifyChanged();
  }

  // ─── 引落予定日 編集 ──
  Future<void> _editPaymentDay() async {
    int? selected = _card.paymentDay;
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('引落予定日を設定'),
          content: SizedBox(
            width: 280,
            child: DropdownButtonFormField<int?>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: '毎月',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— 未設定 —',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                ),
                for (var d = 1; d <= 31; d++)
                  DropdownMenuItem<int?>(
                    value: d,
                    child: Text('$d 日'),
                  ),
              ],
              onChanged: (v) => setLocal(() => selected = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                confirmed = true;
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      }),
    );
    if (!confirmed) return;
    try {
      final cfg = await SettingsRepository.instance.loadPayments();
      final newCards = <core.RegisteredCreditCard>[];
      core.RegisteredCreditCard? updatedSelf;
      for (final c in cfg.creditCards) {
        if (c.id == _card.id) {
          final newC = c.copyWith(
            paymentDay: selected,
            clearPaymentDay: selected == null,
          );
          newCards.add(newC);
          updatedSelf = newC;
        } else {
          newCards.add(c);
        }
      }
      await SettingsRepository.instance.savePayments(
        core.PaymentMethodsConfig(
          bankAccounts: cfg.bankAccounts,
          creditCards: newCards,
        ),
      );
      PaymentsChangeNotifier.instance.notifyChanged();
      if (!mounted) return;
      setState(() {
        if (updatedSelf != null) _updatedCard = updatedSelf;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(selected == null
              ? '引落予定日をクリアしました'
              : '引落予定日を毎月 $selected 日 に設定しました'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

}
