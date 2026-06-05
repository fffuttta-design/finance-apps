import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// インストール許可の状態。
enum InstallPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
}

/// APK のダウンロードとインストール起動を担当するシングルトン。
class UpdateInstaller {
  UpdateInstaller._();
  static final UpdateInstaller instance = UpdateInstaller._();

  final _dio = Dio();

  /// REQUEST_INSTALL_PACKAGES 権限をチェック。なければリクエスト。
  Future<InstallPermissionStatus> ensureInstallPermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return InstallPermissionStatus.granted;

    final result = await Permission.requestInstallPackages.request();
    if (result.isGranted) return InstallPermissionStatus.granted;
    if (result.isPermanentlyDenied) {
      return InstallPermissionStatus.permanentlyDenied;
    }
    return InstallPermissionStatus.denied;
  }

  /// システム設定の「不明なソースからのインストール」画面を開く。
  Future<void> openInstallSettings() async {
    await openAppSettings();
  }

  /// APK を端末のキャッシュディレクトリにダウンロードしてファイルパスを返す。
  Future<File> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final filePath = await _localApkPath(url);
    final f = File(filePath);

    if (await f.exists()) {
      final len = await f.length();
      if (len > 1024 * 1024) {
        onProgress?.call(1.0);
        return f;
      }
      await f.delete();
    }

    await _dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 10),
      ),
    );

    return File(filePath);
  }

  /// 与えられた URL に対応する DL 済み APK が一時ディレクトリにあれば返す。
  Future<File?> getCachedApk(String url) async {
    final filePath = await _localApkPath(url);
    final f = File(filePath);
    if (!await f.exists()) return null;
    final len = await f.length();
    if (len <= 1024 * 1024) return null;
    return f;
  }

  Future<String> _localApkPath(String url) async {
    final dir = await getTemporaryDirectory();
    final fileName = url.split('/').last.split('?').first;
    return '${dir.path}/$fileName';
  }

  /// ダウンロード済の APK を OS のインストーラで開く（半自動インストール）。
  Future<bool> installApk(String apkPath) async {
    final result = await OpenFilex.open(apkPath,
        type: 'application/vnd.android.package-archive');
    return result.type == ResultType.done;
  }
}
