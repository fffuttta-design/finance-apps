import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ全データを 1 つの JSON にエクスポート/インポートする。
///
/// 現状は SharedPreferences ベース。事業（b）/個人（p）モードの両方の
/// 全データを1ファイルにまとめる。Firestore 等へ移行する際は本クラスの
/// 中身だけ差し替えれば UI 側に影響を出さずに済む。
///
/// JSON スキーマ:
/// ```
/// {
///   "appVersion": "1.0.x",
///   "exportedAt": "ISO8601",
///   "schema": 1,
///   "data": {
///     "business": { "categories": {...}, "payments": {...}, ... },
///     "personal":  { ... }
///   }
/// }
/// ```
class BackupRepository {
  BackupRepository._();
  static final BackupRepository instance = BackupRepository._();

  /// スキーマバージョン。データ構造が変わる時にインクリメントする。
  static const int schemaVersion = 1;

  /// モード別 prefix → 表示用キー。
  static const _modes = <String, String>{
    'b': 'business',
    'p': 'personal',
  };

  /// バックアップ対象のキー（モード prefix の下に存在するもの）。
  /// 追加するときはここに足すだけで自動的に対象になる。
  static const _targetKeys = <String>[
    'categories',
    'payments',
    'transactions',
    'income_sources',
    'subscriptions',
    'monthly_snapshots',
    'checklist',
    'month_closing',
  ];

  String _fullKey(String modePrefix, String key) => 'futa.$modePrefix.$key';

  // ───────────────────────────────────────────────────────────────
  // 自動スナップショット（取り込み前に現状を退避）
  // ───────────────────────────────────────────────────────────────

  /// 自動スナップショット保存先ディレクトリ。
  /// アプリ内部の Documents/auto_snapshots/ に切る（アンインストールで消える）。
  Future<Directory> _autoSnapshotDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/auto_snapshots');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 自動スナップショットの最大保持世代数。古いものから順に削除。
  static const int maxAutoSnapshots = 10;

  /// 取り込み実行直前に呼ぶ。現在の SharedPreferences を JSON 化して
  /// auto_snapshots/ にタイムスタンプ付きで保存。
  /// 失敗しても取り込み本体は止めない（best-effort）。
  Future<File?> savePreImportSnapshot() async {
    try {
      final json = await exportAll();
      final dir = await _autoSnapshotDir();
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/pre-import-$stamp.json');
      await file.writeAsString(json);
      await _pruneOldSnapshots();
      return file;
    } catch (_) {
      // スナップショット失敗は取り込みの妨げにはしない
      return null;
    }
  }

