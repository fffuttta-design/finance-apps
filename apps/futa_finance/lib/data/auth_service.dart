import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'windows_google_auth.dart';

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

  /// Windows デスクトップ判定（google_sign_in 非対応プラットフォーム）。
  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 起動時に1回だけ呼ぶ。google_sign_in の初期化。
  /// Web / Windows では google_sign_in を使わないため初期化スキップ。
  ///   - Web: Firebase Auth の signInWithPopup を直接利用
  ///   - Windows: 自前の OAuth ループバック方式（WindowsGoogleAuth）
  Future<void> init() async {
    if (_initialized) return;
    if (!kIsWeb && !_isWindows) {
      await GoogleSignIn.instance.initialize();
    }
    _initialized = true;
  }

  /// 現在ログイン中のユーザー（未ログインなら null）。
  User? get currentUser => _auth.currentUser;

  /// 起動時の自動ログイン。
  /// Windows は FlutterFire のセッション永続が不安定なため、保存済みの
  /// refresh_token から黙って再ログインする（ブラウザを開かない）。
  /// 既にログイン済み、または Web/Android（セッションが永続する）なら何もしない。
  /// 戻り値=ログイン状態になったか。
  Future<bool> trySilentSignIn() async {
    if (_auth.currentUser != null) return true;
    if (!_isWindows) return false;
    try {
      final tokens = await WindowsGoogleAuth.instance.silentSignIn();
      if (tokens == null) return false;
      final credential = GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      return userCred.user != null;
    } catch (e) {
      if (kDebugMode) debugPrint('自動ログイン失敗: $e');
      return false;
    }
  }

  /// ログイン状態のストリーム（リアルタイム）。
  Stream<User?> get userStream => _auth.authStateChanges();

  /// Google でサインイン。
  ///
  /// 成功時: FirebaseAuth.User が返る、authStateChanges() に通知。
  /// 失敗時: 例外を投げる（呼び出し側でキャッチして UI 表示）。
  Future<User?> signInWithGoogle() async {
    if (!_initialized) await init();

    try {
      if (kIsWeb) {
        // Web: Firebase Auth の signInWithPopup を直接利用。
        // google_sign_in の Web 用 client_id 設定が不要になる。
        final provider = GoogleAuthProvider();
        final userCred = await _auth.signInWithPopup(provider);
        return userCred.user;
      }

      if (_isWindows) {
        // Windows: 自前 OAuth でブラウザログイン → id_token を Firebase に渡す。
        final tokens = await WindowsGoogleAuth.instance.signIn();
        final credential = GoogleAuthProvider.credential(
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
        );
        final userCred = await _auth.signInWithCredential(credential);
        return userCred.user;
      }

      // Android/iOS: google_sign_in 経由でネイティブのアカウント選択を起動。
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
      if (_isWindows) {
        await WindowsGoogleAuth.instance.signOut();
      } else if (!kIsWeb) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('サインアウトエラー: $e');
      }
      rethrow;
    }
  }
}
