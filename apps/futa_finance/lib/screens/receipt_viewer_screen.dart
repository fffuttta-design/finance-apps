import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/drive_receipt_service.dart';

/// 証憑（請求書/領収書）をアプリ内で表示する画面。
/// Driveの正本(driveUrl)を、所有者本人の権限(drive.readonly)でダウンロードして
/// アプリ内表示（PDFはpdfrx・画像はImage）。取得に失敗したらDriveを外部で開く。
class ReceiptViewerScreen extends StatefulWidget {
  final String driveUrl;
  final String title; // '請求書' or '領収書'

  const ReceiptViewerScreen({
    super.key,
    required this.driveUrl,
    this.title = '証憑',
  });

  @override
  State<ReceiptViewerScreen> createState() => _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends State<ReceiptViewerScreen> {
  Uint8List? _bytes;
  bool _isPdf = false;
  String? _error;
  bool _loading = true;

  /// PDFの拡大/縮小ボタン用。ホイールはページ送り（スクロール）に使うので、
  /// ズームはボタン・ピンチ・Ctrl+「＋/−」で行う。
  final _pdf = PdfViewerController();

  /// 「ページ全体フィット」を100%とする基準倍率（初期ズーム）。
  double? _fitScale;

  /// 現在の拡大率（フィット基準の%表示に使う）。1.0=フィット時。
  double _zoomRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _pdf.addListener(_onPdfChanged);
    _load();
  }

  @override
  void dispose() {
    _pdf.removeListener(_onPdfChanged);
    super.dispose();
  }

  /// ズーム/スクロール変化のたびに呼ばれる。フィット倍率を基準に現在%を更新。
  void _onPdfChanged() {
    if (!mounted || !_pdf.isReady) return;
    final fit = _fitScale;
    if (fit == null || fit <= 0) return;
    final ratio = _pdf.currentZoom / fit;
    if ((ratio - _zoomRatio).abs() > 0.005) {
      setState(() => _zoomRatio = ratio);
    }
  }

  /// バイト先頭で PDF / 画像 を判定（Driveリンクは拡張子が無いため）。
  bool _looksPdf(Uint8List b) =>
      b.length >= 4 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46; // "%PDF"

  Future<void> _load() async {
    final fileId = DriveReceiptService.fileIdFromUrl(widget.driveUrl);
    if (fileId == null) {
      setState(() {
        _error = 'ファイルIDを取得できませんでした';
        _loading = false;
      });
      return;
    }
    final data = await DriveReceiptService.instance.downloadFile(fileId);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _error = DriveReceiptService.instance.lastError ?? '取得に失敗しました';
        _loading = false;
      });
      return;
    }
    setState(() {
      _bytes = data;
      _isPdf = _looksPdf(data);
      _loading = false;
    });
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.driveUrl.trim());
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title}を見る'),
        actions: [
          // ホイールはページ送りに使うので、ズームはここのボタンで（PDFのみ）。
          if (_isPdf) ...[
            IconButton(
              icon: const Icon(Icons.zoom_out),
              tooltip: '縮小',
              onPressed: () => _pdf.zoomDown(),
            ),
            // 現在の拡大率（ページ全体フィット＝100%基準）。タップでフィットに戻す。
            Center(
              child: InkWell(
                onTap: () {
                  final fit = _fitScale;
                  if (fit != null && _pdf.isReady) {
                    _pdf.setZoom(_pdf.centerPosition, fit);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  constraints: const BoxConstraints(minWidth: 52),
                  alignment: Alignment.center,
                  child: Text(
                    '${(_zoomRatio * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in),
              tooltip: '拡大',
              onPressed: () => _pdf.zoomUp(),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '外部（Drive）で開く',
            onPressed: _openExternal,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF2B2B2B),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              // ドラッグで動かせることが分かるよう、ビューア上は常に「手」カーソルにする。
              : MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: _isPdf
                      ? PdfViewer.data(
                          _bytes!,
                          sourceName: widget.driveUrl,
                          controller: _pdf,
                          params: PdfViewerParams(
                            // 既定はcover(埋める=拡大しすぎ)なので、ページ全体が
                            // 収まるフィット倍率で開く（見やすさ優先）。
                            calculateInitialZoom: (document, controller,
                                alternativeFitScale, coverScale) {
                              // フィット倍率を「100%」の基準として覚えておく。
                              _fitScale = alternativeFitScale;
                              return alternativeFitScale;
                            },
                            // ⚠ ここを null にするとホイールが「ズーム」になり、
                            //   複数ページのPDF（例：GUの注文明細5ページ）を
                            //   ホイールで送れなくなる。ホイール＝スクロールが正。
                            //   ズームはAppBarの拡大/縮小ボタン・ピンチ・Ctrl+「＋/−」で行う。
                            //   既定の0.2は動きが小さいので少し大きめにする。
                            scrollByMouseWheel: 0.5,
                          ),
                        )
                      : InteractiveViewer(
                          maxScale: 5,
                          child: Center(child: Image.memory(_bytes!)),
                        ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Colors.white54),
            const SizedBox(height: 10),
            Text('アプリ内で表示できませんでした\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_new),
              label: const Text('外部（Drive）で開く'),
            ),
          ],
        ),
      );
}
