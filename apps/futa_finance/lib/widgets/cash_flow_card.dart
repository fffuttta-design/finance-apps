import 'package:flutter/material.dart';

import '../mock/dashboard_summary.dart';
import '../utils/formatters.dart';

/// 資金口座の月初→当月支出→想定残高 のフロー表示。
class CashFlowCard extends StatelessWidget {
  final DashboardSummary summary;

  const CashFlowCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  size: 16, color: Color(0xFF7986CB)),
              const SizedBox(width: 6),
              Text(
                '資金口座（${summary.account.name}）',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row('月初', formatYen(summary.account.monthStartBalance),
              const Color(0xFFE5E7EB), fontSize: 14),
          const SizedBox(height: 6),
          _row('当月支出', formatYen(-summary.monthTotal, withSign: true),
              const Color(0xFFEF5350),
              fontSize: 14, mono: true),
          const SizedBox(height: 8),
          Container(height: 1, color: const Color(0xFF1F2937)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('想定残高',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFE5E7EB),
                      fontWeight: FontWeight.w500)),
              Text(
                formatYen(summary.projectedRemaining),
                style: const TextStyle(
                  fontSize: 22,
                  color: Color(0xFF66BB6A),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor,
      {double fontSize = 14, bool mono = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        Text(value,
            style: TextStyle(
              fontSize: fontSize,
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
            )),
      ],
    );
  }
}