  /// 古いスナップショットを削除（最新 [maxAutoSnapshots] 件だけ残す）。
  Future<void> _pruneOldSnapshots() async {
    final dir = await _autoSnapshotDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (files.length <= maxAutoSnapshots) return;
    for (final f in files.skip(maxAutoSnapshots)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// 保存済みスナップショット一覧（新しい順）。
  Future<List<AutoSnapshotInfo>> listAutoSnapshots() async {
    final dir = await _autoSnapshotDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files.map((f) {
      final stat = f.statSync();
      return AutoSnapshotInfo(
        file: f,
        createdAt: stat.modified,
        sizeBytes: stat.size,
      );
    }).toList();
  }

  /// スナップショットを取り込んで復元する（importAll を呼ぶラッパ）。
  /// この呼び出し自体も自動スナップショットを取る（連続して間違えても1個前に戻れる）。
  Future<BackupImportResult> restoreFromSnapshot(File snapshot) async {
    final json = await snapshot.readAsString();
    return importAll(json);
  }

  // ───────────────────────────────────────────────────────────────

  /// 全データを JSON 文字列としてエクスポートする。
  Future<String> exportAll() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();

    final data = <String, Map<String, dynamic>>{};
    for (final entry in _modes.entries) {
      final modePrefix = entry.key;
      final modeLabel = entry.value;
      final modeData = <String, dynamic>{};
      for (final key in _targetKeys) {
        final raw = prefs.getString(_fullKey(modePrefix, key));
        if (raw == null) continue;
        // 各値は既に JSON 文字列で保存されている → ネスト JSON として埋め込む
        try {
          modeData[key] = jsonDecode(raw);
        } catch (_) {
          // 万が一壊れていたら文字列のまま保存（救済策）
          modeData[key] = raw;
        }
      }
      data[modeLabel] = modeData;
    }

    final payload = <String, dynamic>{
      'appVersion': info.version,
      'exportedAt': DateTime.now().toIso8601String(),
      'schema': schemaVersion,
      'data': data,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// バックアップ JSON 文字列を取り込み、全データを上書き保存する。
  /// 既存のデータは消えるため、呼び出し前に確認ダイアログを必ず出すこと。
  ///
  /// 取り込んだモード/キーのみ上書きする（存在しないキーは触らない）。
  /// 完全リセットしたい場合は別途実装。
  ///
  /// 取り込み実行直前に、現在の状態を自動スナップショットとして
  /// `Documents/auto_snapshots/` に保存する（誤取り込みからの一発復旧用）。
  Future<BackupImportResult> importAll(String jsonString) async {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw BackupException('JSONのパースに失敗しました: $e');
    }
    final schema = json['schema'];
    if (schema is! int) {
      throw BackupException('バックアップファイルにスキーマ情報がありません');
    }
    if (schema > schemaVersion) {
      throw BackupException(
          'このアプリ（schema=$schemaVersion）より新しいバックアップ（schema=$schema）です。アプリを更新してください。');
    }
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw BackupException('バックアップの data フィールドが不正です');
    }

    // ── 取り込み実行 *前* に現在の状態を自動スナップショット
    // 失敗しても取り込み本体は止めない（best-effort）
    await savePreImportSnapshot();

    final prefs = await SharedPreferences.getInstance();

    // ── 取り込み前の件数スナップショット
    final beforeCounts = _snapshotCounts(prefs);

    int totalKeys = 0;
    final restoredModes = <String>[];

    for (final entry in _modes.entries) {
      final modePrefix = entry.key;
      final modeLabel = entry.value;
      final modeData = data[modeLabel];
      if (modeData is! Map<String, dynamic>) continue;

      int modeKeyCount = 0;
      for (final key in _targetKeys) {
        if (!modeData.containsKey(key)) continue;
        final value = modeData[key];
        final encoded = value is String ? value : jsonEncode(value);
        await prefs.setString(_fullKey(modePrefix, key), encoded);
        modeKeyCount++;
        totalKeys++;
      }
      if (modeKeyCount > 0) restoredModes.add(modeLabel);
    }

    // ── 取り込み後の件数スナップショット
    final afterCounts = _snapshotCounts(prefs);

    return BackupImportResult(
      appVersion: json['appVersion']?.toString() ?? '',
      exportedAt: json['exportedAt']?.toString() ?? '',
      note: json['note']?.toString(),
      restoredModes: restoredModes,
      restoredKeyCount: totalKeys,
      beforeCounts: beforeCounts,
      afterCounts: afterCounts,
    );
  }

  /// 現在の SharedPreferences から各モード x 各キー の「件数」を抜き出す。
  /// 取り込み前後の比較に使う。
  Map<String, Map<String, int>> _snapshotCounts(SharedPreferences prefs) {
    final out = <String, Map<String, int>>{};
    for (final entry in _modes.entries) {
      final modeLabel = entry.value;
      final counts = <String, int>{};
      for (final key in _targetKeys) {
        final raw = prefs.getString(_fullKey(entry.key, key));
        counts[key] = _countItems(key, raw);
      }
      out[modeLabel] = counts;
    }
    return out;
  }

  /// 各キーの JSON 文字列から「件数」を抽出する。
  /// 想定形式：
  /// - transactions / income_sources / month_closing / monthly_snapshots → List
  /// - payments → bankAccounts + creditCards の合計
  /// - categories → majors.length
  /// - subscriptions → subscriptions.length
  /// - checklist → items.length（サブ項目は数えない）
  int _countItems(String key, String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final parsed = jsonDecode(raw);
      switch (key) {
        case 'transactions':
          return (parsed as List).length;
        case 'payments':
          if (parsed is Map<String, dynamic>) {
            final bank = (parsed['bankAccounts'] as List?)?.length ?? 0;
            final card = (parsed['creditCards'] as List?)?.length ?? 0;
            return bank + card;
          }
          return 0;
        case 'categories':
          if (parsed is Map<String, dynamic>) {
            return (parsed['majors'] as List?)?.length ?? 0;
          }
          return 0;
        case 'subscriptions':
          if (parsed is Map<String, dynamic>) {
            return (parsed['subscriptions'] as List?)?.length ?? 0;
          }
          return 0;
        case 'checklist':
          if (parsed is Map<String, dynamic>) {
            return (parsed['items'] as List?)?.length ?? 0;
          }
          return 0;
        case 'income_sources':
          if (parsed is Map<String, dynamic>) {
            return (parsed['sources'] as List?)?.length ?? 0;
          }
          if (parsed is List) return parsed.length;
          return 0;
        case 'monthly_snapshots':
          if (parsed is Map<String, dynamic>) {
            return (parsed['snapshots'] as List?)?.length ?? 0;
          }
          if (parsed is List) return parsed.length;
          return 0;
        case 'month_closing':
          if (parsed is Map<String, dynamic>) {
            return (parsed['closings'] as List?)?.length ?? 0;
          }
          if (parsed is List) return parsed.length;
          return 0;
      }
    } catch (_) {}
    return 0;
  }
}

/// インポート完了時の結果（UI で表示する用）。
class BackupImportResult {
  final String appVersion;
  final String exportedAt;
  final String? note;
  final List<String> restoredModes;
  final int restoredKeyCount;

  /// 取り込み前の各モード x 各キーの件数（"business" → {"transactions": 30, ...}）。
  final Map<String, Map<String, int>> beforeCounts;

  /// 取り込み後の各モード x 各キーの件数。
  final Map<String, Map<String, int>> afterCounts;

  const BackupImportResult({
    required this.appVersion,
    required this.exportedAt,
    this.note,
    required this.restoredModes,
    required this.restoredKeyCount,
    this.beforeCounts = const {},
    this.afterCounts = const {},
  });
}

/// バックアップ処理の失敗（ユーザーに見せる例外）。
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// 自動スナップショット1ファイル分のメタ情報（UI 表示用）。
class AutoSnapshotInfo {
  final File file;
  final DateTime createdAt;
  final int sizeBytes;

  const AutoSnapshotInfo({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
  });

  /// 「2026/05/27 15:30:45」のような表示用文字列。
  String get displayLabel {
    final d = createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// 「3.2 KB」のようなサイズ表示。
  String get displaySize {
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}
