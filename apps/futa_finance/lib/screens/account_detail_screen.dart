import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

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

  /// カスタム順モード。ON のとき行を長押しドラッグで並び替えでき、その順番を
  /// 各取引の sortOrder に保存する。※残高は日付順が前提のため、このモード中は
  /// 残高列・月初/月末残高を隠す。
  bool _customOrder = false;

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
    if (!mounted) return;
    setState(() => _all = list);
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

    // 表示用: pending があればそれを使う。
    final dispStart = _pendingMonthStartBalance ?? autoMonthStartBalance;
    // 月末は「月初(表示値) ＋ 当月の増減」で常に自動計算する。
    // （月初を手入力で書き換えたら、その場で月末も追従する＝ズレ防止。
    //   月末だけを明示的に上書きしたときのみ、その値を使う）
    final dispEnd = _pendingMonthEndBalance ??
        (dispStart != null ? dispStart + netDelta : autoMonthEndBalance);
    // 途中残高の表示オフセット（月初を手入力で変えたぶん、各行の残高もずらす）。
    final balanceOffset =
        (dispStart != null && autoMonthStartBalance != null)
            ? dispStart - autoMonthStartBalance
            : 0;

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
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _showAddMenu,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('記録',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(width: 2),
                    Icon(Icons.add, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        // メインカラムレイアウト: 広い画面では中央寄せ + 最大幅
        body: LayoutBuilder(
          builder: (ctx, constraints) {
            final content = Column(
              children: [
                _monthSelector(),
                _summaryCard(
                  inSum: inSum,
                  outSum: outSum,
                  netDelta: netDelta,
                  startBalance: dispStart,
                  endBalance: dispEnd,
                ),
                const Divider(height: 1),
                Expanded(
                  child: _customOrder
                      ? _reorderLedger(_customSorted(displayRows))
                      : _ledgerTable(
                          displayRows: displayRows,
                          monthStartBalance: dispStart,
                          monthEndBalance: dispEnd,
                          balanceOffset: balanceOffset,
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

  /// カスタム順モードのリスト（長押しドラッグで並び替え・残高列なし）。
  Widget _reorderLedger(List<_LedgerRow> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text('この期間の取引はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6, left: 2),
            child: Text('▲▼ボタンで並び替え（この順で保存）・残高は日付順のとき表示',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: Color(0xFFF1F2F4)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _AccountMoveButtons(
                        onUp: i > 0
                            ? () => _moveAccountRow(i, i - 1, rows)
                            : null,
                        onDown: i < rows.length - 1
                            ? () => _moveAccountRow(i, i + 1, rows)
                            : null,
                      ),
                      Expanded(child: _reorderRow(rows[i])),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 行を1つ上/下へ動かして sortOrder を保存する。
  void _moveAccountRow(int from, int to, List<_LedgerRow> rows) {
    final list = [...rows];
    final item = list.removeAt(from);
    list.insert(to, item);
    _saveAccountReorder(list);
  }

  Widget _reorderRow(_LedgerRow row) {
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
  /// update() は同期でキャッシュ更新＆stream通知するので await せず投げる＝
  /// 画面は即座に並び替わる（サーバ書き込みは裏で完了。▲▼の反応遅延を解消）。
  void _saveAccountReorder(List<_LedgerRow> ordered) {
    final writes = <Future<void>>[];
    for (int i = 0; i < ordered.length; i++) {
      writes.add(TransactionRepository.instance
          .update(ordered[i].txn.copyWith(sortOrder: i.toDouble())));
    }
    unawaited(Future.wait(writes).catchError((_) {
      if (mounted) _load();
      return <void>[];
    }));
  }

  static const _cGreen = Color(0xFF16A34A);
  static const _cRed = Color(0xFFDC2626);
  static const _cSky = Color(0xFF0284C7);

  Widget _summaryCard({
    required int inSum,
    required int outSum,
    required int netDelta,
    int? startBalance,
    int? endBalance,
  }) {
    final hasMonth = startBalance != null && endBalance != null;
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: hasMonth
          ? _balanceFlowStrip(startBalance, endBalance, inSum, outSum, netDelta)
          // 全期間は月初/月末が無いので、入金/出金/差引のみ。
          : Row(
              children: [
                _summaryItem('入金合計', formatYen(inSum), _cGreen),
                const SizedBox(width: 10),
                _summaryItem('出金合計', formatYen(outSum), _cRed),
                const SizedBox(width: 10),
                _summaryItem('差引', formatYen(netDelta, withSign: true),
                    netDelta >= 0 ? _cGreen : _cRed),
              ],
            ),
    );
  }

  /// 月初 → ＋入金/−出金 → 月末 の残高フロー帯（案A）。
  Widget _balanceFlowStrip(
      int start, int end, int inSum, int outSum, int net) {
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
          // 入金 / 出金
          SizedBox(
            width: 150,
            child: Column(
              children: [
                _flowChip('入金', '+${formatYen(inSum)}', _cGreen,
                    const Color(0xFFF0FDF4), Icons.south_west),
                const SizedBox(height: 6),
                _flowChip('出金', '−${formatYen(outSum)}', _cRed,
                    const Color(0xFFFEF2F2), Icons.north_east),
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
    int balanceOffset = 0,
  }) {
    if (displayRows.isEmpty &&
        monthStartBalance == null &&
        monthEndBalance == null) {
      return const Center(
        child: Text('この期間の取引はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
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
            0: FixedColumnWidth(108),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(100),
            3: FixedColumnWidth(100),
            4: FixedColumnWidth(124),
            5: FixedColumnWidth(44), // 確認チェック
            6: FixedColumnWidth(40), // 編集
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
            for (final row in displayRows) _txnRow(row, balanceOffset),
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
        h('摘要'),
        h('出金', right: true),
        h('入金', right: true),
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
        Padding(
          padding: _cellPad,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151))),
        ),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
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
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('修正に戻る')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C)),
              onPressed: () => Navigator.pop(ctx, 'force'),
              child: const Text('月初優先で強制保存'),
            ),
          ],
        ),
      );
      if (action != 'force') return;
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

  TableRow _txnRow(_LedgerRow row, [int balanceOffset = 0]) {
    final t = row.txn;
    final shownBalance = row.balanceAfter + balanceOffset;
    final isOut = row.signedAmount < 0;
    final isTransfer = t.type == core.TransactionType.transfer;
    final desc = isTransfer
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
      Padding(
        padding: _cellPad,
        child: Text(desc,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(fontSize: 12, color: Color(0xFF111827))),
      ),
      money(isOut ? formatYen(-row.signedAmount) : '',
          const Color(0xFFDC2626)),
      money(isOut ? '' : formatYen(row.signedAmount),
          const Color(0xFF16A34A)),
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

  Future<void> _toggleReviewed(core.Transaction t, bool value) async {
    await TransactionRepository.instance
        .update(t.copyWith(reviewed: value));
    if (mounted) await _load();
  }

  // ───────────────────────────────────────────────────────────
  // 編集ダイアログ（行の鉛筆アイコンから呼ぶ）
  // ───────────────────────────────────────────────────────────

  Future<void> _showEditDialog(core.Transaction t) async {
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

  Future<void> _showAddMenu() async {
    final accountName = _account.name;
    // 他画面と同じ「中央ポップアップ」に統一（下から出るシートはやめる）。
    final choice = await showDialog<String>(
      context: context,
      builder: (dctx) => SimpleDialog(
        title: const Text('記録する', style: TextStyle(fontWeight: FontWeight.w700)),
        children: [
          _addMenuTile(dctx, 'income', Icons.arrow_downward,
              const Color(0xFF16A34A), '入金（収入）を記録', '入金先: $accountName'),
          _addMenuTile(dctx, 'expense', Icons.arrow_upward,
              const Color(0xFFDC2626), '出金（支出）を記録', '支払元: $accountName'),
          _addMenuTile(dctx, 'transfer', Icons.swap_horiz,
              const Color(0xFFEA580C), '振替（他口座へ移動）を記録', '移動元: $accountName'),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final Widget screen;
    switch (choice) {
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

  Widget _addMenuTile(BuildContext dctx, String value, IconData icon,
      Color color, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.pop(dctx, value),
    );
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

/// カスタム順モードで行の左に置く ▲▼ ボタン（1行ずつ上下へ動かす）。
class _AccountMoveButtons extends StatelessWidget {
  const _AccountMoveButtons({required this.onUp, required this.onDown});

  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Icon(icon,
                size: 20,
                color: onTap == null
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFF1A237E)),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        btn(Icons.keyboard_arrow_up, onUp),
        btn(Icons.keyboard_arrow_down, onDown),
      ],
    );
  }
}
