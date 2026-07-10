import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI 表示まわりのユーザー設定。SharedPreferences で永続化し、
/// 変更を ChangeNotifier で各画面に伝える。
///
/// 既存の SettingsRepository は「カテゴリ・支払方法」用の Firestore/Local
/// 切替が絡む層なので、表示フラグ等の軽量設定はこちらに分離する。
class UiPreferences extends ChangeNotifier {
  UiPreferences._();
  static final UiPreferences instance = UiPreferences._();

  /// 新キー（v1.0.65〜）: 未使用フラグ ON のものを隠す
  static const _kHideInactive = 'futa.ui.hide_inactive';

  /// 個人モードの支出タブで「家賃」を除外表示するか。
  /// 家賃はハズレ値（金額が大きすぎて他の支出が霞む）なので、
  /// 冷静に他の支出を見たいときに隠せるようにする。デフォルト false（=表示）。
  static const _kHideRent = 'futa.ui.hide_rent';

  /// 事業モードの経費タブで「税務顧問料」を除外表示するか。
  /// 顧問料は毎月ほぼ固定の大きめ費用で、他の経費の増減を見たいとき霞むため、
  /// 家賃(個人)と同じくワンタップで隠せるようにする。デフォルト false（=表示）。
  static const _kHideAdvisory = 'futa.ui.hide_advisory';

  /// 旧キー（〜v1.0.64）: 残高 0 のものを隠す。
  /// 起動時に値があれば新キーへ引き継いで削除する。
  static const _kLegacyHideZero = 'futa.ui.hide_zero_balance';

  /// サイドバー（広い画面の左ナビ）の並び順。
  /// 値は識別子の文字列リスト（'home', 'expenses', 'income', ...）。
  /// 既存に該当しない/欠けている識別子は無視 or デフォルト末尾に追加。
  static const _kSidebarOrder = 'futa.ui.sidebar_order';

  /// タブ（上ナビ）の選択可能な全識別子（デフォルト並び）。
  /// v2.1 上タブに一本化済み。旧 v1 の asset/cards は廃止（report は「業績」）。
  static const defaultSidebarOrder = <String>[
    'home',
    'expenses',
    'income',
    'report',
    'assets',
    'settings',
    'devLab',
  ];

  /// v2 UI（デスクトップ向け抜本リデザイン）を強制 ON/OFF するキー。
  /// - 値なし（null） → 自動判定
  /// - true → v2 強制
  /// - false → v1 強制
  static const _kUseV2Ui = 'futa.ui.use_v2';

  /// v2 のレイアウトバリアント。
  /// - 'sidebar' → マネフォクラウド風の左サイドバー（既定）
  /// - 'topnav' → マネフォ ME 風の上タブ + 中央カラム（v2.1）
  static const _kV2Variant = 'futa.ui.v2_variant';

  /// v2 バリアント識別子。
  static const v2VariantSidebar = 'sidebar';
  static const v2VariantTopNav = 'topnav';

  /// 新デザイン（リッチUI）に固定（v1.0.366〜・旧デザインは廃止）。
  /// 切替トグルは削除し、常に新デザインを使う。
  bool get richUi => true;

  /// ホーム（広い画面）の総資産カラム幅。ユーザーがドラッグで調整・永続化。
  static const _kHomeAssetWidth = 'futa.ui.home_asset_width';
  static const homeAssetWidthMin = 240.0;
  static const homeAssetWidthMax = 560.0;
  static const homeAssetWidthDefault = 320.0;
  double _homeAssetWidth = homeAssetWidthDefault;

  /// ホームの総資産カラム幅（広い画面のみ使用）。
  double get homeAssetColumnWidth => _homeAssetWidth;

  bool _hideInactive = false;
  bool _hideRent = false;
  bool _hideAdvisory = false;
  List<String> _sidebarOrder = List.of(defaultSidebarOrder);
  bool? _useV2Ui;
  String _v2Variant = v2VariantTopNav;
  bool _loaded = false;

  /// 「未使用」フラグの立っているウォレット・口座・クレカを表示系画面で隠すか。
  /// デフォルトは false（=表示）。
  bool get hideInactive => _hideInactive;

  /// 個人モードの支出タブで「家賃」を除外表示するか。
  bool get hideRent => _hideRent;

  /// 事業モードの経費タブで「税務顧問料」を除外表示するか。
  bool get hideAdvisory => _hideAdvisory;
  bool get loaded => _loaded;

  /// 現在のタブ並び順（ユーザー保存値）。
  /// 廃止済みID(asset/cards 等)は除外し、欠けている現行IDは末尾に補完する。
  List<String> get sidebarOrder {
    final valid =
        _sidebarOrder.where((id) => defaultSidebarOrder.contains(id));
    final missing =
        defaultSidebarOrder.where((id) => !valid.contains(id));
    return [...valid, ...missing];
  }

