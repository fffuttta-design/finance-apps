import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'auth_service.dart';

/// プッシュ通知（FCM）の登録。
///
/// 二村秘書（FutaHishoボット）がFutaFinanceに新規記帳すると、サーバ（VPS）から
/// 「二村秘書が登録しました」というプッシュが届く。
/// - 通知許可をリクエストし、端末トークンを users/{uid}.fcmTokens に保存する。
/// - サーバは notification ペイロード付きで送るので、アプリが閉じている/裏のときは
///   OS が自動で通知を表示する（Dart側の受信処理は不要）。
/// - 前面（アプリ使用中）のときだけ、自前でバナーを表示する。
///
/// 🔑 対象は Android のみ。Web push（要 service worker + VAPID）とデスクトップ
///    （Electron内のWebビルド＝FCM web push が不安定）は対象外なので早期 return する。
///    → たくはるファイナンスの push_service.dart を移植（家計簿の世帯/プラン遷移は削除）。
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _fm = FirebaseMessaging.instance;
  bool _started = false;

  /// 前面（アプリ使用中）で通知を表示するためのローカル通知プラグイン。
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Android の通知チャンネル。
  /// 🔥 id はサーバの AndroidNotification.channel_id と一致させること
  ///    （futafinance.py の "futa_finance_default"）。ズレると背景通知がこの
  ///    チャンネル設定（重要度high）で出ない。
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'futa_finance_default',
    'ふたファイナンス',
    description: '二村秘書の記帳などのお知らせ',
    importance: Importance.high,
  );

  /// ログイン後に1度呼ぶ。許可取得→トークン保存→更新監視→前面表示の設定。
  Future<void> register() async {
    if (_started) return;
    // Android 専用（Web / デスクトップは対象外）。
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      await _initLocalNotifications();
      final token = await _fm.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(token);
      }
      _fm.onTokenRefresh.listen(_saveToken);
      // 前面で受信したメッセージは OS が自動表示しないので、自前で表示する。
      FirebaseMessaging.onMessage.listen(_showForeground);
    } catch (_) {
      // 失敗しても致命的ではない。次回起動で再試行できるよう解除。
      _started = false;
    }
  }

  /// ローカル通知の初期化（チャンネル作成＋許可）。
  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _local.initialize(settings: initSettings);
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();
  }

  /// アプリを開いている（前面）ときに、受信メッセージをバナー表示する。
  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    final title = n?.title ?? (m.data['title']?.toString() ?? '');
    final body = n?.body ?? (m.data['body']?.toString() ?? '');
    if (title.isEmpty && body.isEmpty) return;
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _local.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> _saveToken(String token) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 保存失敗は無視（オフライン等）。次回起動で再試行される。
    }
  }
}
