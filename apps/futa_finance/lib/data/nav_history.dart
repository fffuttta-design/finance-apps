import 'package:flutter/material.dart';

/// マウスの「進む」ボタン用の簡易フォワードスタック（暫定対応）。
///
/// Flutter は「戻る」（pop）はできるが、戻った先を「進む」で復元する標準機能が
/// 無い（Navigator 2.0/go_router 化が必要）。その大改修を避けつつ、主要な
/// フルスクリーン遷移だけを [push] 経由で開いておき、戻ったら "進む候補" として
/// 覚えておく。マウスの進むボタンで [goForward] が呼ばれたら、それを開き直す。
///
/// 対応範囲は [push] を通した画面のみ（設定の各画面・口座/カード詳細など）。
/// モーダルやPCの2ペイン切替などは対象外。
class NavHistory {
  NavHistory._();
  static final NavHistory instance = NavHistory._();

  /// MaterialApp に渡すルート Navigator のキー（goForward 用）。
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 戻って閉じた画面のビルダー（進む候補）。後入れ先出し。
  final List<WidgetBuilder> _forward = [];

  bool get canGoForward => _forward.isNotEmpty;

  /// 直近に戻る/進むを実行した時刻。Electron ではマウスの戻るボタンで
  /// 「app-command（メインプロセス）」と「ポインタイベント（Flutter）」の
  /// 両方が飛んでくることがあり、そのままだと2画面ぶん戻ってしまう。
  /// 短時間の二重発火は捨てる。
  DateTime? _lastNav;
  bool _isDuplicate() {
    final now = DateTime.now();
    if (_lastNav != null &&
        now.difference(_lastNav!).inMilliseconds < 300) {
      return true;
    }
    _lastNav = now;
    return false;
  }

  /// マウス「戻る」：1つ前の画面へ。
  /// ⚠ `MaterialApp.builder` の context は Navigator より**上**なので
  ///    `Navigator.maybeOf(context)` は null になる（これで戻れなかった）。
  ///    ルートの [navigatorKey] から辿ること。
  void goBack() {
    if (_isDuplicate()) return;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) nav.pop();
  }

  /// 新しい画面へ進む。ブラウザ同様、ここで「進む履歴」はクリアされる。
  /// [onReturn] は画面が閉じられて戻ってきた時に呼ばれる（再読込などに使う）。
  void push(BuildContext context, WidgetBuilder builder,
      {VoidCallback? onReturn}) {
    _forward.clear();
    _pushVia(Navigator.of(context), builder, onReturn: onReturn);
  }

  /// マウス「進む」：直前に戻った画面を開き直す。
  void goForward() {
    if (_isDuplicate()) return;
    if (_forward.isEmpty) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _pushVia(nav, _forward.removeLast());
  }

  void _pushVia(NavigatorState nav, WidgetBuilder builder,
      {VoidCallback? onReturn}) {
    nav.push(MaterialPageRoute<void>(builder: builder)).then((_) {
      // 閉じられたら「進む」候補に積む（戻る→進むを繰り返せる）。
      _forward.add(builder);
      onReturn?.call();
    });
  }
}
