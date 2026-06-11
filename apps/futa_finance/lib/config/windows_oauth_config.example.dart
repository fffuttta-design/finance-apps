/// Windows デスクトップ版 OAuth 設定の雛形。
///
/// 実ファイル `windows_oauth_config.dart` は client_secret を含むため
/// .gitignore 済み（コミットしない）。新しい環境では本ファイルをコピーして
/// `windows_oauth_config.dart` を作り、Google Cloud Console の
/// 「デスクトップ アプリ」OAuth クライアントの値を記入する。
///
///   cp windows_oauth_config.example.dart windows_oauth_config.dart
class WindowsOAuthConfig {
  WindowsOAuthConfig._();

  /// 例: '746983928581-xxxxxxxx.apps.googleusercontent.com'
  static const String clientId =
      'PASTE_DESKTOP_CLIENT_ID_HERE.apps.googleusercontent.com';

  /// 例: 'GOCSPX-xxxxxxxxxxxx'
  static const String clientSecret = 'PASTE_DESKTOP_CLIENT_SECRET_HERE';

  /// client_id / client_secret を記入したら true にする。
  static const bool configured = false;
}
