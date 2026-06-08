import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/drive_receipt_service.dart';

/// レシート画像をアプリ内で表示する画面。
/// ブラウザや再ログイン不要で、Drive の権限トークンで画像を取得して表示する。
class ReceiptImageScreen extends StatefulWidget {
  /// DriveのファイルID（receiptUrl から抽出して渡す）。
  final String fileId;
  const ReceiptImageScreen({super.key, required this.fileId});

  @override
  State<ReceiptImageScreen> createState() => _ReceiptImageScreenState();
}

class _ReceiptImageScreenState extends State<ReceiptImageScreen> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = DriveReceiptService.instance.downloadFile(widget.fileId);
  }

  void _retry() {
    setState(() {
      _future = DriveReceiptService.instance.downloadFile(widget.fileId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('レシート'),
      ),
      body: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) {
            final err = DriveReceiptService.instance.lastError;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined,
                        size: 48, color: Colors.white54),
                    const SizedBox(height: 12),
                    Text(
                      '画像を取得できませんでした${err != null ? '\n($err)' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _retry, child: const Text('もう一度')),
                  ],
                ),
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.memory(bytes)),
          );
        },
      ),
    );
  }
}
