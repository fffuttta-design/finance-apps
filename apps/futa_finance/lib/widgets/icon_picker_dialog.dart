import 'package:flutter/material.dart';

import '../utils/category_icons.dart';

/// アイコン選択ダイアログ。グリッド表示で全候補からタップで選択。
/// 返り値: 選択された iconKey (Map のキー名)。キャンセル時は null。
Future<String?> showIconPickerDialog(
  BuildContext context, {
  String? currentKey,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _IconPickerDialog(currentKey: currentKey),
  );
}

class _IconPickerDialog extends StatelessWidget {
  final String? currentKey;

  const _IconPickerDialog({this.currentKey});

  @override
  Widget build(BuildContext context) {
    final entries = kCategoryIcons.entries.toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                const Text('アイコンを選択',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${entries.length}個',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  final selected = entry.key == currentKey;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(context, entry.key),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFE0E7FF)
                            : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF1A237E)
                              : const Color(0xFFE5E7EB),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        entry.value,
                        color: selected
                            ? const Color(0xFF1A237E)
                            : const Color(0xFF374151),
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
