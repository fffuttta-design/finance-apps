import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// 「M/D(曜)」を、**日付は通常色のまま・曜日だけ**を土=青/日=赤で表示する。
///
/// 例: 「6/7」は黒、「(日)」だけ赤。明細の日付列で使う。
Widget dateWeekdayText(DateTime d, {required TextStyle baseStyle}) {
  final wc = weekendColor(d);
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: monthDayOnly(d)),
        TextSpan(
          text: weekdayParen(d),
          style: wc != null ? TextStyle(color: wc) : null,
        ),
      ],
    ),
    style: baseStyle,
    // 日付は 1 行固定。狭い列でも「(火)」の閉じ括弧が次行に落ちないようにする。
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.visible,
  );
}
