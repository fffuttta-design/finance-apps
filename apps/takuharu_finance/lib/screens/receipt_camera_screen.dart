import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';

/// レシート撮影用の自前カメラ画面（FutaFinance方式）。
/// 中央下=シャッター、右下=ギャラリー（端末の直近写真サムネを表示）。
/// 撮影/選択した画像バイトを Navigator.pop で返す（キャンセルは null）。
class ReceiptCameraScreen extends StatefulWidget {
  const ReceiptCameraScreen({super.key});

  @override
  State<ReceiptCameraScreen> createState() => _ReceiptCameraScreenState();
}

class _ReceiptCameraScreenState extends State<ReceiptCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  Uint8List? _latestThumb; // ギャラリーボタンに出す直近写真サムネ

  @override
  void initState() {
    super.initState();
    _setup();
    _loadLatestThumb();
  }

  Future<void> _setup() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _error = 'カメラが見つかりません');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // 長い納品書(多品目)の小さな文字も潰れないよう高解像度で撮影する。
      final ctrl =
          CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      _controller = ctrl;
      await ctrl.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'カメラを起動できません（権限を確認してください）');
      }
    }
  }

  /// 端末の一番新しい画像のサムネを取得（権限が無ければ何もしない）。
  Future<void> _loadLatestThumb() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) return;
      final albums = await PhotoManager.getAssetPathList(
          type: RequestType.image, onlyAll: true);
      if (albums.isEmpty) return;
      final assets = await albums.first.getAssetListPaged(page: 0, size: 1);
      if (assets.isEmpty) return;
      final thumb = await assets.first
          .thumbnailDataWithSize(const ThumbnailSize(160, 160));
      if (thumb != null && mounted) setState(() => _latestThumb = thumb);
    } catch (_) {
      // 取得失敗時はアイコン表示にフォールバック。
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.pop<Uint8List>(context, bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('撮影に失敗しました: $e')));
      }
    }
  }

  Future<void> _gallery() async {
    if (_busy) return;
    // 長い伝票でも文字が読めるよう、縮小を控えめ(幅2200・画質85)にする。
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) Navigator.pop<Uint8List>(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)),
              ),
            )
          else if (c != null && c.value.isInitialized)
            Positioned.fill(child: CameraPreview(c))
          else
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('レシートを画面に収めて撮影 ♡',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
          ),
          // 下部コントロール（左スペーサー｜中央=シャッター｜右=ギャラリー）。
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 120,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: _shoot,
                          child: Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                  color: AppColors.pink, width: 4),
                            ),
                            child: _busy
                                ? const Padding(
                                    padding: EdgeInsets.all(22),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: AppColors.pink))
                                : null,
                          ),
                        ),
                      ),
                    ),
                    // ギャラリー（直近写真サムネ or アイコン）
                    GestureDetector(
                      onTap: _gallery,
                      child: Container(
                        width: 56,
                        height: 56,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white24,
                          border: Border.all(color: Colors.white70, width: 2),
                        ),
                        child: _latestThumb != null
                            ? Image.memory(_latestThumb!, fit: BoxFit.cover)
                            : const Icon(Icons.photo_library_rounded,
                                color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