  /// v2 UI 強制設定。null=自動判定。
  bool? get useV2Ui => _useV2Ui;

  /// 現在の v2 レイアウトバリアント（'sidebar' or 'topnav'）。
  String get v2Variant => _v2Variant;

  /// 渡された画面幅から、最終的に v2 を使うかを返す。
  /// - 強制設定（true/false）があればそれに従う
  /// - 未設定なら自動判定: Web は常に v2.1（v1 は非推奨）
  ///   Android アプリは v1（モバイル UI を保持）
  bool resolveUseV2({required bool isWeb, required double width}) {
    final forced = _useV2Ui;
    if (forced != null) return forced;
    return isWeb;
  }

  /// 起動時に一度呼ぶ。多重呼び出しは無害（最初の値を保持）。
  /// 旧キー（hide_zero_balance）が残っている場合は新キーへマイグレーション。
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    // 新キー優先、無ければ旧キーをフォールバック + 移行
    if (prefs.containsKey(_kHideInactive)) {
      _hideInactive = prefs.getBool(_kHideInactive) ?? false;
    } else if (prefs.containsKey(_kLegacyHideZero)) {
      _hideInactive = prefs.getBool(_kLegacyHideZero) ?? false;
      await prefs.setBool(_kHideInactive, _hideInactive);
      await prefs.remove(_kLegacyHideZero);
    } else {
      _hideInactive = false;
    }
    // 家賃を隠す表示設定
    _hideRent = prefs.getBool(_kHideRent) ?? false;
    // 税務顧問料を隠す表示設定（事業モード）
    _hideAdvisory = prefs.getBool(_kHideAdvisory) ?? false;
    // サイドバー並び順
    final savedOrder = prefs.getStringList(_kSidebarOrder);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      _sidebarOrder = savedOrder;
    } else {
      _sidebarOrder = List.of(defaultSidebarOrder);
    }
    // v2 UI 強制設定（未設定なら null）
    if (prefs.containsKey(_kUseV2Ui)) {
      _useV2Ui = prefs.getBool(_kUseV2Ui);
    } else {
      _useV2Ui = null;
    }
    // v2 バリアント。未設定は topnav（v2.1）を既定とする。
    final variant = prefs.getString(_kV2Variant);
    _v2Variant = (variant == v2VariantSidebar)
        ? v2VariantSidebar
        : v2VariantTopNav;
    // ホーム総資産カラム幅
    final w = prefs.getDouble(_kHomeAssetWidth) ?? homeAssetWidthDefault;
    _homeAssetWidth = w.clamp(homeAssetWidthMin, homeAssetWidthMax);
    _loaded = true;
    notifyListeners();
  }

  /// ホームの総資産カラム幅を更新して永続化（範囲内にクランプ）。
  Future<void> setHomeAssetColumnWidth(double w) async {
    final c = w.clamp(homeAssetWidthMin, homeAssetWidthMax);
    if (c == _homeAssetWidth) return;
    _homeAssetWidth = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kHomeAssetWidth, c);
    notifyListeners();
  }

  /// v2 バリアントを更新。
  Future<void> setV2Variant(String variant) async {
    if (variant != v2VariantSidebar && variant != v2VariantTopNav) {
      return;
    }
    _v2Variant = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kV2Variant, variant);
    notifyListeners();
  }

  /// v2 UI 強制設定を更新。null を渡すと自動判定に戻す。
  Future<void> setUseV2Ui(bool? v) async {
    _useV2Ui = v;
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_kUseV2Ui);
    } else {
      await prefs.setBool(_kUseV2Ui, v);
    }
    notifyListeners();
  }

  Future<void> setHideInactive(bool v) async {
    if (_hideInactive == v) return;
    _hideInactive = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideInactive, v);
    notifyListeners();
  }

  /// 家賃を隠す表示設定を更新して永続化。
  Future<void> setHideRent(bool v) async {
    if (_hideRent == v) return;
    _hideRent = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideRent, v);
    notifyListeners();
  }

  /// 税務顧問料を隠す表示設定を更新して永続化（事業モード）。
  Future<void> setHideAdvisory(bool v) async {
    if (_hideAdvisory == v) return;
    _hideAdvisory = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideAdvisory, v);
    notifyListeners();
  }

  /// サイドバー並び順を更新して永続化。
  Future<void> setSidebarOrder(List<String> order) async {
    _sidebarOrder = List.of(order);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSidebarOrder, _sidebarOrder);
    notifyListeners();
  }

  /// 並び順をデフォルトに戻す。
  Future<void> resetSidebarOrder() async {
    await setSidebarOrder(List.of(defaultSidebarOrder));
  }
}
