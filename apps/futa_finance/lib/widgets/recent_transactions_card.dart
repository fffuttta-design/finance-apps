import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../utils/formatters.dart';

/// 直近の取引フロー。お金の動きが時系列で見える。
class RecentTransactionsCard extends StatelessWidget {
  final List<core.Transaction> transactions;

  const RecentTransactionsCard({super.key, required this.transactions});

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
              Icon(Icons.timeline, size: 16, color: Color(0xFF1A237E)),
              SizedBox(width: 6),
              Text(
                '直近の動き',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...transactions.map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        formatMonthDay(t.date),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            fontFamily: 'monospace'),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.description,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF111827)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${t.category.major.substring(2)} · ${t.paymentMethod}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF9CA3AF)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatYen(-t.amount, withSign: true),
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFDC2626),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
