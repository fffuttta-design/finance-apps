import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ全体のモード（事業用 vs 個人用）。
/// データは shared_preferences のキープレフィックスで完全分離する。
enum AppMode {
  /// 事業用（会社の収支）。
  business,

  /// 個人用（プライベートの収支）。
  personal,
}

extension AppModeX on AppMode {
  /// 短縮ラベル。UIで使う。
  String get label => this == AppMode.business ? '事業' : '個人';

  /// 長めの説明。
  String get description =>
      this == AppMode.business ? '会社・事業用の収支' : 'プライベート用の収支';

  /// モードを示すアクセント色。
  Color get accentColor => this == AppMode.business
      ? const Color(0xFF1A237E) // 紺
      : const Color(0xFFEA580C); // 暖色オレンジ

  /// モード別の薄背景色（画面全体に敷く）。
  /// パッと見でモードがわかるように、アクセント色の超薄バリエーション。
  Color get backgroundTint => this == AppMode.business
      ? const Color(0xFFEEF2FF) // 薄い紺 (indigo-50)
      : const Color(0xFFFFF7ED); // 薄いオレンジ (orange-50)

  /// shared_preferences キーのプレフィックス（短く分かりやすく）。
  String get keyPrefix => this == AppMode.business ? 'b' : 'p';

  IconData get icon =>
      this == AppMode.business ? Icons.business_center : Icons.person;
}

/// 現モードを保持し変更通知を発火するシングルトン。
class AppModeManager extends ChangeNotifier {
  AppModeManager._();
  static final AppModeManager instance = AppModeManager._();

  static const _modeKey = 'futa.app_mode';
  static const _migrationKey = 'futa.migration.v2_mode_aware';

  AppMode _mode = AppMode.business;
  bool _initialized = false;

  AppMode get current => _mode;
  bool get isInitialized => _initialized;

  /// 起動時に1回だけ呼ぶ。永続化されたモード読込 + 旧データの移行。
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modeKey);
    if (saved != null) {
      _mode = AppMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => AppMode.business,
      );
    }
    await _migrateLegacyKeys(prefs);
    _initialized = true;
  }

  /// 旧キー(モード分離前)を「事業モード」のキーに移行する。1回だけ実行。
  Future<void> _migrateLegacyKeys(SharedPreferences prefs) async {
    if (prefs.getBool(_migrationKey) == true) return;

    const legacyBases = [
      'futa.transactions',
      'futa.categories',
      'futa.payments',
      'futa.income_sources',
      'futa.subscriptions',
    ];
    for (final legacy in legacyBases) {
      // legacy: 'futa.transactions' → 新: 'futa.b.transactions'
      final base = legacy.substring(5); // "transactions" など
      final newKey = 'futa.b.$base';
      final value = prefs.getString(legacy);
      if (value != null && prefs.getString(newKey) == null) {
        await prefs.setString(newKey, value);
      }
    }
    await prefs.setBool(_migrationKey, true);
  }

  Future<void> setMode(AppMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    // UI を即座に更新する。永続化（ディスク書き込み）の完了は待たない＝
    // 切替直後のカクつき/もたつきを防ぐ。notifyListeners() は同期的に走るため
    // この時点で各画面のリビルドが始まる。
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }
}

/// モード変更を検知して画面を再読込するための Mixin。
///
/// 使い方:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with ModeAwareMixin {
///   @override
///   void onModeChanged() => _load();
/// }
/// ```
mixin ModeAwareMixin<T extends StatefulWidget> on State<T> {
  void onModeChanged();

  @override
  void initState() {
    super.initState();
    AppModeManager.instance.addListener(_handleModeChange);
  }

  @override
  void dispose() {
    AppModeManager.instance.removeListener(_handleModeChange);
    super.dispose();
  }

  void _handleModeChange() {
    if (mounted) onModeChanged();
  }
}
