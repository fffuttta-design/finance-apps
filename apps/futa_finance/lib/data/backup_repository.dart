import 'dart:convert';
import 'dart:io';

import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';
import 'checklist_repository.dart';
import 'income_source_repository.dart';
import 'month_closing_repository.dart';
import 'monthly_snapshot_repository.dart';
import 'settings_repository.dart';
import 'subscription_repository.dart';
import 'transaction_repository.dart';

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
  ///
  /// [reason] は「何の前のスナップショットか」を示す英字タグ。
  /// ファイル名に埋め込み、後でスナップショット一覧で識別できる。
  /// - "pre-import"  : JSON 取り込みの直前
  /// - "pre-wipe"    : 全削除の直前
  /// - "pre-sample"  : サンプル投入の直前
  /// - "manual"      : ユーザー任意の手動取得
  ///
  /// Web では path_provider が File API を提供しないためスキップ。
  /// （Firestore 同期環境では取り込みデータの上書きも別端末から復旧可能なので、
  ///  Web 側のローカルスナップショットが無くても運用上は問題なし）
  Future<File?> savePreImportSnapshot({String reason = 'pre-import'}) async {
    if (kIsWeb) return null;
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
      // reason は英数とハイフン以外を除去（ファイル名に安全な形に）
      final safeReason = reason.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '-');
      final file = File('${dir.path}/$safeReason-$stamp.json');
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
  /// Web では常に空。
  Future<List<AutoSnapshotInfo>> listAutoSnapshots() async {
    if (kIsWeb) return [];
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
  // 手動バックアップの最終実施日（リマインダー用）
  // ───────────────────────────────────────────────────────────────

  /// 「最後に手動バックアップを取った日時」を SharedPreferences に保持するキー。
  static const _kLastManualBackupAt = 'futa.backup.last_manual_at';

  /// 「14日リマインダーを次にいつまで黙らせるか」を保持するキー（後で でスヌーズ）。
  static const _kRemindSnoozeUntil = 'futa.backup.remind_snooze_until';

  /// リマインドのしきい値（日数）。
  static const int reminderThresholdDays = 14;

  /// 手動バックアップ完了を記録する（exportAll() を実行した UI 側から呼ぶ）。
  Future<void> markManualBackupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kLastManualBackupAt, DateTime.now().toIso8601String());
    // バックアップしたらスヌーズも解除（次の14日後にまたリマインド）
    await prefs.remove(_kRemindSnoozeUntil);
  }

  /// 最後の手動バックアップ日時。未実施なら null。
  Future<DateTime?> lastManualBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastManualBackupAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// 「リマインドを次に出してよい時刻」。null なら制限なし。
  Future<DateTime?> _remindSnoozeUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRemindSnoozeUntil);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// 「あとで」で 3日間 リマインドをスヌーズ。
  Future<void> snoozeReminder({int days = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(Duration(days: days));
    await prefs.setString(_kRemindSnoozeUntil, until.toIso8601String());
  }

  /// 今リマインダーを出すべきか判定する。
  /// 条件:
  ///   1) 過去に1度でも手動バックアップしている（してないと意味不明）
  ///   2) 最終バックアップから [reminderThresholdDays] 日経過
  ///   3) スヌーズ期限が切れている（または未設定）
  Future<BackupReminderState> shouldRemindBackup() async {
    final last = await lastManualBackupAt();
    if (last == null) return BackupReminderState.noPriorBackup;
    final days = DateTime.now().difference(last).inDays;
    if (days < reminderThresholdDays) return BackupReminderState.fresh;
    final snooze = await _remindSnoozeUntil();
    if (snooze != null && DateTime.now().isBefore(snooze)) {
      return BackupReminderState.snoozed;
    }
    return BackupReminderState.shouldRemind;
  }

  // ───────────────────────────────────────────────────────────────

  /// 全データを JSON 文字列としてエクスポートする。
  ///
  /// ★重要: 端末ローカル(SharedPreferences)ではなく、現在アクティブな
  /// リポジトリ（ログイン中は Firestore / 未ログインは Local）から読む。
  /// これでログイン状態でも「画面に出ているデータ」を正しく書き出す。
  /// 事業/個人の両モードを順に読むため、一時的にモードを切り替える。
  Future<String> exportAll() async {
    final info = await PackageInfo.fromPlatform();
    final originalMode = AppModeManager.instance.current;

    final data = <String, Map<String, dynamic>>{};
    for (final entry in _modes.entries) {
      final modeLabel = entry.value;
      final mode = entry.key == 'b' ? AppMode.business : AppMode.personal;
      if (AppModeManager.instance.current != mode) {
        await AppModeManager.instance.setMode(mode);
      }

      final modeData = <String, dynamic>{};
      try {
        final txns = await TransactionRepository.instance.loadAll();
        modeData['transactions'] = txns.map((t) => t.toJson()).toList();
      } catch (_) {}

      Future<void> addConfig(
          String key, Future<String> Function() readJsonString) async {
        try {
          modeData[key] = jsonDecode(await readJsonString());
        } catch (_) {}
      }

      await addConfig('categories',
          () async => (await SettingsRepository.instance.loadCategories()).toJsonString());
      await addConfig('payments',
          () async => (await SettingsRepository.instance.loadPayments()).toJsonString());
      await addConfig('subscriptions',
          () async => (await SubscriptionRepository.instance.load()).toJsonString());
      await addConfig('income_sources',
          () async => (await IncomeSourceRepository.instance.load()).toJsonString());
      await addConfig('monthly_snapshots',
          () async => (await MonthlySnapshotRepository.instance.load()).toJsonString());
      await addConfig('month_closing',
          () async => (await MonthClosingRepository.instance.load()).toJsonString());
      await addConfig('checklist',
          () async => (await ChecklistRepository.instance.load()).toJsonString());

      data[modeLabel] = modeData;
    }

    if (AppModeManager.instance.current != originalMode) {
      await AppModeManager.instance.setMode(originalMode);
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
    await savePreImportSnapshot(reason: 'pre-import');

    final prefs = await SharedPreferences.getInstance();

    // ── 取り込み前の件数スナップショット
    final beforeCounts = _snapshotCounts(prefs);

    int totalKeys = 0;
    final restoredModes = <String>[];

    // ── 現在の AppMode を退避（取り込み中にモード切替するため）
    final originalMode = AppModeManager.instance.current;

    for (final entry in _modes.entries) {
      final modePrefix = entry.key;
      final modeLabel = entry.value;
      final mode = modePrefix == 'b' ? AppMode.business : AppMode.personal;
      final modeData = data[modeLabel];
      if (modeData is! Map<String, dynamic>) continue;

      // Repository.instance は AppMode 依存のキー/コレクションを使うため、
      // 取り込み対象のモードに一時的に切り替える必要がある。
      if (AppModeManager.instance.current != mode) {
        await AppModeManager.instance.setMode(mode);
      }

      int modeKeyCount = 0;
      for (final key in _targetKeys) {
        if (!modeData.containsKey(key)) continue;
        final value = modeData[key];
        final encoded = value is String ? value : jsonEncode(value);
        // (1) SharedPreferences (Local Repository が見る場所) を更新
        await prefs.setString(_fullKey(modePrefix, key), encoded);
        // (2) 現在アクティブな Repository (Firestore / Local) にも書く
        //     これで Firestore 同期環境でも UI に即反映される
        await _writeToActiveRepository(key, value);
        modeKeyCount++;
        totalKeys++;
      }
      if (modeKeyCount > 0) restoredModes.add(modeLabel);
    }

    // モードを元に戻す
    if (AppModeManager.instance.current != originalMode) {
      await AppModeManager.instance.setMode(originalMode);
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

  /// 取り込んだデータを現在アクティブな Repository (Firestore or Local) に書き込む。
  /// AppMode は事前に呼び出し側で対象モードに切替されている前提。
  ///
  /// 個別キーで失敗しても他のキー取り込みは続行（best-effort）。
  Future<void> _writeToActiveRepository(String key, dynamic value) async {
    try {
      // Config 系の fromJsonString に渡す文字列。
      // バックアップ JSON では Config は文字列で格納されている形式と
      // 直接ネストオブジェクトの形式の両方があり得るのでケアする。
      final source = value is String ? value : jsonEncode(value);

      switch (key) {
        case 'transactions':
          // 取引はリスト構造（文字列なら decode してリスト化）。
          final decoded = value is String ? jsonDecode(value) : value;
          final list = (decoded as List)
              .map((e) =>
                  core.Transaction.fromJson(e as Map<String, dynamic>))
              .toList();
          await TransactionRepository.instance.replaceAll(list);
          break;
        case 'categories':
          final config = core.CategoryConfig.fromJsonString(source);
          await SettingsRepository.instance.saveCategories(config);
          break;
        case 'payments':
          final config = core.PaymentMethodsConfig.fromJsonString(source);
          await SettingsRepository.instance.savePayments(config);
          break;
        case 'subscriptions':
          final config = core.SubscriptionConfig.fromJsonString(source);
          await SubscriptionRepository.instance.save(config);
          break;
        case 'income_sources':
          final config = core.IncomeSourceConfig.fromJsonString(source);
          await IncomeSourceRepository.instance.save(config);
          break;
        case 'monthly_snapshots':
          final config = core.MonthlySnapshotConfig.fromJsonString(source);
          await MonthlySnapshotRepository.instance.save(config);
          break;
        case 'month_closing':
          final config = core.MonthClosingConfig.fromJsonString(source);
          await MonthClosingRepository.instance.save(config);
          break;
        case 'checklist':
          final config = core.ChecklistConfig.fromJsonString(source);
          await ChecklistRepository.instance.save(config);
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Repository write failed for $key: $e');
      }
    }
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

/// バックアップリマインダーの判定結果。
enum BackupReminderState {
  /// まだ一度も手動バックアップしたことがない（リマインドしない）
  noPriorBackup,

  /// 最終バックアップから 14日 未満（フレッシュ）
  fresh,

  /// 14日経過しているがユーザーが「あとで」でスヌーズ中
  snoozed,

  /// リマインドを出すべき
  shouldRemind,
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

  /// ファイル名から「取得理由」タグを抽出する。
  /// 例: pre-import-20260527-153045.json → "pre-import"
  /// 該当しなければ null。
  String? get reasonTag {
    final base = file.uri.pathSegments.last; // "pre-import-20260527-153045.json"
    // タイムスタンプ "-YYYYMMDD-" の前までが reason
    final m = RegExp(r'^(.+?)-\d{8}-\d{6}\.json$').firstMatch(base);
    return m?.group(1);
  }

  /// reason の日本語ラベル。UI 一覧での識別用。
  String? get reasonLabel {
    switch (reasonTag) {
      case 'pre-import':
        return 'JSON取り込み前';
      case 'pre-wipe':
        return '全削除前';
      case 'pre-sample':
        return 'サンプル投入前';
      case 'manual':
        return '手動';
      default:
        return null;
    }
  }
}
