import 'package:flutter/material.dart';

import '../mock/dashboard_summary.dart';
import '../utils/formatters.dart';

/// ウォレットの月初→当月支出→想定残高 のフロー表示。
class CashFlowCard extends StatelessWidget {
  final DashboardSummary summary;

  const CashFlowCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  size: 16, color: Color(0xFF1A237E)),
              const SizedBox(width: 6),
              Text(
                'ウォレット（${summary.accountName}）',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row('現在残高', formatYen(summary.monthStartBalance),
              const Color(0xFF111827),
              fontSize: 14),
          const SizedBox(height: 6),
          if (summary.monthIncomeTotal > 0) ...[
            _row('当月収入', formatYen(summary.monthIncomeTotal, withSign: true),
                const Color(0xFF16A34A),
                fontSize: 14, mono: true),
            const SizedBox(height: 6),
          ],
          _row('当月支出', formatYen(-summary.monthExpenseTotal, withSign: true),
              const Color(0xFFDC2626),
              fontSize: 14, mono: true),
          const SizedBox(height: 8),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('想定残高',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w500)),
              Text(
                formatYen(summary.projectedRemaining),
                style: const TextStyle(
                  fontSize: 22,
                  color: Color(0xFF16A34A),
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
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
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
