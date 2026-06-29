import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_bridge.dart' as desktop;
import 'windows_google_auth.dart';

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

  /// 裏で完了したアップロードの結果URL（receiptId → webViewLink）。
  /// 「保存より先にアップロードが完了した」場合に、保存時へURLを渡すために使う。
  final Map<String, String> _resultUrls = {};
  void rememberUrl(String receiptId, String url) =>
      _resultUrls[receiptId] = url;
  String? urlFor(String receiptId) => _resultUrls[receiptId];

  /// 直近の失敗理由（UI 表示・原因切り分け用）。成功時は null。
  String? lastError;

  /// Drive のファイルURL/IDからファイルIDを取り出す。
  /// 例: `https://drive.google.com/file/d/{ID}/view?usp=...` から `{ID}` を返す。
  static String? fileIdFromUrl(String urlOrId) {
    final s = urlOrId.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'/d/([A-Za-z0-9_-]+)').firstMatch(s) ??
        RegExp(r'[?&]id=([A-Za-z0-9_-]+)').firstMatch(s);
    if (m != null) return m.group(1);
    if (!s.contains('/') && !s.contains(' ')) return s;
    return null;
  }

  /// 自分の権限トークンでDriveから画像バイトを取得（アプリ内表示用）。
  /// ブラウザ/再ログイン不要で開ける（drive.file=アプリ作成ファイルに有効）。
  Future<Uint8List?> downloadFile(String fileId) async {
    lastError = null;
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
      return res.bodyBytes;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// フォルダIDのメモリキャッシュ。毎回の探索/作成API往復を省いて高速化。
  /// key: "親ID|フォルダ名" → フォルダID。
  final Map<String, String> _folderCache = {};

  /// 月フォルダIDのキャッシュ。key: "事業/個人-YYYY-MM" → 月フォルダID。
  final Map<String, String> _monthPathCache = {};

  /// レシート画像をアップロードして閲覧リンクを返す。失敗時は null（lastError に理由）。
  Future<String?> uploadReceiptImage({
    required Uint8List bytes,
    required DateTime date,
    required bool isBusiness,
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
      final monthId = await _ensureMonthFolder(token, isBusiness, date);
      final name = _fileName(date, store, amount);
      return await _uploadMultipart(token, name, monthId, bytes);
    } catch (e) {
      lastError = e.toString();
      if (kDebugMode) debugPrint('Drive upload error: $e');
      return null;
    }
  }

  /// 指定モード×月のフォルダにある領収書ファイル一覧を返す（新しい順）。
  /// ※ drive.file 権限のため、このアプリが保存したファイルのみ見える。
  /// フォルダ未作成なら空リスト。失敗時も空（lastError に理由）。
  Future<List<DriveReceiptFile>> listMonthReceipts({
    required DateTime date,
    required bool isBusiness,
  }) async {
    lastError = null;
    try {
      final token = await _accessToken();
      if (token == null) {
        lastError = 'アクセストークンを取得できませんでした';
        return const [];
      }
      final monthId = await _findMonthFolderOnly(token, isBusiness, date);
      if (monthId == null) return const []; // まだ保存実績なし
      final q =
          "'$monthId' in parents and trashed=false and mimeType!='application/vnd.google-apps.folder'";
      final uri = Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=${Uri.encodeQueryComponent(q)}'
          '&fields=files(id,name,webViewLink,createdTime)&orderBy=createdTime desc'
          '&spaces=drive&pageSize=200');
      var res =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 401) {
        final fresh = await _accessToken(forceRefresh: true);
        if (fresh != null) {
          res = await http
              .get(uri, headers: {'Authorization': 'Bearer $fresh'});
        }
      }
      if (res.statusCode != 200) {
        lastError = '一覧取得失敗 (${res.statusCode})';
        return const [];
      }
      final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
      return files.map((f) {
        final m = f as Map<String, dynamic>;
        final id = m['id'] as String;
        return DriveReceiptFile(
          id: id,
          name: (m['name'] as String?) ?? '(無名)',
          webViewLink: (m['webViewLink'] as String?) ??
              'https://drive.google.com/file/d/$id/view',
          createdTime: m['createdTime'] != null
              ? DateTime.tryParse(m['createdTime'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// 月フォルダを「探すだけ」（無ければ作らずに null）。一覧表示用。
  Future<String?> _findMonthFolderOnly(
      String token, bool isBusiness, DateTime d) async {
    final mk =
        '${isBusiness ? 'b' : 'p'}-${d.year}-${d.month.toString().padLeft(2, '0')}';
    final cached = _monthPathCache[mk];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var rootId = prefs.getString(_rootIdKey);
    rootId ??= await _findFolder(token, _rootName, 'root');
    if (rootId == null) return null;
    final modeId =
        await _findFolder(token, isBusiness ? '事業用' : '個人用', rootId);
    if (modeId == null) return null;
    final yearId = await _findFolder(token, '${d.year}年', modeId);
    if (yearId == null) return null;
    final monthId = await _findFolder(
        token, '${d.month.toString().padLeft(2, '0')}月', yearId);
    if (monthId != null) _monthPathCache[mk] = monthId;
    return monthId;
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
  /// [forceRefresh] true で、期限切れトークンを捨てて新しく取り直す（401対策）。
  Future<String?> _accessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _tokenCache != null) return _tokenCache;
    if (forceRefresh) _tokenCache = null;
    if (desktop.isDesktopShell) {
      // Electron デスクトップ版：ログイン時の OAuth で drive.file も認可済み。
      // メインプロセスが refresh_token から access_token を更新して返す。
      _tokenCache = await desktop.desktopDriveToken(forceRefresh: forceRefresh);
      return _tokenCache;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      // Windows: ログイン時の OAuth で drive.file も認可済み。
      // WindowsGoogleAuth が保持する refresh_token から取得・更新する。
      _tokenCache =
          await WindowsGoogleAuth.instance.accessToken(forceRefresh: forceRefresh);
      return _tokenCache;
    }
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
      // 強制リフレッシュ時はキャッシュ済み(=期限切れの可能性)を使わず取り直す。
      var authz =
          forceRefresh ? null : await client.authorizationForScopes([_scope]);
      authz ??= await client.authorizeScopes([_scope]);
      _tokenCache = authz.accessToken;
      return _tokenCache;
    }
  }

  // ── フォルダ階層を用意して月フォルダIDを返す ─────────────────
  Future<String> _ensureMonthFolder(
      String token, bool isBusiness, DateTime d) async {
    // 同じ「モード×年×月」は2回目以降キャッシュで即返す（API往復ゼロ）。
    final mk =
        '${isBusiness ? 'b' : 'p'}-${d.year}-${d.month.toString().padLeft(2, '0')}';
    final cached = _monthPathCache[mk];
    if (cached != null) return cached;
    final rootId = await _ensureRoot(token);
    final modeId = await _findOrCreateFolder(
        token, isBusiness ? '事業用' : '個人用', rootId);
    final yearId = await _findOrCreateFolder(token, '${d.year}年', modeId);
    final monthId = await _findOrCreateFolder(
        token, '${d.month.toString().padLeft(2, '0')}月', yearId);
    _monthPathCache[mk] = monthId;
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
      throw 'アップロード失敗 (${res.statusCode}) ${_short(res.body)}';
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (j['webViewLink'] as String?) ??
        'https://drive.google.com/file/d/${j['id']}/view';
  }
}

/// Drive 上の領収書ファイル1件（一覧表示・紐付け用）。
class DriveReceiptFile {
  final String id;
  final String name;
  final String webViewLink;
  final DateTime? createdTime;
  const DriveReceiptFile({
    required this.id,
    required this.name,
    required this.webViewLink,
    this.createdTime,
  });
}
