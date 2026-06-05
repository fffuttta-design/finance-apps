import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// 認証サービス。Google Sign-In + Firebase Auth。
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _initialized = false;

  /// Web OAuth クライアントID（google-services.json の client_type=3）。
  /// Android で Firebase 用の idToken を得るために serverClientId として渡す。
  static const String _webClientId =
      '806764261873-abarnv8pa0iljdpimo9v8irikvugis2d.apps.googleusercontent.com';

  Future<void> init() async {
    if (_initialized) return;
    if (!kIsWeb) {
      // serverClientId を渡さないと、authenticate() の idToken の audience が
      // Android クライアントになり Firebase が受け付けない（Androidログイン失敗）。
      await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    }
    _initialized = true;
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get userStream => _auth.authStateChanges();

  Future<User?> signInWithGoogle() async {
    if (!_initialized) await init();
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          // 毎回アカウント選択画面を出す（ブラウザに1アカウントだけだと
          // 即サインインしてしまい、別アカウントを選べない問題を回避）。
          ..setCustomParameters({'prompt': 'select_account'});
        final cred = await _auth.signInWithPopup(provider);
        return cred.user;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google idToken が取得できませんでした');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final cred = await _auth.signInWithCredential(credential);
      return cred.user;
    } catch (e) {
      if (kDebugMode) debugPrint('サインインエラー: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }
}
