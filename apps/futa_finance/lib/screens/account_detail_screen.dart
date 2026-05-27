import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

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

  /// 月フィルタ。null = 全期間。
  DateTime? _selectedMonth;

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
    final name = widget.account.name;
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

    int balance = widget.account.startingBalance ?? 0;
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
    int balance = widget.account.startingBalance ?? 0;
    for (final row in ascAll) {
      if (row.txn.date.isAfter(cutoff)) break;
      balance = row.balanceAfter;
    }
    return balance;
  }

  /// 月選択肢: 取引がある年月（降順）+ 全期間。
  List<DateTime?> _availableMonths() {
    final name = widget.account.name;
    final set = <DateTime>{};
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
    int? monthStartBalance;
    int? monthEndBalance;
    if (_selectedMonth != null) {
      final m = _selectedMonth!;
      final monthFirst = DateTime(m.year, m.month, 1);
      final monthLast = DateTime(m.year, m.month + 1, 1)
          .subtract(const Duration(seconds: 1));
      // 月初残高 = 月1日0時の残高 = 月1日0時より前 (前日23:59:59) までの累計
      final beforeMonth = monthFirst.subtract(const Duration(seconds: 1));
      monthStartBalance = _balanceAt(ascAll, beforeMonth);
      monthEndBalance = _balanceAt(ascAll, monthLast);
    }

    // サマリー
    final inSum = filteredAsc
        .where((r) => r.signedAmount > 0)
        .fold<int>(0, (s, r) => s + r.signedAmount);
    final outSum = filteredAsc
        .where((r) => r.signedAmount < 0)
        .fold<int>(0, (s, r) => s + (-r.signedAmount));
    final netDelta = inSum - outSum;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.account.iconUrl != null &&
                widget.account.iconUrl!.isNotEmpty)
              BrandLogo(
                  iconUrl: widget.account.iconUrl,
                  fallbackEmoji: widget.account.accountType.emoji,
                  size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.account.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
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
                startBalance: monthStartBalance,
                endBalance: monthEndBalance,
              ),
              const Divider(height: 1),
              Expanded(
                child: _ledgerTable(
                  displayRows: displayRows,
                  monthStartBalance: monthStartBalance,
                  monthEndBalance: monthEndBalance,
                ),
              ),
            ],
          );
          if (constraints.maxWidth >= 900) {
            return Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _kContentMaxWidth),
                child: content,
              ),
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
            onChanged: (v) => setState(() => _selectedMonth = v),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              _summaryItem(
                  '入金合計', formatYen(inSum), const Color(0xFF16A34A)),
              const SizedBox(width: 12),
              _summaryItem(
                  '出金合計', formatYen(outSum), const Color(0xFFDC2626)),
              const SizedBox(width: 12),
              _summaryItem(
                '差引',
                formatYen(netDelta, withSign: true),
                netDelta >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ],
          ),
          if (startBalance != null || endBalance != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (startBalance != null)
                  Text(
                    '月初残高: ${formatYen(startBalance)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                if (endBalance != null)
                  Text(
                    '月末残高: ${formatYen(endBalance)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ],
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 月初/月末残高の仮想行（編集不可、背景色付き）。
  DataRow _virtualBalanceRow({
    required String label,
    required DateTime date,
    required int balance,
    required Color background,
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
        DataCell(Text(
          formatYen(balance),
          style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace'),
        )),
        const DataCell(SizedBox.shrink()),
      ],
    );
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
        (isTransfer && t.transferFromAccount == widget.account.name);

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
            content: SizedBox(
              width: 360,
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
    final accountName = widget.account.name;
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
