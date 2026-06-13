import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../screens/plan_detail_screen.dart';
import '../screens/transaction_chat_screen.dart';
import 'auth_service.dart';
import 'household_service.dart';
import 'plan_repository.dart';
import 'tx_repository.dart';

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

  /// 前面（アプリ使用中）で通知を表示するためのローカル通知プラグイン。
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// 通知チャンネル（Android）。
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'takuharu_default',
    'たくはるファイナンス',
    description: '記録・コメント・プランのお知らせ',
    importance: Importance.high,
  );

  /// ログイン後に1度呼ぶ。許可取得→トークン保存→更新監視→タップ遷移の設定。
  Future<void> register() async {
    if (_started) return;
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
      _setupTapHandlers();
    } catch (_) {
      // 失敗しても致命的ではない。次回起動で再試行できるよう解除。
      _started = false;
    }
  }

  /// ローカル通知の初期化（チャンネル作成＋タップ時の遷移設定）。
  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          _handleTap(Map<String, dynamic>.from(jsonDecode(payload) as Map));
        } catch (_) {/* ペイロード不正は無視 */}
      },
    );
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
    _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      payload: jsonEncode(m.data),
    );
  }

  /// 通知タップ時の遷移を設定。
  /// - バックグラウンドから復帰: onMessageOpenedApp
  /// - 終了状態から起動: getInitialMessage
  void _setupTapHandlers() {
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));
    _fm.getInitialMessage().then((m) {
      if (m != null) _handleTap(m.data);
    });
  }

  /// 通知データから、対象画面へ遷移する。
  /// - 取引（tx / comment）: その取引のチャット画面。
  /// - プランニング（plan / plan_comment）: その項目の詳細画面。
  Future<void> _handleTap(Map<String, dynamic> data) async {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;

    final planId = data['planId'];
    if (planId is String && planId.isNotEmpty) {
      // 起動直後はデータ未準備のことがあるので軽くリトライ。
      for (var i = 0; i < 3; i++) {
        final p = await PlanRepository.instance.getById(hid, planId);
        final nav = appNavigatorKey.currentState;
        if (p != null && nav != null) {
          nav.push(MaterialPageRoute(builder: (_) => PlanDetailScreen(item: p)));
          return;
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
      return;
    }

    final txId = data['txId'];
    if (txId is! String || txId.isEmpty) return;
    // 起動直後はデータ未準備のことがあるので軽くリトライ。
    for (var i = 0; i < 3; i++) {
      final t = await TxRepository.instance.getById(hid, txId);
      final nav = appNavigatorKey.currentState;
      if (t != null && nav != null) {
        nav.push(MaterialPageRoute(
            builder: (_) => TransactionChatScreen(transaction: t)));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 800));
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
