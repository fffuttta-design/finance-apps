import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// 認証サービス。
/// Google Sign-In + Firebase Auth を統合し、ログイン状態を提供する。
///
/// 使い方:
/// ```dart
/// await AuthService.instance.init();
/// AuthService.instance.userStream.listen((user) { ... });
/// await AuthService.instance.signInWithGoogle();
/// await AuthService.instance.signOut();
/// ```
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _initialized = false;

  /// 起動時に1回だけ呼ぶ。google_sign_in の初期化。
  Future<void> init() async {
    if (_initialized) return;
    // google_sign_in 7.x は初期化APIあり。Web 含め共通。
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  /// 現在ログイン中のユーザー（未ログインなら null）。
  User? get currentUser => _auth.currentUser;

  /// ログイン状態のストリーム（リアルタイム）。
  Stream<User?> get userStream => _auth.authStateChanges();

  /// Google でサインイン。
  ///
  /// 成功時: FirebaseAuth.User が返る、authStateChanges() に通知。
  /// 失敗時: 例外を投げる（呼び出し側でキャッチして UI 表示）。
  Future<User?> signInWithGoogle() async {
    if (!_initialized) await init();

    try {
      // Google アカウント選択（ネイティブダイアログ起動）。
      final account = await GoogleSignIn.instance.authenticate();

      // idToken を取得
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw Exception('Google idToken が取得できませんでした');
      }

      // Firebase Auth に渡す
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await _auth.signInWithCredential(credential);
      return userCred.user;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Google サインインエラー: $e');
      }
      rethrow;
    }
  }

  /// サインアウト。
  Future<void> signOut() async {
    try {
      // Firebase 側
      await _auth.signOut();
      // Google 側（次回サインイン時にアカウント選択を再表示するため）
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) {
        debugPrint('サインアウトエラー: $e');
      }
      rethrow;
    }
  }
}
