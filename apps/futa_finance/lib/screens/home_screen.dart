import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../mock/dashboard_summary.dart';
import '../mock/mock_data.dart';
import '../widgets/annual_contracts_card.dart';
import '../widgets/cash_flow_card.dart';
import '../widgets/category_heat_grid.dart';
import '../widgets/recent_transactions_card.dart';
import 'expense_input_screen.dart';
import 'income_input_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _settings = SettingsRepository();
  final _txRepo = TransactionRepository.instance;
  StreamSubscription<List<Transaction>>? _sub;

  List<Transaction> _transactions = [];
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final payments = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _payments = payments;
      _loading = false;
    });
  }

  /// 登録銀行口座の startingBalance を合算して月初想定残高とする。
  int get _monthStartBalance => _payments.bankAccounts
      .fold(0, (sum, b) => sum + (b.startingBalance ?? 0));

  String get _accountName {
    final banks = _payments.bankAccounts;
    if (banks.isEmpty) return '未設定';
    if (banks.length == 1) return banks.first.name;
    return '${banks.first.name} 他${banks.length - 1}口座';
  }

  void _openAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.remove_circle_outline,
                    color: Color(0xFFDC2626)),
              ),
              title: const Text('支出を追加',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('経費・購入・引き落としなど',
                  style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExpenseInputScreen()),
                ).then((_) => _load());
              },
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF16A34A)),
              ),
              title: const Text('収入を追加',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('売上・入金など（収入マスタから選択）',
                  style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const IncomeInputScreen()),
                ).then((_) => _load());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    final summary = DashboardSummary(
      today: today,
      allTransactions: _transactions,
      monthStartBalance: _monthStartBalance,
      accountName: _accountName,
      annualContracts: MockData.annualContracts,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance, size: 22, color: Color(0xFF1A237E)),
            SizedBox(width: 8),
            Text(
              'FutaFinance',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Color(0xFF111827)),
            ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${today.year}年${today.month}月',
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('記録'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _transactions.isEmpty
                  ? _emptyState()
                  : ListView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: [
                        CashFlowCard(summary: summary),
                        const SizedBox(height: 12),
                        CategoryHeatGrid(summary: summary),
                        const SizedBox(height: 12),
                        AnnualContractsCard(
                          contracts: summary.annualContracts,
                          today: today,
                        ),
                        const SizedBox(height: 12),
                        RecentTransactionsCard(
                          transactions: summary.recentTransactions(limit: 6),
                        ),
                        const SizedBox(height: 24),
                        _footer(),
                      ],
                    ),
            ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 72, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('まだ取引がありません',
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            const Text('右下の「記録」ボタンから追加できます',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 24),
            _footer(),
          ],
        ),
      );

  Widget _footer() {
    final projectId = Firebase.app().options.projectId;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'v1.0.9+10  /  com.futa.finance',
            style: TextStyle(
                fontSize: 10,
                color: Color(0xFF9CA3AF),
                fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_done, size: 12, color: Color(0xFF16A34A)),
            const SizedBox(width: 4),
            Text(
              'Firebase: $projectId',
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF16A34A),
                  fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }
}
