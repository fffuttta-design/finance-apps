import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// レシート画像を Google Drive に保存するサービス（最小権限 drive.file）。
///
/// フォルダ構成: [ルート]/(事業用|個人用)/YYYY年/MM月/ にアップロードし、
/// 閲覧リンク(webViewLink)を返す。
/// ルートフォルダIDは prefs に保存し、ユーザーがフォルダを別の場所へ
/// 移動しても ID で追従する（option B）。
class DriveReceiptService {
  DriveReceiptService._();
  static final DriveReceiptService instance = DriveReceiptService._();

  static const _scope = 'https://www.googleapis.com/auth/drive.file';
  static const _rootName = 'FutaFinanceレシート';
  static const _rootIdKey = 'futa.drive.receipt_root_id';

  /// セッション中のアクセストークン簡易キャッシュ（Web の再ポップアップ抑制）。
  String? _tokenCache;

  /// レシート画像をアップロードして閲覧リンクを返す。失敗時は null。
  Future<String?> uploadReceiptImage({
    required Uint8List bytes,
    required DateTime date,
    required bool isBusiness,
    String? store,
    int? amount,
  }) async {
    try {
      final token = await _accessToken();
      if (token == null) return null;
      final monthId = await _ensureMonthFolder(token, isBusiness, date);
      final name = _fileName(date, store, amount);
      return await _uploadMultipart(token, name, monthId, bytes);
    } catch (e) {
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
    return '$ymd$cleanStore$amt$uniq.jpg';
  }

  // ── アクセストークン取得（Web / Android で経路が異なる）─────────
  Future<String?> _accessToken() async {
    if (_tokenCache != null) return _tokenCache;
    if (kIsWeb) {
      // Web: Firebase Auth のポップアップに drive.file スコープを足して
      // OAuth アクセストークンを取得する。
      final provider = GoogleAuthProvider()..addScope(_scope);
      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      final oauth = cred.credential;
      _tokenCache = oauth is OAuthCredential ? oauth.accessToken : null;
      return _tokenCache;
    } else {
      // Android/iOS: google_sign_in 7.x の authorizationClient で
      // スコープを認可（初回は同意画面、以降はサイレント）。
      final client = GoogleSignIn.instance.authorizationClient;
      var authz = await client.authorizationForScopes([_scope]);
      authz ??= await client.authorizeScopes([_scope]);
      _tokenCache = authz.accessToken;
      return _tokenCache;
    }
  }

  // ── フォルダ階層を用意して月フォルダIDを返す ─────────────────
  Future<String> _ensureMonthFolder(
      String token, bool isBusiness, DateTime d) async {
    final rootId = await _ensureRoot(token);
    final modeId = await _findOrCreateFolder(
        token, isBusiness ? '事業用' : '個人用', rootId);
    final yearId = await _findOrCreateFolder(token, '${d.year}年', modeId);
    final monthId = await _findOrCreateFolder(
        token, '${d.month.toString().padLeft(2, '0')}月', yearId);
    return monthId;
  }

  Future<String> _ensureRoot(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_rootIdKey);
    if (saved != null && await _folderExists(token, saved)) {
      return saved;
    }
    // 初回はマイドライブ直下に作成（ユーザーが後で移動してもIDで追従）。
    var id = await _findFolder(token, _rootName, 'root');
    id ??= await _createFolder(token, _rootName, 'root');
    await prefs.setString(_rootIdKey, id);
    return id;
  }

  Future<String> _findOrCreateFolder(
      String token, String name, String parentId) async {
    final found = await _findFolder(token, name, parentId);
    if (found != null) return found;
    return _createFolder(token, name, parentId);
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
    return jsonDecode(res.body)['id'] as String;
  }

  Future<bool> _folderExists(String token, String id) async {
    final res = await http.get(
      Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$id?fields=id,trashed'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return false;
    return (jsonDecode(res.body)['trashed'] as bool? ?? false) == false;
  }

  Future<String?> _uploadMultipart(
      String token, String name, String parentId, Uint8List bytes) async {
    const boundary = 'futa_receipt_boundary_8c3f';
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
      return null;
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (j['webViewLink'] as String?) ??
        'https://drive.google.com/file/d/${j['id']}/view';
  }
}
