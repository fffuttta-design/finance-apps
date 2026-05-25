import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../utils/formatters.dart';

/// 年間払い契約。次回請求までのカウントダウンを表示。
class AnnualContractsCard extends StatelessWidget {
  final List<AnnualContract> contracts;
  final DateTime today;

  const AnnualContractsCard(
      {super.key, required this.contracts, required this.today});

  Color _countdownColor(int? days) {
    if (days == null) return const Color(0xFF9CA3AF);
    if (days < 30) return const Color(0xFFDC2626);
    if (days < 90) return const Color(0xFFF59E0B);
    return const Color(0xFF1A237E);
  }

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
              color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_repeat, size: 16, color: Color(0xFF1A237E)),
              SizedBox(width: 6),
              Text(
                '年間払い契約',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...contracts.map((c) {
            final days = c.daysUntilCharge(today);
            final color = _countdownColor(days);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          days == null
                              ? (c.memo ?? '次回請求日未設定')
                              : 'あと$days日 (${c.nextChargeDate!.month}/${c.nextChargeDate!.day})',
                          style: TextStyle(fontSize: 10, color: color),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatYen(c.amount),
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF111827),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
