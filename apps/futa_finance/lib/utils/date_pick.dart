import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 端末（画面幅）に応じて日付選択 UI を出し分ける。
/// - 広い画面（PC）：見やすい Material のカレンダー（showDatePicker）
/// - 狭い画面（スマホ）：従来のホイール（CupertinoDatePicker）
///
/// 選択された日付を返す（キャンセル時は null）。
Future<DateTime?> pickAdaptiveDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) async {
  var init = initial;
  if (init.isBefore(first)) init = first;
  if (init.isAfter(last)) init = last;

  // PC（広い画面）はホイールが見づらいのでカレンダーを出す。
  final isWide = MediaQuery.sizeOf(context).width >= 600;
  if (isWide) {
    return showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
    );
  }

  // スマホ：従来のホイール（Cupertino）。
  DateTime temp = init;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheet) => SafeArea(
      child: Container(
        height: 280,
        color: Colors.white,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(sheet, null),
                  child: const Text('キャンセル',
                      style: TextStyle(color: Color(0xFF6B7280))),
                ),
                const Text('日付を選択',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827))),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, temp),
                  child: const Text('完了',
                      style: TextStyle(
                          color: Color(0xFF1A237E),
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            Container(height: 1, color: const Color(0xFFE5E7EB)),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: temp,
                minimumDate: first,
                maximumDate: last,
                dateOrder: DatePickerDateOrder.ymd,
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
