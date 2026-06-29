import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/drive_receipt_service.dart';
import '../screens/receipt_image_screen.dart';

/// Drive の「指定モード×月」フォルダにある領収書を一覧表示し、1件選んで
/// その閲覧リンク(webViewLink)を返すボトムシート。
/// ※ drive.file 権限のため、このアプリが保存した領収書のみ表示される。
Future<String?> showDriveReceiptPicker(
  BuildContext context, {
  required DateTime date,
  required bool isBusiness,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _DriveReceiptPicker(date: date, isBusiness: isBusiness),
  );
}

class _DriveReceiptPicker extends StatefulWidget {
  final DateTime date;
  final bool isBusiness;
  const _DriveReceiptPicker({required this.date, required this.isBusiness});

  @override
  State<_DriveReceiptPicker> createState() => _DriveReceiptPickerState();
}

class _DriveReceiptPickerState extends State<_DriveReceiptPicker> {
  late Future<List<DriveReceiptFile>> _future;

  @override
  void initState() {
    super.initState();
    _future = DriveReceiptService.instance
        .listMonthReceipts(date: widget.date, isBusiness: widget.isBusiness);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Driveの領収書を選ぶ（${widget.date.year}年${widget.date.month}月）',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<DriveReceiptFile>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final files = snap.data ?? const [];
                  if (files.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 36, color: Color(0xFF9CA3AF)),
                          const SizedBox(height: 10),
                          const Text(
                            'この月にアプリ保存の領収書はありません',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFF6B7280)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DriveReceiptService.instance.lastError ??
                                '「画像を保存」で上げた領収書がここに並びます。',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF9CA3AF)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: files.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFEEF0F3)),
                    itemBuilder: (context, i) => _row(files[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(DriveReceiptFile f) {
    final c = f.createdTime;
    final sub = c == null
        ? 'Drive保存ファイル'
        : '${c.year}/${c.month}/${c.day} 保存';
    return ListTile(
      leading: _Thumb(fileId: f.id),
      title: Text(f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(sub,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_full, size: 18),
        tooltip: 'プレビュー',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReceiptImageScreen(fileId: f.id)),
        ),
      ),
      onTap: () => Navigator.pop(context, f.webViewLink),
    );
  }
}

/// 一覧の小サムネ。Drive からバイトを取得して表示（取得失敗時はアイコン）。
class _Thumb extends StatefulWidget {
  final String fileId;
  const _Thumb({required this.fileId});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    DriveReceiptService.instance.downloadFile(widget.fileId).then((b) {
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _failed = b == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = Image.memory(_bytes!,
          width: 40, height: 40, fit: BoxFit.cover, cacheWidth: 80);
    } else if (_failed) {
      child = const Icon(Icons.receipt_long,
          size: 20, color: Color(0xFF9CA3AF));
    } else {
      child = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
