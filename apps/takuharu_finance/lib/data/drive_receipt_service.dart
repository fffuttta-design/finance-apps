import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// レシート画像を Google Drive に保存するサービス。
///
/// 【方式】共有アカウント takuharumika@gmail.com のドライブに作った
///   「ツール開発 / たくはるファイナンス / レシート」フォルダ（[_receiptFolderId]）を
///   親にして、その下に YYYY年/MM月 を作って画像を入れる。
///   このフォルダは たく・はる 両方のGmailに「編集」権限で共有してあるので、
///   どちらが記録しても同じ場所に集約され、2人＋takuharumika 全員が閲覧できる。
///
/// 【権限】他人(共有アカウント)が作った親フォルダの中へ書き込むため、
///   最小権限 drive.file ではなくフル drive スコープを使う。
///   （初回は「確認されていないアプリ」警告が出るが、2人だけの利用なので続行でOK）
class DriveReceiptService {
  DriveReceiptService._();
  static final DriveReceiptService instance = DriveReceiptService._();

  static const _scope = 'https://www.googleapis.com/auth/drive';

  /// takuharumika の「ツール開発 / たくはるファイナンス / レシート」フォルダID。
  /// ここを親にして年月フォルダを作る。両アカウントに編集共有済み。
  static const _receiptFolderId = '1oKNY3j3wDWAXVzsjqS_AhOCZVsKDFDmD';

  /// セッション中のアクセストークン簡易キャッシュ（Web の再ポップアップ抑制）。
  String? _tokenCache;

  /// 裏で完了したアップロードの結果URL（receiptId → webViewLink）。
  /// 「保存より先にアップロードが完了した」場合に、保存時へURLを渡すために使う。
  final Map<String, String> _resultUrls = {};
  void rememberUrl(String receiptId, String url) =>
      _resultUrls[receiptId] = url;
  String? urlFor(String receiptId) => _resultUrls[receiptId];

