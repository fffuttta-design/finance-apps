import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'auth_service.dart';

/// プッシュ通知（FCM）の登録。
///
/// - 通知許可をリクエストし、端末トークンを users/{uid}.fcmTokens に保存。
/// - 相手が記録/コメントすると Cloud Functions から通知が届く。
/// - 通知の「表示」はバックグラウンド/終了時はOSが自動で行う（notificationペイロード）。
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _fm = FirebaseMessaging.instance;
  bool _started = false;

  /// ログイン後に1度呼ぶ。許可取得→トークン保存→更新監視。
  Future<void> register() async {
    if (_started) return;
    _started = true;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      final token = await _fm.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(token);
      }
      _fm.onTokenRefresh.listen(_saveToken);
    } catch (_) {
      // 失敗しても致命的ではない。次回起動で再試行できるよう解除。
      _started = false;
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmTokens': FieldValue.arrayUnion([token])},
        SetOptions(merge: true),
      );
    } catch (_) {
      // 保存失敗は無視（オフライン等）。
    }
  }
}
