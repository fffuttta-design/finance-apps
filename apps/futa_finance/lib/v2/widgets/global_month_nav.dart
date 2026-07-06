import 'package:flutter/material.dart';

import '../../data/month_cursor.dart';
import 'month_nav_bar.dart';

/// トップバーに置く「共有月」ナビ（‹ YYYY年M月 ›）。
///
/// 全タブが [MonthCursor] を購読しているので、ここで月を変えると
/// ホーム/支出/収入/業績の各タブが一斉に追従する。各タブ内の月ナビは廃止し、
/// 月の切り替えはこの1か所に集約する。
class GlobalMonthNav extends StatelessWidget {
  const GlobalMonthNav({super.key});

  void _shift(int delta) {
    final m = MonthCursor.instance.month;
    MonthCursor.instance.month = DateTime(m.year, m.month + delta);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MonthCursor.instance,
      builder: (context, _) {
        final m = MonthCursor.instance.month;
        return MonthNavBar(
          label: '${m.year}年${m.month}月',
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
        );
      },
    );
  }
}
