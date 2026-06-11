/// Windows デスクトップ版の Google OAuth クライアント設定。
///
/// client_id は公開情報なので既定値に直書きしてよい。
/// client_secret は **ビルド時に --dart-define で注入**する（gemini.key と同様）。
///   - 秘密は `apps/futa_finance/win_oauth.key`（gitignore）に保存
///   - `deploy_windows.ps1` がそれを読んで
///     `--dart-define=WIN_OAUTH_CLIENT_SECRET=...` を付けてビルドする
///
/// Web/Android ビルドでは secret を注入しない＝空文字＝[configured] が false。
/// （Web/Android は WindowsGoogleAuth を使わないので問題なし。CI もこれで通る）
class WindowsOAuthConfig {
  WindowsOAuthConfig._();

  /// デスクトップアプリの client_id（公開情報）。
  static const String clientId = String.fromEnvironment(
    'WIN_OAUTH_CLIENT_ID',
    defaultValue:
        '746983928581-1pg8giqolvjim3v4gogqaf5jh0f0pncf.apps.googleusercontent.com',
  );

  /// client_secret（ビルド時注入・既定は空）。
  static const String clientSecret =
      String.fromEnvironment('WIN_OAUTH_CLIENT_SECRET');

  /// secret が注入されていれば有効。
  static bool get configured => clientSecret.isNotEmpty;
}
