import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/receipt_detail_screen.dart';
import 'household_service.dart';
import 'tx_repository.dart';

/// 明細共有リンクを受け取って、対象のレシート明細画面を開く。
///
/// - Android: `takuharu://receipt/{receiptId}`（Discordに貼るhttps中継ページ
///   `open.html` が intent 経由でこのスキームを起動する）。
/// - Web: 現在URLの `?r={receiptId}`（中継ページの未インストール時フォールバック先）。
///
/// 画面遷移は通知タップ（[PushService]）と同じ「receiptId → 品目取得 →
/// [ReceiptDetailScreen]」の作りを踏襲する。ログイン・世帯確保が済んだ
/// [MainShell] 表示後に [init] を1度だけ呼ぶ。
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  bool _started = false;
  String? _lastId;
  DateTime? _lastAt;

  Future<void> init() async {
    if (_started) return;
    _started = true;

    if (kIsWeb) {
      // Web版: このURLの ?r= を見て、その明細を開く。
      final rid = Uri.base.queryParameters['r'];
      if (rid != null && rid.isNotEmpty) {
        await _openReceipt(rid);
      }
      return;
    }

    try {
      final links = AppLinks();
      // 終了状態から共有リンクで起動されたとき。
      final initial = await links.getInitialLink();
      if (initial != null) {
        final rid = _receiptIdFromUri(initial);
        if (rid != null) await _openReceipt(rid);
      }
      // アプリを開いている間に受け取ったリンク。
      links.uriLinkStream.listen((uri) {
        final rid = _receiptIdFromUri(uri);
        if (rid != null) _openReceipt(rid);
      });
    } catch (_) {
      // 失敗しても致命的ではない（共有リンクが開けないだけ）。
    }
  }

  /// `takuharu://receipt/{id}` / `.../?r={id}` / `.../receipt/{id}` から receiptId を抽出。
  String? _receiptIdFromUri(Uri uri) {
    final q = uri.queryParameters['r'];
    if (q != null && q.isNotEmpty) return q;
    if (uri.host == 'receipt' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    final segs = uri.pathSegments;
    final i = segs.indexOf('receipt');
    if (i >= 0 && i + 1 < segs.length) return segs[i + 1];
    return null;
  }

  Future<void> _openReceipt(String receiptId) async {
    // 起動直後の初期リンクとストリームが同じIDを続けて出しても二重表示しない。
    final now = DateTime.now();
    if (_lastId == receiptId &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastId = receiptId;
    _lastAt = now;

    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    // 起動直後はデータ未準備のことがあるので軽くリトライ（push_service と同じ作り）。
    for (var i = 0; i < 6; i++) {
      final members =
          await TxRepository.instance.listByReceiptId(hid, receiptId);
      final nav = appNavigatorKey.currentState;
      if (members.isNotEmpty && nav != null) {
        nav.push(MaterialPageRoute(
            builder: (_) => ReceiptDetailScreen(members: members)));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }
}
