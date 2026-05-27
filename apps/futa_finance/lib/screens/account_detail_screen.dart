import 'dart:async';

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
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.account});

  final core.RegisteredBankAccount account;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];

  /// 月フィルタ。null = 全期間。
  DateTime? _selectedMonth;

  @override
  void initState() {
    super.initState();
    // デフォルトで「今月」を選択
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

  /// 「+」ボタン押下時のアクションシート。
  /// この口座をプリセットした入力モーダルを呼び出す。
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

  /// この口座に関連する取引のみを抽出（収入/支出/振替）。
  /// 各取引に対して符号付き金額（収入＝+、支出＝-、振替元＝-、振替先＝+）と
  /// その時点の残高を計算する。
  List<_LedgerRow> _buildLedger() {
    final name = widget.account.name;

    // この口座に関連する全取引（日付昇順）
    final related = <_RelatedTxn>[];
    for (final t in _all) {
      if (t.type == core.TransactionType.transfer) {
        if (t.transferFromAccount == name) {
          related.add(_RelatedTxn(t, -t.amount, _Direction.out));
        } else if (t.transferToAccount == name) {
          related.add(_RelatedTxn(t, t.amount, _Direction.inAmount));
        }
      } else if (t.paymentMethod == name) {
        if (t.type == core.TransactionType.income) {
          related.add(_RelatedTxn(t, t.amount, _Direction.inAmount));
        } else {
          related.add(_RelatedTxn(t, -t.amount, _Direction.out));
        }
      }
    }
    related.sort((a, b) => a.txn.date.compareTo(b.txn.date));

    // 累積残高を計算（昇順）
    int balance = widget.account.startingBalance ?? 0;
    final asc = <_LedgerRow>[];
    for (final r in related) {
      balance += r.signedAmount;
      asc.add(_LedgerRow(
        txn: r.txn,
        direction: r.direction,
        signedAmount: r.signedAmount,
        balanceAfter: balance,
      ));
    }

    // 月フィルタ
    final filtered = asc.where((row) {
      if (_selectedMonth == null) return true;
      final m = _selectedMonth!;
      return row.txn.date.year == m.year && row.txn.date.month == m.month;
    }).toList();

    // 表示は降順（新しい順）
    return filtered.reversed.toList();
  }

  /// 月選択肢: この口座の取引がある年月を一覧（降順）+ 全期間。
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
    return [null, ...list]; // null = 全期間
  }

  @override
  Widget build(BuildContext context) {
    final ledger = _buildLedger();
    final months = _availableMonths();
    // 月次サマリー
    final inSum =
        ledger.where((r) => r.signedAmount > 0).fold<int>(0, (s, r) => s + r.signedAmount);
    final outSum = ledger
        .where((r) => r.signedAmount < 0)
        .fold<int>(0, (s, r) => s + (-r.signedAmount));
    final netDelta = inSum - outSum;
    // 期間の最初・最後の残高
    final periodEndBalance = ledger.isEmpty ? null : ledger.first.balanceAfter;
    final periodStartBalance =
        ledger.isEmpty ? null : ledger.last.balanceAfter - ledger.last.signedAmount;

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
      body: Column(
        children: [
          // 月セレクター
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Text('期間: ',
                    style:
                        TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                DropdownButton<DateTime?>(
                  value: _selectedMonth,
                  underline: const SizedBox.shrink(),
                  items: months.map((m) {
                    final label = m == null
                        ? '全期間'
                        : '${m.year}年${m.month}月';
                    return DropdownMenuItem<DateTime?>(
                      value: m,
                      child: Text(label),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedMonth = v),
                ),
              ],
            ),
          ),
          // サマリーカード
          if (ledger.isNotEmpty)
            _summaryCard(
              inSum: inSum,
              outSum: outSum,
              netDelta: netDelta,
              startBalance: periodStartBalance,
              endBalance: periodEndBalance,
            ),
          const Divider(height: 1),
          // 通帳テーブル
          Expanded(child: _ledgerTable(ledger)),
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
              _summaryItem('入金合計', formatYen(inSum),
                  const Color(0xFF16A34A)),
              const SizedBox(width: 12),
              _summaryItem('出金合計', formatYen(outSum),
                  const Color(0xFFDC2626)),
              const SizedBox(width: 12),
              _summaryItem(
                  '差引',
                  formatYen(netDelta, withSign: true),
                  netDelta >= 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626)),
            ],
          ),
          if (startBalance != null || endBalance != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (startBalance != null)
                  Text(
                    '期首残高: ${formatYen(startBalance)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                if (endBalance != null)
                  Text(
                    '期末残高: ${formatYen(endBalance)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF111827),
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

  Widget _ledgerTable(List<_LedgerRow> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text('この期間の取引はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
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
            ],
            rows: rows.map((row) {
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
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}

enum _Direction { inAmount, out }

class _RelatedTxn {
  _RelatedTxn(this.txn, this.signedAmount, this.direction);
  final core.Transaction txn;
  final int signedAmount;
  final _Direction direction;
}

class _LedgerRow {
  _LedgerRow({
    required this.txn,
    required this.direction,
    required this.signedAmount,
    required this.balanceAfter,
  });
  final core.Transaction txn;
  final _Direction direction;
  final int signedAmount;
  final int balanceAfter;
}
