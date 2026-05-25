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
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline, size: 16, color: Color(0xFF7986CB)),
              SizedBox(width: 6),
              Text(
                '直近の動き',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
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
                            color: Color(0xFF9CA3AF),
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
                                fontSize: 13, color: Color(0xFFE5E7EB)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${t.category.major.substring(2)} · ${t.paymentMethod}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF6B7280)),
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
                          color: Color(0xFFEF5350),
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
