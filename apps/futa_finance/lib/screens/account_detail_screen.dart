import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
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
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
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

  /// 月選択肢: 取引がある年月（降順）+ 全期間 + 当月（常に含める）。
  /// 取引が0件の口座でも残高編集ができるよう、当月は無条件で選択肢に出す。
  List<DateTime?> _availableMonths() {
    final name = _account.name;
    final set = <DateTime>{};
    // 当月は無条件で含める
    final now = DateTime.now();
    set.add(DateTime(now.year, now.month));
    for (final t in _all) {
      final isRelated = (t.type == core.TransactionType.transfer)
          ? (t.transferFromAccount == name || t.transferToAccount == name)
          : (t.paymentMethod == name);
      if (!isRelated) continue;
      set.add(DateTime(t.date.year, t.date.month));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return [null, ...list];
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
    // 表示用: pending があればそれを使う
    final dispStart = _pendingMonthStartBalance ?? autoMonthStartBalance;
    final dispEnd = _pendingMonthEndBalance ?? autoMonthEndBalance;

    // サマリー
    final inSum = filteredAsc
        .where((r) => r.signedAmount > 0)
        .fold<int>(0, (s, r) => s + r.signedAmount);
    final outSum = filteredAsc
        .where((r) => r.signedAmount < 0)
        .fold<int>(0, (s, r) => s + (-r.signedAmount));
    final netDelta = inSum - outSum;

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
            IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF1A237E)),
              tooltip: '取引を追加',
              onPressed: _showAddMenu,
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
                  child: _ledgerTable(
                    displayRows: displayRows,
                    monthStartBalance: dispStart,
                    monthEndBalance: dispEnd,
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

  Widget _monthSelector() {
    final months = _availableMonths();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Text('期間: ',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          DropdownButton<DateTime?>(
            value: _selectedMonth,
            underline: const SizedBox.shrink(),
            items: months.map((m) {
              final label = m == null ? '全期間' : '${m.year}年${m.month}月';
              return DropdownMenuItem<DateTime?>(
                value: m,
                child: Text(label),
              );
            }).toList(),
            onChanged: (v) async {
              // 未保存編集があったら確認
              if (_hasPendingEdit) {
                final ok = await _confirmDiscardEdits();
                if (!ok) return;
                _clearPending();
              }
              setState(() => _selectedMonth = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required int inSum,
    required int outSum,
    required int netDelta,
    int? startBalance,
    int? endBalance,
  }) {
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // ── 月初/月末 残高（主役、大きく強調） ──
          if (startBalance != null || endBalance != null) ...[
            Row(
              children: [
                if (startBalance != null)
                  _balanceHeadlineCard(
                    label: '月初残高',
                    value: startBalance,
                    accent: const Color(0xFFEAB308), // 黄系
                  ),
                if (startBalance != null && endBalance != null)
                  const SizedBox(width: 10),
                if (endBalance != null)
                  _balanceHeadlineCard(
                    label: '月末残高',
                    value: endBalance,
                    accent: const Color(0xFF0EA5E9), // 水色系
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // ── 入金/出金/差引（補助、小さめ） ──
          Row(
            children: [
              _summaryItem(
                  '入金合計', formatYen(inSum), const Color(0xFF16A34A)),
              const SizedBox(width: 10),
              _summaryItem(
                  '出金合計', formatYen(outSum), const Color(0xFFDC2626)),
              const SizedBox(width: 10),
              _summaryItem(
                '差引',
                formatYen(netDelta, withSign: true),
                netDelta >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 月初/月末残高の見出しカード（強調表示）。
  Widget _balanceHeadlineCard({
    required String label,
    required int value,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatYen(value),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
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
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF3F4F6)),
            headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151)),
            dataTextStyle: const TextStyle(
                fontSize: 12, color: Color(0xFF111827)),
            columnSpacing: 16,
            horizontalMargin: 12,
            columns: const [
              DataColumn(label: Text('取引日')),
              DataColumn(label: Text('摘要')),
              DataColumn(label: Text('出金'), numeric: true),
              DataColumn(label: Text('入金'), numeric: true),
              DataColumn(label: Text('残高'), numeric: true),
              DataColumn(label: SizedBox.shrink()), // 編集アイコン列
            ],
            rows: [
              // 月末残高（先頭 = 一番上）
              if (monthEndBalance != null && _selectedMonth != null)
                _virtualBalanceRow(
                  label: '月末残高',
                  date: DateTime(_selectedMonth!.year,
                      _selectedMonth!.month + 1, 0),
                  balance: monthEndBalance,
                  background: const Color(0xFFE0F2FE),
                  isMonthStart: false,
                  isEdited: _pendingMonthEndBalance != null,
                ),
              // 通常の取引行
              for (final row in displayRows) _txnRow(row),
              // 月初残高（末尾 = 一番下）
              if (monthStartBalance != null && _selectedMonth != null)
                _virtualBalanceRow(
                  label: '月初残高',
                  date: DateTime(
                      _selectedMonth!.year, _selectedMonth!.month, 1),
                  balance: monthStartBalance,
                  background: const Color(0xFFFEF3C7),
                  isMonthStart: true,
                  isEdited: _pendingMonthStartBalance != null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 月初/月末残高の仮想行（残高セルをタップで手入力編集可能）。
  /// [isMonthStart] true=月初残高、false=月末残高
  /// [isEdited] true なら pending 編集中（オレンジ枠で強調）
  DataRow _virtualBalanceRow({
    required String label,
    required DateTime date,
    required int balance,
    required Color background,
    required bool isMonthStart,
    required bool isEdited,
  }) {
    return DataRow(
      color: WidgetStateProperty.all(background),
      cells: [
        DataCell(Text(
            '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280)))),
        DataCell(Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151)))),
        const DataCell(Text('')),
        const DataCell(Text('')),
        DataCell(
          InkWell(
            onTap: () => _editVirtualBalance(isMonthStart, balance),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isEdited
                      ? const Color(0xFFEA580C)
                      : Colors.transparent,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatYen(balance),
                    style: TextStyle(
                        color: isEdited
                            ? const Color(0xFFEA580C)
                            : const Color(0xFF111827),
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit,
                      size: 11,
                      color: isEdited
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF9CA3AF)),
                ],
              ),
            ),
          ),
        ),
        const DataCell(SizedBox.shrink()),
      ],
    );
  }

  Future<void> _editVirtualBalance(bool isMonthStart, int currentValue) async {
    final ctrl =
        TextEditingController(text: currentValue.toString());
    final newValue = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMonthStart ? '月初残高を修正' : '月末残高を修正'),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
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
              final v = int.tryParse(ctrl.text.replaceAll(',', ''));
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
    final newEnd = _pendingMonthEndBalance ?? autoEnd ?? 0;

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

  DataRow _txnRow(_LedgerRow row) {
    final t = row.txn;
    final isOut = row.signedAmount < 0;
    final isTransfer = t.type == core.TransactionType.transfer;
    final desc = isTransfer
        ? '振替 ${t.transferFromAccount ?? '?'} → ${t.transferToAccount ?? '?'}'
        : t.description;
    return DataRow(cells: [
      DataCell(Text(
          '${t.date.year}/${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}')),
      DataCell(SizedBox(
        width: 220,
        child: Text(desc, overflow: TextOverflow.ellipsis),
      )),
      DataCell(Text(
        isOut ? formatYen(-row.signedAmount) : '',
        style: const TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace'),
      )),
      DataCell(Text(
        isOut ? '' : formatYen(row.signedAmount),
        style: const TextStyle(
            color: Color(0xFF16A34A),
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace'),
      )),
      DataCell(Text(
        formatYen(row.balanceAfter),
        style: TextStyle(
            color: row.balanceAfter >= 0
                ? const Color(0xFF111827)
                : const Color(0xFFDC2626),
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace'),
      )),
      DataCell(
        IconButton(
          icon: const Icon(Icons.edit_outlined,
              size: 16, color: Color(0xFF6B7280)),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          tooltip: '編集',
          onPressed: () => _showEditDialog(t),
        ),
      ),
    ]);
  }

  // ───────────────────────────────────────────────────────────
  // 編集ダイアログ（行の鉛筆アイコンから呼ぶ）
  // ───────────────────────────────────────────────────────────

  Future<void> _showEditDialog(core.Transaction t) async {
    final isTransfer = t.type == core.TransactionType.transfer;
    final isOut = (t.type == core.TransactionType.expense) ||
        (isTransfer && t.transferFromAccount == _account.name);

    DateTime editingDate = t.date;
    final descCtrl = TextEditingController(text: t.description);
    final amountCtrl = TextEditingController(text: t.amount.toString());
    final memoCtrl = TextEditingController(text: t.memo ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('取引を編集',
                style: TextStyle(fontWeight: FontWeight.w700)),
            // SingleChildScrollView でラップして広い画面でも content が
            // 縮退しないようにする（Web ではこの保険がないと中身が消える）
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // 取引日
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('取引日',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                    subtitle: Text(
                      '${editingDate.year}/${editingDate.month.toString().padLeft(2, '0')}/${editingDate.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 16),
                    onTap: () async {
                      final picked =
                          await showCupertinoModalPopup<DateTime>(
                        context: ctx,
                        builder: (_) => Container(
                          height: 280,
                          color: Colors.white,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 40,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.end,
                                  children: [
                                    CupertinoButton(
                                      onPressed: () => Navigator.pop(
                                          ctx, editingDate),
                                      child: const Text('完了'),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: CupertinoDatePicker(
                                  mode: CupertinoDatePickerMode.date,
                                  initialDateTime: editingDate,
                                  onDateTimeChanged: (d) =>
                                      editingDate = d,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (picked != null) {
                        setLocal(() => editingDate = picked);
                      }
                    },
                  ),
                  // 摘要
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: '摘要',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 金額（出金/入金の方向はそのまま、絶対値だけ編集）
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isOut ? '出金額（円）' : '入金額（円）',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      prefixText: '¥ ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // メモ
                  TextField(
                    controller: memoCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'メモ',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isTransfer)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '※ 振替の移動元/先はここでは変更不可',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  // 削除確認
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (delCtx) => AlertDialog(
                      title: const Text('取引を削除しますか？'),
                      content: const Text('元に戻せません。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(delCtx, false),
                            child: const Text('キャンセル')),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626)),
                          onPressed: () => Navigator.pop(delCtx, true),
                          child: const Text('削除'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await TransactionRepository.instance.delete(t.id);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx, true);
                  }
                },
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626)),
                child: const Text('削除'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () async {
                  final newAmount =
                      int.tryParse(amountCtrl.text.replaceAll(',', ''));
                  if (newAmount == null || newAmount <= 0) return;
                  final updated = t.copyWith(
                    date: editingDate,
                    description: descCtrl.text.trim(),
                    amount: newAmount,
                    memo: memoCtrl.text.trim().isEmpty
                        ? null
                        : memoCtrl.text.trim(),
                  );
                  await TransactionRepository.instance.update(updated);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        });
      },
    );
    if (saved == true && mounted) {
      // Stream で自動更新されるはずだが念のため
      await _load();
    }
  }

  // ───────────────────────────────────────────────────────────
  // 「+」ボタンの追加メニュー
  // ───────────────────────────────────────────────────────────

  Future<void> _showAddMenu() async {
    final accountName = _account.name;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.arrow_downward,
                    color: Color(0xFF16A34A)),
                title: const Text('入金（収入）を記録'),
                subtitle: Text('入金先: $accountName'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IncomeInputScreen(
                          initialReceiveAccount: accountName),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_upward,
                    color: Color(0xFFDC2626)),
                title: const Text('出金（支出）を記録'),
                subtitle: Text('支払元: $accountName'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpenseInputScreen(
                          initialPaymentMethod: accountName),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz,
                    color: Color(0xFFEA580C)),
                title: const Text('振替（他口座へ移動）を記録'),
                subtitle: Text('移動元: $accountName'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransferInputScreen(
                          initialFromAccount: accountName),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
