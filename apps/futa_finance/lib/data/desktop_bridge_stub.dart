/// 非Web（Android/iOS/Windowsネイティブ）向けスタブ。
/// Electron ブリッジは存在しないので常に無効。
class DesktopTokens {
  const DesktopTokens(this.idToken, this.accessToken);
  final String idToken;
  final String accessToken;
}

/// Electron デスクトップ版で動いているか。非Webでは常に false。
bool get isDesktopShell => false;

Future<DesktopTokens> desktopSignIn() =>
    throw UnsupportedError('desktop bridge is web-only');

Future<DesktopTokens?> desktopSilentTokens() async => null;

Future<String?> desktopDriveToken({bool forceRefresh = false}) async => null;

Future<void> desktopSignOut() async {}
