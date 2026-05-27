// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// このファイルは Web 専用（conditional import 経由でのみ読み込まれる）
// なので dart:html / dart:ui_web を直接使うのが正しい使い方。
// Web 専用の画像レンダリング実装。
//
// Flutter Web (CanvasKit レンダラ) は Image.network で内部的に画像を fetch して
// Canvas にデコードするため、画像サーバーが CORS ヘッダ (Access-Control-Allow-Origin)
// を返さないと表示できない。Google Favicon API / encrypted-tbn0.gstatic.com /
// 各社の独自CDN は CORS ヘッダ無しの場合がほとんど。
//
// 解決策: HtmlElementView で <img> タグを直接埋め込む。
//        <img> はブラウザネイティブなので CORS 不要、何でも表示できる。
//
// Non-Web では brand_logo_stub.dart が代わりに使われる（conditional import）。

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// 同じ viewType を二度 register するとエラーになるため、登録済みを記録。
final Set<String> _registeredTypes = <String>{};

/// Web 用: <img> タグで画像を表示する。
Widget buildWebImage(String url, double size) {
  final viewType = 'brand-logo-${url.hashCode}';
  if (!_registeredTypes.contains(viewType)) {
    _registeredTypes.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final img = html.ImageElement(src: url);
      img.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'cover'
        ..border = 'none'
        ..display = 'block';
      img.draggable = false;
      return img;
    });
  }
  return SizedBox(
    width: size,
    height: size,
    child: HtmlElementView(viewType: viewType),
  );
}
