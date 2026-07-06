import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/month_closing_repository.dart';
import '../data/month_cursor.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../v2/widgets/month_nav_bar.dart';
import '../widgets/brand_logo.dart';
import 'expense_input_screen.dart';
import 'income_input_screen.dart';
import 'transfer_input_screen.dart';

/// 口座詳細（通帳）画面。
/// 単一口座に関連する取引を時系列で表示し、各時点の残高を逆算する。
/// 新生銀行などの実通帳と同じ列構成（取引日 / 摘要 / 出金 / 入金 / 残高）。
///
/// 機能:
/// - 月セレクター（取引のある月 + 全期間）
/// - 月初残高/月末残高を仮想行として上下に表示（自動計算）
/// - 各行の編集（鉛筆アイコン）→ 取引日/摘要/出金/入金/メモ修正
/// - AppBar「+」から入金/出金/振替モーダルを当該口座プリセットで起動
/// - レイアウトは中央メインカラム（最大幅 1000px）に集約
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.account});

  final core.RegisteredBankAccount account;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

/// 最大幅。広い画面でもサマリーバーとリストを同じ幅に揃える。
const double _kContentMaxWidth = 1000;

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];

  /// 編集後の口座スナップショット（startingBalance を保存後に反映するため）。
  /// null の場合は widget.account を使う。late を使うと初期化漏れで
  /// LateInitializationError になることがあるため nullable + getter にした。
  core.RegisteredBankAccount? _updatedAccount;
  core.RegisteredBankAccount get _account =>
      _updatedAccount ?? widget.account;

  /// 月フィルタ。null = 全期間。
  DateTime? _selectedMonth;

  /// カスタム順モード。ON のとき行をドラッグで並び替えでき、その順番を
  /// 各取引の sortOrder に保存する。残高はこのモードでも表示し、
  /// 「表示順に沿って積み上げた値」を出す（並び替えるたびに再計算される）。
  bool _customOrder = false;
  // 月締め処理中フラグ（ボタン多重押し防止）。
  bool _busyClose = false;
  // ウォレット×月ごとの「締め済み」状態（明示的にボタンを押したときだけ立つ）。
  core.MonthClosingConfig _closing = core.MonthClosingConfig.empty();

  // ─── 未保存編集の管理 ─────────────────────
  /// ユーザーが手入力で上書きした月初残高（保存前のローカル状態）。
  int? _pendingMonthStartBalance;

  /// ユーザーが手入力で上書きした月末残高（保存前のローカル状態）。
  int? _pendingMonthEndBalance;

  bool get _hasPendingEdit =>
      _pendingMonthStartBalance != null ||
      _pendingMonthEndBalance != null;

  void _clearPending() {
    _pendingMonthStartBalance = null;
    _pendingMonthEndBalance = null;
  }

  @override
  void initState() {
    super.initState();
    // タブで選択中の月で開く（6月を見ていたら口座詳細も6月から）。
    _selectedMonth = MonthCursor.instance.month;
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
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
    final list = await TransactionRepository.instance.loadAll();
    final closing = await MonthClosingRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _all = list;
      _closing = closing;
    });
  }

  /// ウォレット×月の締めキー（月グローバルの締めと衝突しない接頭辞付き）。
  String _walletMonthKey(DateTime m) =>
      'w:${_account.name}:${m.year}-${m.month.toString().padLeft(2, '0')}';

  bool get _isMonthClosed {
    final m = _selectedMonth;
    if (m == null) return false;
    final key = _walletMonthKey(m);
    return _closing.closings.any((c) => c.yearMonth == key && c.isClosed);
  }

  /// 指定取引の「この口座の月」が締め済みか（全期間表示でも取引日で判定）。
  bool _isClosedForTxn(core.Transaction t) {
    final key = 'w:${_account.name}:'
        '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
    return _closing.closings.any((c) => c.yearMonth == key && c.isClosed);
  }

  /// 締め済みの月の取引を変更しようとしたとき、確認アラートを出す。
  /// 「変更する」を選んだときだけ true を返す（それ以外は false＝編集させない）。
  Future<bool> _confirmEditClosed(core.Transaction t) async {
    if (!_isClosedForTxn(t)) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('締め済みの月です'),
        content: Text(
            '${t.date.month}月は締め済みです。この取引の金額や内容を変更すると、'
            '締めた月の集計・残高が変わります。それでも変更しますか？'),
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

  // ───────────────────────────────────────────────────────────
  // 計算ロジック
  // ───────────────────────────────────────────────────────────

  /// この口座に関連する取引（昇順）から、各時点の残高を計算した行を返す。
  /// 月フィルタは未適用（全期間ベースで残高を計算）。
  List<_LedgerRow> _buildLedgerAllPeriod() {
    final name = _account.name;
    final related = <_RelatedTxn>[];
    for (final t in _all) {
      if (t.type == core.TransactionType.transfer) {
        if (t.transferFromAccount == name) {
          related.add(_RelatedTxn(t, -t.amount));
        } else if (t.transferToAccount == name) {
          related.add(_RelatedTxn(t, t.amount));
        }
      } else if (t.paymentMethod == name) {
        related.add(_RelatedTxn(t,
            t.type == core.TransactionType.income ? t.amount : -t.amount));
      }
    }
    related.sort((a, b) => a.txn.date.compareTo(b.txn.date));

    int balance = _account.startingBalance ?? 0;
    final asc = <_LedgerRow>[];
    for (final r in related) {
      balance += r.signedAmount;
      asc.add(_LedgerRow(
        txn: r.txn,
        signedAmount: r.signedAmount,
        balanceAfter: balance,
      ));
    }
    return asc;
  }

  /// 指定日時点（その日の終わり）での残高を返す。
  int _balanceAt(List<_LedgerRow> ascAll, DateTime cutoff) {
    int balance = _account.startingBalance ?? 0;
    for (final row in ascAll) {
      if (row.txn.date.isAfter(cutoff)) break;
      balance = row.balanceAfter;
    }
    return balance;
  }

  // ───────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ascAll = _buildLedgerAllPeriod();
    // 月フィルタを適用した表示用リスト（降順）
    final filteredAsc = _selectedMonth == null
        ? ascAll
        : ascAll
            .where((r) =>
                r.txn.date.year == _selectedMonth!.year &&
                r.txn.date.month == _selectedMonth!.month)
            .toList();
    final displayRows = filteredAsc.reversed.toList();

    // 月初残高/月末残高（月選択時のみ）
    int? autoMonthStartBalance;
    int? autoMonthEndBalance;
    if (_selectedMonth != null) {
      final m = _selectedMonth!;
      final monthFirst = DateTime(m.year, m.month, 1);
      final monthLast = DateTime(m.year, m.month + 1, 1)
          .subtract(const Duration(seconds: 1));
      final beforeMonth = monthFirst.subtract(const Duration(seconds: 1));
      autoMonthStartBalance = _balanceAt(ascAll, beforeMonth);
      autoMonthEndBalance = _balanceAt(ascAll, monthLast);
    }
    // サマリー（月初/月末の再計算に使うので先に求める）
    final inSum = filteredAsc
        .where((r) => r.signedAmount > 0)
        .fold<int>(0, (s, r) => s + r.signedAmount);
    final outSum = filteredAsc
        .where((r) => r.signedAmount < 0)
        .fold<int>(0, (s, r) => s + (-r.signedAmount));
    final netDelta = inSum - outSum;
    // 「振替（口座間の移動）」と「実収入/実支出」を分けて集計する。
    // 振替は残高は動かすが"本物の収入・支出"ではないので、サマリーで別立てにして
    // 月の実像（実収入・実支出）が振替に埋もれないようにする（案A）。
    int realIn = 0, realOut = 0, transferIn = 0, transferOut = 0;
    for (final r in filteredAsc) {
      if (r.txn.type == core.TransactionType.transfer) {
        if (r.signedAmount > 0) {
          transferIn += r.signedAmount;
        } else {
          transferOut += -r.signedAmount;
        }
      } else if (r.signedAmount > 0) {
        realIn += r.signedAmount;
      } else {
        realOut += -r.signedAmount;
      }
    }
    final transferNet = transferIn - transferOut;

    // 表示用: pending があればそれを使う。
    final dispStart = _pendingMonthStartBalance ?? autoMonthStartBalance;
    // 月末は「月初(表示値) ＋ 当月の増減」で常に自動計算する。
    // （月初を手入力で書き換えたら、その場で月末も追従する＝ズレ防止。
    //   月末だけを明示的に上書きしたときのみ、その値を使う）
    final dispEnd = _pendingMonthEndBalance ??
        (dispStart != null ? dispStart + netDelta : autoMonthEndBalance);
    // ※ 各行の残高は _ledgerTable 側で「表示順に積み上げ（月初残高が起点）」に統一。
    //   月初を手入力で変えても dispStart 起点で自動追従するのでオフセットは不要。

    return PopScope(
      canPop: !_hasPendingEdit,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirm = await _confirmDiscardEdits();
        if (confirm && mounted) {
          _clearPending();
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (_account.iconUrl != null &&
                  _account.iconUrl!.isNotEmpty)
                BrandLogo(
                    iconUrl: _account.iconUrl,
                    fallbackEmoji: _account.accountType.emoji,
                    size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_account.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              if (_hasPendingEdit) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('未保存',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          actions: [
            // 保存ボタン: 未保存編集がある時のみ強調表示
            if (_hasPendingEdit)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('保存'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                  ),
                  onPressed: () => _saveBalanceEdits(
                    autoStart: autoMonthStartBalance,
                    autoEnd: autoMonthEndBalance,
                    inSum: inSum,
                    outSum: outSum,
                    ascAll: ascAll,
                  ),
                ),
              ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              // HOMEと同じ「ボタン脇に出るポップアップメニュー」（画面中央を奪わない）。
              child: PopupMenuButton<String>(
                tooltip: '記録する',
                onSelected: _openRecord,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'income',
                    child: Row(
                      children: const [
                        Icon(Icons.add_circle_outline,
                            size: 16, color: Color(0xFF10B981)),
                        SizedBox(width: 8),
                        Text('入金（収入）を記録'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'expense',
                    child: Row(
                      children: const [
                        Icon(Icons.remove_circle_outline,
                            size: 16, color: Color(0xFFEF4444)),
                        SizedBox(width: 8),
                        Text('出金（支出）を記録'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'transfer',
                    child: Row(
                      children: const [
                        Icon(Icons.swap_horiz,
                            size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Text('振替（他口座へ移動）を記録'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('記録',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down,
                          size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // メインカラムレイアウト: 広い画面では中央寄せ + 最大幅
        body: LayoutBuilder(
          builder: (ctx, constraints) {
            // 締め済みの月は本文（残高カード＋明細）を薄く（グレーアウト）。
            final closed = _isMonthClosed;
            final content = Column(
              children: [
                _monthSelector(),
                _closeMonthBar(),
                Expanded(
                  child: Opacity(
                    opacity: closed ? 0.5 : 1.0,
                    child: Column(
                      children: [
                        _summaryCard(
                          inSum: inSum,
                          outSum: outSum,
                          netDelta: netDelta,
                          realIn: realIn,
                          realOut: realOut,
                          transferNet: transferNet,
                          startBalance: dispStart,
                          endBalance: dispEnd,
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _customOrder
                              ? _reorderLedger(_customSorted(displayRows),
                                  dispStart ?? (_account.startingBalance ?? 0))
                              : _ledgerTable(
                                  // カスタム順（保存した並び順）で表示。並びが未設定なら
                                  // 日付順にフォールバックするので、通常の口座は今まで通り。
                                  displayRows: _customSorted(displayRows),
                                  monthStartBalance: dispStart,
                                  monthEndBalance: dispEnd,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
            if (constraints.maxWidth >= 900) {
              // Row+Spacer で中央寄せ。SizedBoxは幅だけ指定して高さは
              // 親(Row)から受け取る形にすると、内側Columnの Expanded が
              // finite な親制約を持って正常に動作する。
              return Row(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: _kContentMaxWidth,
                    child: content,
                  ),
                  const Spacer(),
                ],
              );
            }
            return content;
          },
        ),
      ),
    );
  }

  /// 未保存編集を破棄して離脱する確認ダイアログ。
  Future<bool> _confirmDiscardEdits() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存していない編集があります'),
        content: const Text(
            '月初/月末残高の編集が未保存です。\n破棄してこの画面を離れますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('破棄して離れる'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 月を切り替える（未保存編集があれば確認）。null=全期間。
  Future<void> _setMonth(DateTime? m) async {
    if (_hasPendingEdit) {
      final ok = await _confirmDiscardEdits();
      if (!ok) return;
      _clearPending();
    }
    if (!mounted) return;
    setState(() => _selectedMonth = m);
    // 月を変えたら共有カーソルにも反映（他タブ・他詳細と揃う）。全期間(null)は書かない。
    if (m != null) MonthCursor.instance.month = m;
  }

  void _shiftMonth(int delta) {
    final now = DateTime.now();
    final base = _selectedMonth ?? DateTime(now.year, now.month);
    _setMonth(DateTime(base.year, base.month + delta));
  }

  Widget _monthSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          const Text('期間: ',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          // 横矢印で月を前後に切替。全期間のときはラベルだけ。
          if (_selectedMonth != null)
            MonthNavBar(
              label: '${_selectedMonth!.year}年${_selectedMonth!.month}月',
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('全期間',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
            ),
          const Spacer(),
          // カスタム順トグル（ON=長押しで並び替え可能・残高列は隠れる）。
          Tooltip(
            message: _customOrder
                ? 'カスタム順：ON（長押しで並び替え・自動保存／残高は非表示）'
                : 'カスタム順に切り替え（自由に並び替えて保存）',
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _customOrder = !_customOrder),
              icon: Icon(Icons.swap_vert,
                  size: 16,
                  color: _customOrder
                      ? const Color(0xFF1A237E)
                      : const Color(0xFF6B7280)),
              label: Text('カスタム順',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          _customOrder ? FontWeight.w700 : FontWeight.w500,
                      color: _customOrder
                          ? const Color(0xFF1A237E)
                          : const Color(0xFF6B7280))),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: _customOrder
                    ? const Color(0xFF1A237E).withValues(alpha: 0.08)
                    : null,
                side: BorderSide(
                    color: _customOrder
                        ? const Color(0xFF1A237E)
                        : const Color(0xFFD1D5DB)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 全期間 ⇄ 月別 切替。
          OutlinedButton.icon(
            onPressed: () => _setMonth(_selectedMonth == null
                ? DateTime(DateTime.now().year, DateTime.now().month)
                : null),
            icon: Icon(
                _selectedMonth == null
                    ? Icons.calendar_view_month
                    : Icons.all_inclusive,
                size: 16),
            label: Text(_selectedMonth == null ? '月別で見る' : '全期間',
                style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  /// カスタム順の並びに整える（sortOrder 昇順、未設定は日付降順で先頭へ）。
  List<_LedgerRow> _customSorted(List<_LedgerRow> rows) {
    final list = [...rows];
    list.sort((a, b) {
      final ao = a.txn.sortOrder, bo = b.txn.sortOrder;
      if (ao == null && bo == null) return -a.txn.date.compareTo(b.txn.date);
      if (ao == null) return -1;
      if (bo == null) return 1;
      return ao.compareTo(bo);
    });
    return list;
  }

  /// カスタム順モードのリスト（ハンドルをドラッグで並び替え・残高列なし）。
  /// クレカ明細と同じ「ドラッグ並び替え」に統一（銀行/現金/電子マネー共通）。
  Widget _reorderLedger(List<_LedgerRow> rows, int seedBalance) {
    if (rows.isEmpty) {
      return const Center(
        child: Text('この期間の取引はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    // 表示順（上＝新しい／下＝古い）に沿って残高を積み上げる。
    // 下（古い方）から月初残高に足していき、各行に「その行まで反映した残高」を出す。
    // ＝並び替えるたびに、この表示順で残高が再計算される。
    final balances = List<int>.filled(rows.length, seedBalance);
    int running = seedBalance;
    for (int i = rows.length - 1; i >= 0; i--) {
      running += rows[i].signedAmount;
      balances[i] = running;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 10, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('ハンドル（⋮⋮）をドラッグで並び替え（この順で保存・残高もこの順で再計算）',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ),
              // まず日付順（新しい順）に整えてから、手でドラッグ微調整する用。
              TextButton.icon(
                onPressed: () {
                  final byDate = [...rows]
                    ..sort((a, b) => -a.txn.date.compareTo(b.txn.date));
                  _saveAccountReorder(byDate);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('日付順（新しい順）に並べ直しました'),
                        duration: Duration(seconds: 2)),
                  );
                },
                icon: const Icon(Icons.sort, size: 16),
                label: const Text('日付順に並べ直す',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF1A237E)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: rows.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final list = [...rows];
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              _saveAccountReorder(list);
            },
            itemBuilder: (context, i) {
              final row = rows[i];
              return DecoratedBox(
                key: ValueKey('acctreorder_${row.txn.id}'),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF1F2F4)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        child: Icon(Icons.drag_indicator,
                            size: 20, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                    Expanded(child: _reorderRow(row, balances[i])),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _reorderRow(_LedgerRow row, int balanceAfter) {
    final t = row.txn;
    final isOut = row.signedAmount < 0;
    final isTransfer = t.type == core.TransactionType.transfer;
    final desc = isTransfer
        ? '振替 ${t.transferFromAccount ?? '?'} → ${t.transferToAccount ?? '?'}'
        : t.description;
    final reviewed = t.reviewed;
    return Container(
      color: reviewed ? const Color(0xFFF3F4F6) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
                '${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 12,
                    color: reviewed
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(desc,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontSize: 12, color: Color(0xFF111827))),
          ),
          const SizedBox(width: 8),
          Text(
              isOut
                  ? '-${formatYen(-row.signedAmount)}'
                  : '+${formatYen(row.signedAmount)}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: isOut
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A))),
          // 残高（この表示順で積み上げた値）。
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(formatYen(balanceAfter),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: balanceAfter >= 0
                        ? const Color(0xFF111827)
                        : const Color(0xFFDC2626))),
          ),
          SizedBox(
            width: 34,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: reviewed,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: const Color(0xFF6B7280),
                  onChanged: (v) => _toggleReviewed(t, v ?? false),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 16, color: Color(0xFF6B7280)),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            tooltip: '編集',
            onPressed: () => _showEditDialog(t),
          ),
        ],
      ),
    );
  }

  /// 並び替え結果を各取引の sortOrder（0,1,2…）として保存する。
  /// updateMany で一括更新＝通知は1回だけ（並び替え中のチラつき防止）。
  /// 画面は即反映され、サーバ書き込みは裏で完了。失敗時のみ再読込。
  void _saveAccountReorder(List<_LedgerRow> ordered) {
    final txns = [
      for (int i = 0; i < ordered.length; i++)
        ordered[i].txn.copyWith(sortOrder: i.toDouble())
    ];
    unawaited(TransactionRepository.instance.updateMany(txns).catchError((_) {
      if (mounted) _load();
    }));
  }

  static const _cGreen = Color(0xFF16A34A);
  static const _cRed = Color(0xFFDC2626);
  static const _cSky = Color(0xFF0284C7);
  // 振替（口座間の移動）を表す青。支出/収入の赤緑と区別する。
  static const _cTransfer = Color(0xFF2563EB);

  Widget _summaryCard({
    required int inSum,
    required int outSum,
    required int netDelta,
    required int realIn,
    required int realOut,
    required int transferNet,
    int? startBalance,
    int? endBalance,
  }) {
    final hasMonth = startBalance != null && endBalance != null;
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: hasMonth
          ? _balanceFlowStrip(
              startBalance, endBalance, realIn, realOut, transferNet, netDelta)
          // 全期間は月初/月末が無いので、実収入/実支出/振替/差引を並べる。
          : Row(
              children: [
                _summaryItem('実収入', formatYen(realIn), _cGreen),
                const SizedBox(width: 8),
                _summaryItem('実支出', formatYen(realOut), _cRed),
                const SizedBox(width: 8),
                _summaryItem('振替',
                    formatYen(transferNet, withSign: true), _cTransfer),
                const SizedBox(width: 8),
                _summaryItem('差引', formatYen(netDelta, withSign: true),
                    netDelta >= 0 ? _cGreen : _cRed),
              ],
            ),
    );
  }

  /// 月初 → 実収入/実支出/振替 → 月末 の残高フロー帯（案A）。
  Widget _balanceFlowStrip(int start, int end, int realIn, int realOut,
      int transferNet, int net) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // 月初残高
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('月初残高',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                const SizedBox(height: 4),
                Text(formatYen(start),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          // 実収入 / 実支出 / 振替
          SizedBox(
            width: 168,
            child: Column(
              children: [
                _flowChip('実収入', '+${formatYen(realIn)}', _cGreen,
                    const Color(0xFFF0FDF4), Icons.south_west),
                const SizedBox(height: 6),
                _flowChip('実支出', '−${formatYen(realOut)}', _cRed,
                    const Color(0xFFFEF2F2), Icons.north_east),
                const SizedBox(height: 6),
                _flowChip(
                    '振替',
                    formatYen(transferNet, withSign: true),
                    _cTransfer,
                    const Color(0xFFEFF6FF),
                    Icons.swap_horiz),
              ],
            ),
          ),
          // 月末残高 ＋ 差引
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('月末残高',
                    style: TextStyle(fontSize: 12, color: _cSky)),
                const SizedBox(height: 4),
                Text(formatYen(end),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _cSky,
                        fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: net >= 0
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('差引 ${formatYen(net, withSign: true)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: net >= 0 ? _cGreen : _cRed)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowChip(
      String label, String value, Color color, Color bg, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  Widget _ledgerTable({
    required List<_LedgerRow> displayRows,
    int? monthStartBalance,
    int? monthEndBalance,
  }) {
    if (displayRows.isEmpty &&
        monthStartBalance == null &&
        monthEndBalance == null) {
      return const Center(
        child: Text('この期間の取引はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    // 残高は「表示されている順番」に沿って積み上げる（下＝古い側から月初残高に足す）。
    // これでカスタム順に並べても、その並び順どおりに残高が再計算される。
    final seed = monthStartBalance ?? (_account.startingBalance ?? 0);
    final balances = List<int>.filled(displayRows.length, seed);
    int running = seed;
    for (int i = displayRows.length - 1; i >= 0; i--) {
      running += displayRows[i].signedAmount;
      balances[i] = running;
    }
    // 列幅を固定した Table で揃える（DataTableの不揃いを解消）。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(92), // 取引日
            1: FixedColumnWidth(78), // 種別
            2: FlexColumnWidth(), // 摘要
            3: FixedColumnWidth(88), // 支出
            4: FixedColumnWidth(88), // 収入
            5: FixedColumnWidth(104), // 振替
            6: FixedColumnWidth(108), // 残高
            7: FixedColumnWidth(44), // 確認チェック
            8: FixedColumnWidth(40), // 編集
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
              horizontalInside:
                  BorderSide(color: Color(0xFFF1F2F4), width: 1)),
          children: [
            _ledgerHeaderRow(),
            if (monthEndBalance != null && _selectedMonth != null)
              _virtualBalanceRow(
                label: '月末残高',
                date: DateTime(
                    _selectedMonth!.year, _selectedMonth!.month + 1, 0),
                balance: monthEndBalance,
                background: const Color(0xFFE0F2FE),
                isMonthStart: false,
                isEdited: _pendingMonthEndBalance != null,
              ),
            for (int i = 0; i < displayRows.length; i++)
              _txnRow(displayRows[i], balances[i]),
            if (monthStartBalance != null && _selectedMonth != null)
              _virtualBalanceRow(
                label: '月初残高',
                date:
                    DateTime(_selectedMonth!.year, _selectedMonth!.month, 1),
                balance: monthStartBalance,
                background: const Color(0xFFFEF3C7),
                isMonthStart: true,
                isEdited: _pendingMonthStartBalance != null,
              ),
          ],
        ),
      ),
    );
  }

  static const _cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 11);

  TableRow _ledgerHeaderRow() {
    Widget h(String s, {bool right = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(s,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
        );
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF3F4F6)),
      children: [
        h('取引日'),
        h('種別'),
        h('摘要'),
        h('支出', right: true),
        h('収入', right: true),
        h('振替', right: true),
        h('残高', right: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
          child: Text('確認',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
        ),
        const SizedBox.shrink(),
      ],
    );
  }

  /// 月初/月末残高の仮想行（残高セルをタップで手入力編集可能）。
  /// [isMonthStart] true=月初残高、false=月末残高
  /// [isEdited] true なら pending 編集中（オレンジ枠で強調）
  TableRow _virtualBalanceRow({
    required String label,
    required DateTime date,
    required int balance,
    required Color background,
    required bool isMonthStart,
    required bool isEdited,
  }) {
    return TableRow(
      decoration: BoxDecoration(color: background),
      children: [
        Padding(
          padding: _cellPad,
          child: Text(
              '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ),
        const SizedBox.shrink(), // 種別
        Padding(
          padding: _cellPad,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151))),
        ),
        const SizedBox.shrink(), // 支出
        const SizedBox.shrink(), // 収入
        const SizedBox.shrink(), // 振替
        // 残高：他の行と同じ右端に揃える（鉛筆は次の編集列へ）。
        Padding(
          padding: _cellPad,
          child: Text(formatYen(balance),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: isEdited
                      ? const Color(0xFFEA580C)
                      : const Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ),
        // 確認列（残高行にはチェック無し）。
        const SizedBox.shrink(),
        // 編集列（鉛筆）。
        IconButton(
          icon: Icon(Icons.edit,
              size: 14,
              color: isEdited
                  ? const Color(0xFFEA580C)
                  : const Color(0xFF9CA3AF)),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          tooltip: isMonthStart ? '月初残高を修正' : '月末残高を修正',
          onPressed: () => _editVirtualBalance(isMonthStart, balance),
        ),
      ],
    );
  }

  Future<void> _editVirtualBalance(bool isMonthStart, int currentValue) async {
    final ctrl =
        NoComposingUnderlineController(text: formatAmount(currentValue));
    final newValue = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMonthStart ? '月初残高を修正' : '月末残高を修正'),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              HalfWidthDigitsFormatter(),
              ThousandsSeparatorInputFormatter(),
            ],
            decoration: const InputDecoration(
              labelText: '残高（円）',
              prefixText: '¥ ',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final v = parseAmount(ctrl.text);
              if (v != null) Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (newValue == null) return;
    setState(() {
      if (isMonthStart) {
        _pendingMonthStartBalance = newValue;
      } else {
        _pendingMonthEndBalance = newValue;
      }
    });
  }

  /// 保存ボタン押下時: 整合性チェック → startingBalance を逆算して保存。
  Future<void> _saveBalanceEdits({
    required int? autoStart,
    required int? autoEnd,
    required int inSum,
    required int outSum,
    required List<_LedgerRow> ascAll,
  }) async {
    if (_selectedMonth == null) return;
    if (autoStart == null) return;
    final newStart = _pendingMonthStartBalance ?? autoStart;
    // 月末を明示上書きしていなければ「月初＋当月増減」を期待値にする
    // （月初だけ直したときに整合性エラーを出さないため）。
    final newEnd = _pendingMonthEndBalance ?? (newStart + inSum - outSum);

    // 整合性チェック: 月初 + 入金合計 - 出金合計 = 期待月末残高
    final expectedEnd = newStart + inSum - outSum;
    if (expectedEnd != newEnd) {
      final diff = newEnd - expectedEnd;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Color(0xFFDC2626)),
              SizedBox(width: 8),
              Text('整合性エラー'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('計算が合いません。',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('月初残高: ${formatYen(newStart)}'),
              Text('+ 入金合計: ${formatYen(inSum)}'),
              Text('- 出金合計: ${formatYen(outSum)}'),
              const Divider(),
              Text('= 期待月末残高: ${formatYen(expectedEnd)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A237E))),
              const SizedBox(height: 8),
              Text('入力された月末残高: ${formatYen(newEnd)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '差額: ${formatYen(diff, withSign: true)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 8),
              const Text(
                '取引漏れ or 月初/月末残高の入力ミスの可能性があります。',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('修正に戻る')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'force'),
              child: const Text('月初優先で保存'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(ctx, 'adjust'),
              child: const Text('差額調整を追加して合わせる'),
            ),
          ],
        ),
      );
      if (action == 'cancel' || action == null) return;
      // 差額調整を選んだら、この月の末日に「差額調整（強制変更）」を1件作る。
      if (action == 'adjust') {
        await _addBalanceAdjustment(diff);
      }
    }

    // 月初残高 → startingBalance を逆算
    // 月初前までの取引差分（自動計算ベース）= autoStart - 現在のstartingBalance
    final currentStarting = _account.startingBalance ?? 0;
    final deltaBeforeMonth = autoStart - currentStarting;
    final newStartingBalance = newStart - deltaBeforeMonth;

    try {
      final cfg = await SettingsRepository.instance.loadPayments();
      final updated = <core.RegisteredBankAccount>[];
      core.RegisteredBankAccount? updatedSelf;
      for (final a in cfg.bankAccounts) {
        if (a.id == _account.id) {
          final newA = core.RegisteredBankAccount(
            id: a.id,
            name: a.name,
            last4: a.last4,
            startingBalance: newStartingBalance,
            currentBalance: a.currentBalance,
            accountType: a.accountType,
            iconUrl: a.iconUrl,
            memo: a.memo,
          );
          updated.add(newA);
          updatedSelf = newA;
        } else {
          updated.add(a);
        }
      }
      await SettingsRepository.instance.savePayments(
        core.PaymentMethodsConfig(
          bankAccounts: updated,
          creditCards: cfg.creditCards,
        ),
      );
      // 他画面（ホーム残高/資産タブ等）に変更を通知して再ロードさせる
      PaymentsChangeNotifier.instance.notifyChanged();
      if (!mounted) return;
      setState(() {
        _clearPending();
        // 自分自身の最新値で _account も更新して画面に反映させる
        if (updatedSelf != null) {
          _updatedAccount = updatedSelf;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '残高を更新しました（開始残高: ${formatYen(newStartingBalance)}）'),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

  /// 月末残高の強制変更にあわせて、差額ぶんの「差額調整（強制変更）」を作る。
  /// 収支・PLには載せないため振替扱い（相手は擬似口座「差額調整」）。
  /// 口座台帳（このウォレットの残高）だけを diff ぶん動かして帳尻を合わせる。
  Future<void> _addBalanceAdjustment(int diff) async {
    final m = _selectedMonth;
    if (m == null || diff == 0) return;
    final lastDay = DateTime(m.year, m.month + 1, 0);
    final up = diff > 0; // 残高を増やす方向か
    final tx = core.Transaction(
      id: '${DateTime.now().microsecondsSinceEpoch}adj',
      date: lastDay,
      type: core.TransactionType.transfer,
      category: const core.Category(major: '差額調整', sub: ''),
      paymentMethod: '',
      description: '差額調整（強制変更）',
      amount: diff.abs(),
      transferFromAccount: up ? '差額調整' : _account.name,
      transferToAccount: up ? _account.name : '差額調整',
      reviewed: true,
      memo: 'アプリ導入前などのズレを、入力した月末残高に合わせて調整',
    );
    await TransactionRepository.instance.add(tx);
  }

  TableRow _txnRow(_LedgerRow row, int shownBalance) {
    final t = row.txn;
    final isOut = row.signedAmount < 0;
    final isTransfer = t.type == core.TransactionType.transfer;
    // 差額調整（強制変更）は赤字で目立たせ、摘要は説明文をそのまま出す。
    final isAdjust = t.category.major == '差額調整';
    final desc = isAdjust
        ? t.description
        : isTransfer
            ? '振替 ${t.transferFromAccount ?? '?'} → ${t.transferToAccount ?? '?'}'
            : t.description;
    Widget money(String s, Color c) => Padding(
          padding: _cellPad,
          child: Text(s,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: c,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
        );
    final reviewed = t.reviewed;
    return TableRow(
      // 確認済みは薄いグレー背景。
      decoration: reviewed
          ? const BoxDecoration(color: Color(0xFFF3F4F6))
          : null,
      children: [
      Padding(
        padding: _cellPad,
        child: Text(
            '${t.date.year}/${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}',
            style: TextStyle(
                fontSize: 12,
                color: reviewed
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF6B7280))),
      ),
      // 種別（入金/出金/振替）。タップで変更（振替は移動先を尋ねる）。
      _typeCell(t),
      Padding(
        padding: _cellPad,
        child: Text(desc,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
                fontSize: 12,
                // 差額調整（強制変更）は赤字＋太字で目立たせる。
                fontWeight: isAdjust ? FontWeight.w700 : FontWeight.w400,
                color: isAdjust
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF111827))),
      ),
      // 支出列：振替以外の出金だけ（赤）。
      money(!isTransfer && isOut ? formatYen(-row.signedAmount) : '',
          const Color(0xFFDC2626)),
      // 収入列：振替以外の入金だけ（緑）。
      money(!isTransfer && !isOut ? formatYen(row.signedAmount) : '',
          const Color(0xFF16A34A)),
      // 振替列：口座間の移動だけ（青・符号付き）。支出/収入とは別立て。
      money(
          isTransfer
              ? (isOut
                  ? '−${formatYen(-row.signedAmount)}'
                  : '+${formatYen(row.signedAmount)}')
              : '',
          _cTransfer),
      Padding(
        padding: _cellPad,
        child: Text(formatYen(shownBalance),
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12,
                color: shownBalance >= 0
                    ? const Color(0xFF111827)
                    : const Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace')),
      ),
      // 確認済みチェック（締め処理用）。
      Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: reviewed,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: const Color(0xFF6B7280),
            onChanged: (v) => _toggleReviewed(t, v ?? false),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined,
            size: 16, color: Color(0xFF6B7280)),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
        tooltip: '編集',
        onPressed: () => _showEditDialog(t),
      ),
    ]);
  }

  /// 種別ラベル（入金/出金/振替）を色付きチップで表示（読み取り専用）。
  Widget _typeCell(core.Transaction t) {
    final String label;
    final Color fg;
    final Color bg;
    switch (t.type) {
      case core.TransactionType.transfer:
        label = '振替';
        fg = _cTransfer;
        bg = const Color(0xFFEFF6FF);
        break;
      case core.TransactionType.income:
        label = '入金';
        fg = _cGreen;
        bg = const Color(0xFFF0FDF4);
        break;
      case core.TransactionType.expense:
        label = '出金';
        fg = _cRed;
        bg = const Color(0xFFFEF2F2);
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      ),
    );
  }

  Future<void> _toggleReviewed(core.Transaction t, bool value) async {
    await TransactionRepository.instance
        .update(t.copyWith(reviewed: value));
    if (mounted) await _load();
  }

  /// 選択中の月で、このウォレットに関係する取引（支払元/入金先/振替の相手）。
  List<core.Transaction> _monthRelatedTxns() {
    final m = _selectedMonth;
    if (m == null) return const [];
    final name = _account.name;
    return _all.where((t) {
      if (t.date.year != m.year || t.date.month != m.month) return false;
      if (t.type == core.TransactionType.transfer) {
        return t.transferFromAccount == name || t.transferToAccount == name;
      }
      return t.paymentMethod == name;
    }).toList();
  }

  /// この月を締める＝この月のこのウォレットの取引を全部「確認済み」にする。
  Future<void> _setClosedFlag(DateTime m, bool closed) async {
    final key = _walletMonthKey(m);
    final existing = _closing.closings.firstWhere(
      (c) => c.yearMonth == key,
      orElse: () => core.MonthClosing(yearMonth: key),
    );
    final updated = closed
        ? existing.copyWith(closedAt: DateTime.now())
        : existing.copyWith(clearClosedAt: true);
    await MonthClosingRepository.instance.save(_closing.upsert(updated));
  }

  /// この月を締める＝取引を全部「確認済み」にして、明示的な締めフラグを立てる。
  Future<void> _closeMonth() async {
    final m = _selectedMonth;
    if (m == null) return;
    final txns = _monthRelatedTxns();
    final todo = txns.where((t) => !t.reviewed).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('${m.month}月を締めますか？'),
        content: Text(
            '「${_account.name}」の${m.year}年${m.month}月の取引 ${txns.length}件を、'
            'すべて「確認済み（金額に間違いなし）」にして締めます。'),
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
    setState(() => _busyClose = true);
    for (final t in todo) {
      await TransactionRepository.instance.update(t.copyWith(reviewed: true));
    }
    await _setClosedFlag(m, true);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _busyClose = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${m.month}月を締めました')));
  }

  /// 締めを解除＝締めフラグを外す（確認チェックはそのまま残す）。
  Future<void> _reopenMonth() async {
    final m = _selectedMonth;
    if (m == null) return;
    setState(() => _busyClose = true);
    await _setClosedFlag(m, false);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _busyClose = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${m.month}月の締めを解除しました')));
  }

  /// 月の締めバー（月選択時のみ）。
  /// 締め済みは「ユーザーが締めボタンを押したとき」だけ（チェック全部でも自動では締めない）。
  Widget _closeMonthBar() {
    final m = _selectedMonth;
    if (m == null) return const SizedBox.shrink();
    final txns = _monthRelatedTxns();
    if (txns.isEmpty) return const SizedBox.shrink();
    final closed = _isMonthClosed;
    final doneCount = txns.where((t) => t.reviewed).length;
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
                  ? '${m.month}月は締め済み（全${txns.length}件 確認済み）'
                  : '確認済み $doneCount/${txns.length}件',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: closed
                      ? const Color(0xFF059669)
                      : const Color(0xFF6B7280)),
            ),
          ),
          if (closed)
            TextButton(
              onPressed: _busyClose ? null : _reopenMonth,
              child: const Text('締め解除'),
            )
          else
            FilledButton.icon(
              onPressed: _busyClose ? null : _closeMonth,
              icon: _busyClose
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle, size: 16),
              label: Text('${m.month}月を締める'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  visualDensity: VisualDensity.compact),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 編集ダイアログ（行の鉛筆アイコンから呼ぶ）
  // ───────────────────────────────────────────────────────────

  Future<void> _showEditDialog(core.Transaction t) async {
    // 締め済みの月の取引なら、まず確認アラート。「変更する」以外は編集しない。
    if (!await _confirmEditClosed(t)) return;
    if (!mounted) return;
    // 種類別に、アプリ共通の入力画面（中央ポップアップ）で編集する。
    // 以前はこの画面だけ独自の AlertDialog で、広い画面だと中身がグレーの
    // まま出ない不具合があったため、他画面と同じ入力フォームに統一した。
    final Widget screen;
    switch (t.type) {
      case core.TransactionType.transfer:
        screen = TransferInputScreen(editing: t);
        break;
      case core.TransactionType.income:
        screen = IncomeInputScreen(editing: t);
        break;
      case core.TransactionType.expense:
        screen = ExpenseInputScreen(editing: t);
        break;
    }
    final changed = await showInputSheet<bool>(context, screen);
    if (changed == true && mounted) await _load();
  }

  // ───────────────────────────────────────────────────────────
  // 「+」ボタンの追加メニュー
  // ───────────────────────────────────────────────────────────

  /// ポップアップメニューから選ばれた種別で入力画面を開く（このウォレットをプリフィル）。
  Future<void> _openRecord(String kind) async {
    final accountName = _account.name;
    final Widget screen;
    switch (kind) {
      case 'income':
        screen = IncomeInputScreen(initialReceiveAccount: accountName);
        break;
      case 'transfer':
        screen = TransferInputScreen(initialFromAccount: accountName);
        break;
      default:
        screen = ExpenseInputScreen(initialPaymentMethod: accountName);
    }
    final saved = await showInputSheet<bool>(context, screen);
    if (saved == true && mounted) await _load();
  }
}

class _RelatedTxn {
  _RelatedTxn(this.txn, this.signedAmount);
  final core.Transaction txn;
  final int signedAmount;
}

class _LedgerRow {
  _LedgerRow({
    required this.txn,
    required this.signedAmount,
    required this.balanceAfter,
  });
  final core.Transaction txn;
  final int signedAmount;
  final int balanceAfter;
}
