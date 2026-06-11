import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/windows_oauth_config.dart';

/// 1回の OAuth で取得したトークン群。
class WindowsGoogleTokens {
  WindowsGoogleTokens({
    required this.idToken,
    required this.accessToken,
    required this.refreshToken,
  });

  final String idToken;
  final String accessToken;
  final String? refreshToken;
}

/// Windows デスクトップ版の Google ログイン。
///
/// google_sign_in が Windows 非対応のため、OAuth 2.0 の
/// 「ループバック（ローカルIP）方式 + PKCE」を自前で実装する。
/// 取得した id_token は Firebase Auth の signInWithCredential に、
/// access_token は Google Drive API（drive.file）にそのまま使える。
///
/// スコープに drive.file を含めるので、ログイン＝Drive 連携も同時に許可される。
class WindowsGoogleAuth {
  WindowsGoogleAuth._();
  static final WindowsGoogleAuth instance = WindowsGoogleAuth._();

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const List<String> _scopes = [
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const _kRefreshToken = 'futa.win.google.refresh_token';

  // メモリ上のアクセストークンキャッシュ。
  String? _accessTokenCache;
  DateTime? _accessTokenExpiry;

  bool get isConfigured => WindowsOAuthConfig.configured;

  /// ブラウザを開いて Google ログインを行い、トークン群を返す。
  /// 失敗時は例外を投げる。
  Future<WindowsGoogleTokens> signIn() async {
    if (!isConfigured) {
      throw Exception(
          'Windows 用の Google OAuth クライアントが未設定です（管理者に連絡）。');
    }

    // PKCE
    final verifier = _randomString(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomString(24);

    // ループバックサーバ起動（空きポート自動割当）
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    final port = server.port;
    final redirectUri = 'http://127.0.0.1:$port';

    final authUri = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': WindowsOAuthConfig.clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes.join(' '),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent select_account',
    });

    if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw Exception('ブラウザを開けませんでした');
    }

    // リダイレクトを待ち受け（最大5分）
    String? code;
    String? error;
    try {
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final params = req.uri.queryParameters;
        if (params['state'] != state) {
          // 想定外リクエストは無視して待機継続
          req.response
            ..statusCode = 400
            ..write('invalid state');
          await req.response.close();
          continue;
        }
        code = params['code'];
        error = params['error'];
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_doneHtml(error));
        await req.response.close();
        break;
      }
    } on TimeoutException {
      throw Exception('ログインがタイムアウトしました');
    } finally {
      await server.close(force: true);
    }

    if (error != null) {
      throw Exception('Google ログインが拒否されました: $error');
    }
    if (code == null) {
      throw Exception('認可コードを取得できませんでした');
    }

    // 認可コード → トークン交換
    final res = await http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'code': code,
        'client_id': WindowsOAuthConfig.clientId,
        'client_secret': WindowsOAuthConfig.clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      },
    );
    if (res.statusCode != 200) {
      throw Exception('トークン取得失敗: ${res.statusCode} ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final idToken = j['id_token'] as String?;
    final accessToken = j['access_token'] as String?;
    final refreshToken = j['refresh_token'] as String?;
    if (idToken == null || accessToken == null) {
      throw Exception('id_token / access_token が空でした');
    }

    // 保存・キャッシュ
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _cacheAccessToken(accessToken, expiresIn);
    if (refreshToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRefreshToken, refreshToken);
    }

    return WindowsGoogleTokens(
      idToken: idToken,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  /// Drive 等で使うアクセストークン。期限内ならキャッシュ、切れていれば
  /// refresh_token で更新する。refresh_token が無ければ null。
  Future<String?> accessToken({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _accessTokenCache != null &&
        _accessTokenExpiry != null &&
        DateTime.now()
            .isBefore(_accessTokenExpiry!.subtract(const Duration(minutes: 1)))) {
      return _accessTokenCache;
    }
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kRefreshToken);
    if (refresh == null) return null;

    final res = await http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'client_id': WindowsOAuthConfig.clientId,
        'client_secret': WindowsOAuthConfig.clientSecret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      },
    );
    if (res.statusCode != 200) {
      if (kDebugMode) debugPrint('トークン更新失敗: ${res.statusCode} ${res.body}');
      return null;
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final accessToken = j['access_token'] as String?;
    if (accessToken == null) return null;
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _cacheAccessToken(accessToken, expiresIn);
    return accessToken;
  }

  /// サインアウト。保存した refresh_token を破棄。
  Future<void> signOut() async {
    _accessTokenCache = null;
    _accessTokenExpiry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRefreshToken);
  }

  void _cacheAccessToken(String token, int expiresInSeconds) {
    _accessTokenCache = token;
    _accessTokenExpiry =
        DateTime.now().add(Duration(seconds: expiresInSeconds));
  }

  String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  String _doneHtml(String? error) {
    final ok = error == null;
    final title = ok ? 'ログイン完了' : 'ログインに失敗しました';
    final msg = ok
        ? 'このタブを閉じて、FutaFinance に戻ってください。'
        : 'アプリに戻ってもう一度お試しください。（$error）';
    return '''
<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  body{font-family:'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;
       display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
  .card{background:#1e293b;padding:40px 48px;border-radius:16px;text-align:center;
        box-shadow:0 10px 40px rgba(0,0,0,.4)}
  h1{font-size:20px;margin:0 0 12px}
  p{font-size:14px;color:#94a3b8;margin:0}
  .mark{font-size:48px;margin-bottom:8px}
</style></head>
<body><div class="card">
  <div class="mark">${ok ? '✅' : '⚠️'}</div>
  <h1>$title</h1><p>$msg</p>
</div></body></html>
''';
  }
}
