import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// ダウンロード結果。
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
  /// onProgress: 0.0〜1.0 のダウンロード進捗（受信中に随時呼ばれる）
  Future<File> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final fileName =
        url.split('/').last.split('?').first; // クエリ除去したファイル名
    final filePath = '${dir.path}/$fileName';

    // 既存ファイルがあれば削除（前回のリーク対策）
    final f = File(filePath);
    if (await f.exists()) await f.delete();

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

  /// ダウンロード済の APK を OS のインストーラで開く（半自動インストール）。
  /// ユーザーは表示される確認画面で「インストール」をタップする必要がある。
  Future<bool> installApk(String apkPath) async {
    final result = await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
    return result.type == ResultType.done;
  }
}
