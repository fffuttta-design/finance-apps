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

  /// Driveから画像バイトを取得（アプリ内表示用）。
  /// ① まず「リンク公開」前提のトークン不要URLで取得を試みる（相手の権限に依存せず最強）。
  /// ② ダメなら従来どおり自分の権限トークンで取得（401は1回リフレッシュ）。
  Future<Uint8List?> downloadFile(String fileId) async {
    lastError = null;
    final cached = _imageCache[fileId];
    if (cached != null) return cached; // 2回目以降は即返す

    // ① トークン不要の公開URL（保存時に anyone-reader を付与済みなら成功）。
    final pub = await _tryPublicDownload(fileId);
    if (pub != null) {
      _cachePut(fileId, pub);
      return pub;
    }

    // ② フォールバック: 自分のトークンで取得。
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
      _cachePut(fileId, bytes);
      return bytes;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// 「リンクを知っている人は閲覧可」のファイルを、トークン無しで取得する。
  /// 公開されていない/画像でない応答（ログイン要求HTML等）のときは null を返す。
  Future<Uint8List?> _tryPublicDownload(String fileId) async {
    try {
      final uri = Uri.parse(
          'https://drive.google.com/uc?export=download&id=$fileId');
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      // 画像が返れば成功。HTML（サインイン要求/確認ページ）は非公開とみなし失敗扱い。
      if (ct.startsWith('image/')) return res.bodyBytes;
      if (!ct.contains('text/html') && res.bodyBytes.length > 512) {
        return res.bodyBytes;
      }
    } catch (_) {/* 公開取得に失敗 → トークン経路へ */}
    return null;
  }

  /// 画像キャッシュへ格納（肥大化防止に直近20件だけ保持）。
  void _cachePut(String fileId, Uint8List bytes) {
    if (_imageCache.length >= 20) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[fileId] = bytes;
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
    final id = j['id'] as String?;
    // ★ 保存直後に「リンクを知っている人は閲覧可」権限を付与。
    //   これで相手のドライブ権限/フォルダ共有の効き具合に依存せず、
    //   必ず相手も画像を開ける（トークン無しの公開URLで読める）。
    if (id != null) {
      await _makeAnyoneReader(token, id);
    }
    return (j['webViewLink'] as String?) ??
        'https://drive.google.com/file/d/$id/view';
  }

  /// ファイルに「リンクを知っている人は閲覧可（reader）」を付与する。
  /// 失敗しても致命ではない（従来どおりフォルダ共有＋自分のトークンで開ける）。
  Future<void> _makeAnyoneReader(String token, String fileId) async {
    try {
      await http.post(
        Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId/permissions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'role': 'reader', 'type': 'anyone'}),
      );
    } catch (_) {/* 権限付与失敗は無視 */}
  }
}
