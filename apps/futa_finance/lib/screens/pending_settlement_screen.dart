import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 入金締め処理画面。
///
/// 「見込み」フラグの立った収入取引を一覧表示し、
/// 実際に入金された時点で「確定」に切り替える。
/// 月末締めの拡張概念で、「翌月の入金確定日に本当に締まる」イメージ。
class PendingSettlementScreen extends StatefulWidget {
  const PendingSettlementScreen({super.key});

  @override
  State<PendingSettlementScreen> createState() =>
      _PendingSettlementScreenState();
}

class _PendingSettlementScreenState extends State<PendingSettlementScreen> {
  List<core.Transaction> _pending = [];
  core.PaymentMethodsConfig? _payments;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await TransactionRepository.instance.loadAll();
    final p = await SettingsRepository().loadPayments();
    final pending = all
        .where((t) => t.type == core.TransactionType.income && t.isPending)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date)); // 古い順
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _payments = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total =
        _pending.fold<int>(0, (s, t) => s + t.amount);
    return Scaffold(
      appBar: AppBar(
        title: const Text('入金締め処理',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 説明
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFCD34D)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.hourglass_top,
                            size: 18, color: Color(0xFFD97706)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '「見込み売上」として登録した取引を、'
                            '実際の入金で確定するための画面です。\n'
                            '「確定」を押すと残高に反映され、PL も実額になります。',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // サマリーカード
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pending_actions,
                            size: 18, color: Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        const Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('未確定の見込み売上',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827))),
                            Text('合計（${'件数'}）',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6B7280))),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${_pending.length} 件',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF))),
                            Text(
                              formatYen(total),
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEA580C),
                                  fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 一括確定ボタン
                  if (_pending.isNotEmpty) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('全件を確定にする'),
                      onPressed: _settleAll,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        side: const BorderSide(
                            color: Color(0xFF16A34A)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 個別リスト
                  if (_pending.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Center(
                        child: Text('見込み売上はありません',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF))),
                      ),
                    )
                  else
                    ..._pending.map(_pendingTile),
                ],
              ),
      ),
    );
  }

  Widget _pendingTile(core.Transaction t) {
    final amountCtrl =
        TextEditingController(text: t.amount.toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('見込み',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706))),
              ),
              const SizedBox(width: 8),
              Text(
                  '${t.date.year}/${t.date.month}/${t.date.day}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.description.isEmpty
                      ? t.category.sub
                      : t.description,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('入金先: ${t.paymentMethod}',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 10),
          // 金額確定欄
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('確定額',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(),
                    suffixText: '円',
                  ),
                  style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('確定'),
                onPressed: () =>
                    _settleOne(t, int.tryParse(amountCtrl.text.trim())),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 1件を確定（金額を更新して isPending=false + 残高反映）
  Future<void> _settleOne(core.Transaction t, int? finalAmount) async {
    if (finalAmount == null || finalAmount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正しい金額を入力してください')),
      );
      return;
    }
    final updated = t.copyWith(amount: finalAmount, isPending: false);
    await TransactionRepository.instance.update(updated);
    // 入金先銀行口座の残高を増やす
    await _addToBalance(t.paymentMethod, finalAmount);
    PaymentsChangeNotifier.instance.notifyChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${t.description} を確定しました')),
    );
    await _load();
  }

  /// 全件をそのままの額で確定（金額編集なし）
  Future<void> _settleAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('全件を確定にする'),
        content: Text(
            '${_pending.length} 件の見込み売上を、現在の金額のまま確定にします。\n'
            '個別に金額を変えたい場合は個別「確定」ボタンを使ってください。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('一括確定')),
        ],
      ),
    );
    if (ok != true) return;

    for (final t in _pending) {
      final updated = t.copyWith(isPending: false);
      await TransactionRepository.instance.update(updated);
      await _addToBalance(t.paymentMethod, t.amount);
    }
    PaymentsChangeNotifier.instance.notifyChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全件を確定しました')),
    );
    await _load();
  }

  /// 指定の銀行口座の現在残高に金額を加算する。
  Future<void> _addToBalance(String accountName, int amount) async {
    if (_payments == null) return;
    final accounts = _payments!.bankAccounts;
    final updated = accounts.map((b) {
      if (b.name == accountName) {
        final newBalance = (b.displayBalance ?? 0) + amount;
        return b.copyWith(currentBalance: newBalance);
      }
      return b;
    }).toList();
    final newPayments = _payments!.copyWith(bankAccounts: updated);
    await SettingsRepository().savePayments(newPayments);
    _payments = newPayments;
  }
}
