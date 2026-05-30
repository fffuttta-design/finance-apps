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

  /// 旧キー（〜v1.0.64）: 残高 0 のものを隠す。
  /// 起動時に値があれば新キーへ引き継いで削除する。
  static const _kLegacyHideZero = 'futa.ui.hide_zero_balance';

  /// サイドバー（広い画面の左ナビ）の並び順。
  /// 値は識別子の文字列リスト（'home', 'expenses', 'income', ...）。
  /// 既存に該当しない/欠けている識別子は無視 or デフォルト末尾に追加。
  static const _kSidebarOrder = 'futa.ui.sidebar_order';

  /// サイドバーで選択可能な全ナビ識別子（デフォルト並び）。
  static const defaultSidebarOrder = <String>[
    'home',
    'expenses',
    'income',
    'asset',
    'cards',
    'report',
    'settings',
    'devLab',
  ];

  bool _hideInactive = false;
  List<String> _sidebarOrder = List.of(defaultSidebarOrder);
  bool _loaded = false;

  /// 「未使用」フラグの立っているウォレット・口座・クレカを表示系画面で隠すか。
  /// デフォルトは false（=表示）。
  bool get hideInactive => _hideInactive;
  bool get loaded => _loaded;

  /// 現在のサイドバー並び順（ユーザー保存値、欠けがあればデフォルトで補う）。
  List<String> get sidebarOrder {
    // 保存値に含まれない既知の識別子は末尾に補完（新タブ追加時にも壊さない）
    final missing = defaultSidebarOrder
        .where((id) => !_sidebarOrder.contains(id))
        .toList();
    return [..._sidebarOrder, ...missing];
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
    // サイドバー並び順
    final savedOrder = prefs.getStringList(_kSidebarOrder);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      _sidebarOrder = savedOrder;
    } else {
      _sidebarOrder = List.of(defaultSidebarOrder);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setHideInactive(bool v) async {
    if (_hideInactive == v) return;
    _hideInactive = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideInactive, v);
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
