import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

/// 通知の受け取り設定（各自が users/{uid}.notifyPrefs に保存）。
///
/// 各自が「自分が受け取りたい通知の種類」を ON/OFF する。
/// VPS の通知サービス（takuharu-notifier）が送信時に相手のこの設定を見て、
/// OFF の種類はその人にだけ送らない（相手の設定は相手のもの）。
/// 既定はすべて ON（未設定キーは true 扱い）。
class NotifyPrefsService {
  NotifyPrefsService._();
  static final NotifyPrefsService instance = NotifyPrefsService._();

  final _db = FirebaseFirestore.instance;

  /// 通知の種類（キー）と表示ラベル。notifier.py の pref_key と一致させること。
  static const categories = <({String key, String label, String desc})>[
    (key: 'tx', label: '記録（追加・修正）', desc: '相手が支出/収入を記録・修正したとき'),
    (key: 'tx_deleted', label: '記録の削除', desc: '相手が記録を削除したとき'),
    (key: 'comment', label: '記録へのコメント', desc: '記録のチャットに返信が来たとき'),
    (key: 'plan', label: 'プラン（追加・編集・完了）', desc: 'やりたいこと等の追加・更新・完了'),
    (key: 'plan_deleted', label: 'プランの削除', desc: 'プラン項目が削除されたとき'),
    (key: 'plan_comment', label: 'プランへのコメント', desc: 'プランのチャットに返信が来たとき'),
    (key: 'subscription', label: '固定費の追加・変更', desc: '固定費・サブスクの追加や金額変更'),
  ];

  Map<String, bool> _prefs = {};

  /// 起動後・設定画面表示時に呼ぶ。自分の設定を読み込む。
  Future<void> load() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final d = await _db.collection('users').doc(uid).get();
      final m = (d.data()?['notifyPrefs'] as Map?) ?? const {};
      _prefs = {
        for (final e in m.entries) '${e.key}': (e.value as bool? ?? true),
      };
    } catch (_) {/* 読めなくても既定ON扱い */}
  }

  /// 指定の種類が ON か（未設定は ON）。
  bool isOn(String key) => _prefs[key] ?? true;

  /// 指定の種類の ON/OFF を保存する。
  Future<void> set(String key, bool value) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    _prefs[key] = value;
    await _db.collection('users').doc(uid).set({
      'notifyPrefs': {key: value},
    }, SetOptions(merge: true));
  }
}
