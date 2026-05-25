import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../mock/dashboard_summary.dart';
import '../mock/mock_data.dart';
import '../widgets/annual_contracts_card.dart';
import '../widgets/cash_flow_card.dart';
import '../widgets/category_heat_grid.dart';
import '../widgets/pace_projection_card.dart';
import '../widgets/recent_transactions_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final summary = DashboardSummary(
      account: MockData.account,
      transactions: MockData.transactions,
      annualContracts: MockData.annualContracts,
      today: MockData.today,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.account_balance, size: 22, color: Color(0xFF7986CB)),
            SizedBox(width: 8),
            Text(
              'FutaFinance',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${summary.today.year}年${summary.today.month}月',
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            CashFlowCard(summary: summary),
            const SizedBox(height: 12),
            PaceProjectionCard(summary: summary),
            const SizedBox(height: 12),
            CategoryHeatGrid(summary: summary),
            const SizedBox(height: 12),
            AnnualContractsCard(
              contracts: summary.annualContracts,
              today: summary.today,
            ),
            const SizedBox(height: 12),
            RecentTransactionsCard(
              transactions: summary.recentTransactions(limit: 6),
            ),
            const SizedBox(height: 24),
            // フッター情報（バージョン・接続先）
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final projectId = Firebase.app().options.projectId;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF374151)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'v1.0.3+4  /  com.futa.finance',
            style: TextStyle(
                fontSize: 10,
                color: Color(0xFF6B7280),
                fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_done,
                size: 12, color: Color(0xFF66BB6A)),
            const SizedBox(width: 4),
            Text(
              'Firebase: $projectId',
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF66BB6A),
                  fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }
}
