import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 現在版とリモート version.json の比較結果。
class UpdateCheckResult {
  final String currentVersion;
  final String currentBuildNumber;
  final String? latestVersion;
  final String? latestBuildNumber;
  final String? downloadUrl;
  final String? releaseNotes;
  final bool hasUpdate;
  final bool fetchFailed;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.currentBuildNumber,
    this.latestVersion,
    this.latestBuildNumber,
    this.downloadUrl,
    this.releaseNotes,
    required this.hasUpdate,
    this.fetchFailed = false,
  });

  String get currentFull => '$currentVersion+$currentBuildNumber';
  String get latestFull => latestVersion == null
      ? '取得失敗'
      : '$latestVersion${latestBuildNumber != null ? "+$latestBuildNumber" : ""}';
}

/// アプリのバージョン自動チェック。
///
/// リモートの version.json（例: Firebase Hosting にデプロイ）を fetch し、
/// 現在版より新しい場合は updateAvailable=true を返す。
///
/// version.json のフォーマット例:
/// ```json
/// {
///   "version": "1.0.12",
///   "buildNumber": "13",
///   "downloadUrl": "https://.../app-debug.apk",
///   "releaseNotes": "○○を改善"
/// }
/// ```
class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  /// リモート version.json のURL。
  /// Firebase Hosting にデプロイした想定。プロジェクトに合わせて差し替え。
  static const String versionUrl =
      'https://futa-finance.web.app/version.json';

  Future<({String version, String buildNumber})> getCurrent() async {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, buildNumber: info.buildNumber);
  }

  Future<UpdateCheckResult> check() async {
    final current = await getCurrent();
    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          currentVersion: current.version,
          currentBuildNumber: current.buildNumber,
          hasUpdate: false,
          fetchFailed: true,
        );
      }
      final j = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = j['version'] as String?;
      final latestBuildNumber = j['buildNumber']?.toString();
      if (latestVersion == null) {
        return UpdateCheckResult(
          currentVersion: current.version,
          currentBuildNumber: current.buildNumber,
          hasUpdate: false,
          fetchFailed: true,
        );
      }
      final hasUpdate = _isNewer(
        latestVersion: latestVersion,
        latestBuild: latestBuildNumber,
        currentVersion: current.version,
        currentBuild: current.buildNumber,
      );
      return UpdateCheckResult(
        currentVersion: current.version,
        currentBuildNumber: current.buildNumber,
        latestVersion: latestVersion,
        latestBuildNumber: latestBuildNumber,
        downloadUrl: j['downloadUrl'] as String?,
        releaseNotes: j['releaseNotes'] as String?,
        hasUpdate: hasUpdate,
      );
    } catch (_) {
      return UpdateCheckResult(
        currentVersion: current.version,
        currentBuildNumber: current.buildNumber,
        hasUpdate: false,
        fetchFailed: true,
      );
    }
  }

  /// セマンティックバージョン比較（major.minor.patch）+ build number。
  bool _isNewer({
    required String latestVersion,
    required String? latestBuild,
    required String currentVersion,
    required String? currentBuild,
  }) {
    final l = _parseVersion(latestVersion);
    final c = _parseVersion(currentVersion);
    for (int i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    // major.minor.patch が同じならビルド番号で比較
    final lb = int.tryParse(latestBuild ?? '0') ?? 0;
    final cb = int.tryParse(currentBuild ?? '0') ?? 0;
    return lb > cb;
  }

  List<int> _parseVersion(String v) {
    final parts = v.split('+').first.split('.');
    final list = <int>[];
    for (int i = 0; i < 3; i++) {
      list.add(i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
    }
    return list;
  }
}