  /// Drive のファイルURL/IDからファイルIDを取り出す。
  /// 例: `https://drive.google.com/file/d/{ID}/view?usp=...` から `{ID}` を返す。
  static String? fileIdFromUrl(String urlOrId) {
    final s = urlOrId.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'/d/([A-Za-z0-9_-]+)').firstMatch(s) ??
        RegExp(r'[?&]id=([A-Za-z0-9_-]+)').firstMatch(s);
    if (m != null) return m.group(1);
    // 既にIDっぽい（スラッシュなし）ならそのまま。
    if (!s.contains('/') && !s.contains(' ')) return s;
    return null;
  }

  /// ダウンロード済み画像のメモリキャッシュ（同じレシートの再表示を一瞬に）。
  final Map<String, Uint8List> _imageCache = {};

  /// 自分の権限トークンでDriveから画像バイトを取得（アプリ内表示用）。
  /// ブラウザ/ログイン不要で開ける（共有フォルダにアクセス権がある前提）。
  Future<Uint8List?> downloadFile(String fileId) async {
    lastError = null;
    final cached = _imageCache[fileId];
    if (cached != null) return cached; // 2回目以降は即返す
    try {
      final token = await _accessToken();
      if (token == null) {
        lastError = 'アクセストークンを取得できませんでした';
        return null;
      }
      final uri = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      var res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      // 401(トークン期限切れ)は一度だけ強制リフレッシュして再試行。
      if (res.statusCode == 401) {
        final fresh = await _accessToken(forceRefresh: true);
        if (fresh != null) {
          res = await http.get(uri, headers: {'Authorization': 'Bearer $fresh'});
        }
      }
      if (res.statusCode != 200) {
        lastError = '取得失敗 (${res.statusCode})';
        return null;
      }
      final bytes = res.bodyBytes;
      // 肥大化防止: 直近20件だけ保持。
      if (_imageCache.length >= 20) {
        _imageCache.remove(_imageCache.keys.first);
      }
      _imageCache[fileId] = bytes;
      return bytes;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// 直近の失敗理由（UI 表示・原因切り分け用）。成功時は null。
  String? lastError;

  /// フォルダIDのメモリキャッシュ。key: "親ID|フォルダ名" → フォルダID。
  final Map<String, String> _folderCache = {};

  /// 月フォルダIDのキャッシュ。key: "YYYY-MM" → 月フォルダID。
  final Map<String, String> _monthPathCache = {};

  /// レシート画像をアップロードして閲覧リンクを返す。失敗時は null（lastError に理由）。
  Future<String?> uploadReceiptImage({
    required Uint8List bytes,
    required DateTime date,
    String? store,
    int? amount,
  }) async {
    lastError = null;
    try {
      final token = await _accessToken();
      if (token == null) {
        lastError = 'アクセストークンを取得できませんでした';
        return null;
      }
      final monthId = await _ensureMonthFolder(token, date);
      final name = _fileName(date, store, amount);
      return await _uploadMultipart(token, name, monthId, bytes);
    } catch (e) {
      lastError = e.toString();
      if (kDebugMode) debugPrint('Drive upload error: $e');
      return null;
    }
  }

  String _fileName(DateTime d, String? store, int? amount) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ymd = '${d.year}-${two(d.month)}-${two(d.day)}';
    final cleanStore = (store == null || store.trim().isEmpty)
        ? ''
        : '_${store.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '')}';
    final amt = amount == null ? '' : '_${amount}_yen';
    final uniq = DateTime.now().microsecondsSinceEpoch.toString();
    return '$ymd$cleanStore${amt}_$uniq.jpg';
  }

  // ── アクセストークン取得（Web / Android で経路が異なる）─────────
  /// [forceRefresh] true で、期限切れトークンを捨てて新しく取り直す（401対策）。
  Future<String?> _accessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _tokenCache != null) return _tokenCache;
    if (forceRefresh) _tokenCache = null;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope(_scope);
      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      final oauth = cred.credential;
      _tokenCache = oauth is OAuthCredential ? oauth.accessToken : null;
      return _tokenCache;
    } else {
      final client = GoogleSignIn.instance.authorizationClient;
      // 強制リフレッシュ時はキャッシュ済み(=期限切れの可能性)を使わず取り直す。
      var authz =
          forceRefresh ? null : await client.authorizationForScopes([_scope]);
      authz ??= await client.authorizeScopes([_scope]);
      _tokenCache = authz.accessToken;
      return _tokenCache;
    }
  }

  // ── 共有フォルダ配下に年月フォルダを用意して月フォルダIDを返す ──────
  Future<String> _ensureMonthFolder(String token, DateTime d) async {
    final mk = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final cached = _monthPathCache[mk];
    if (cached != null) return cached;
    final yearId =
        await _findOrCreateFolder(token, '${d.year}年', _receiptFolderId);
    final monthId = await _findOrCreateFolder(
        token, '${d.month.toString().padLeft(2, '0')}月', yearId);
    _monthPathCache[mk] = monthId;
    return monthId;
  }

  Future<String> _findOrCreateFolder(
      String token, String name, String parentId) async {
    final ck = '$parentId|$name';
    final hit = _folderCache[ck];
    if (hit != null) return hit;
    final found = await _findFolder(token, name, parentId);
    final id = found ?? await _createFolder(token, name, parentId);
    _folderCache[ck] = id;
    return id;
  }

  Future<String?> _findFolder(
      String token, String name, String parentId) async {
    final esc = name.replaceAll("'", r"\'");
    final q =
        "name='$esc' and mimeType='application/vnd.google-apps.folder' and '$parentId' in parents and trashed=false";
    final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=${Uri.encodeQueryComponent(q)}&fields=files(id)&spaces=drive');
    final res =
        await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode != 200) return null;
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    return files.first['id'] as String?;
  }

  Future<String> _createFolder(
      String token, String name, String parentId) async {
    final res = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentId],
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw 'フォルダ作成失敗 (${res.statusCode}) ${_short(res.body)}';
    }
    return jsonDecode(res.body)['id'] as String;
  }

  String _short(String s) => s.length > 300 ? s.substring(0, 300) : s;

  Future<String?> _uploadMultipart(
      String token, String name, String parentId, Uint8List bytes) async {
    const boundary = 'takuharu_receipt_boundary_8c3f';
    final meta = jsonEncode({
      'name': name,
      'parents': [parentId],
    });
    final body = <int>[];
    void add(String s) => body.addAll(utf8.encode(s));
    add('--$boundary\r\n');
    add('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    add('$meta\r\n');
    add('--$boundary\r\n');
    add('Content-Type: image/jpeg\r\n\r\n');
    body.addAll(bytes);
    add('\r\n--$boundary--');
    final res = await http.post(
      Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('Drive upload failed: ${res.statusCode} ${res.body}');
      }
      throw 'アップロード失敗 (${res.statusCode}) ${_short(res.body)}';
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (j['webViewLink'] as String?) ??
        'https://drive.google.com/file/d/${j['id']}/view';
  }
}
