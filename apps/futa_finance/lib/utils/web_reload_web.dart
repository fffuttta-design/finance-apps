// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// Web 専用: ブラウザのリロードを実行する。
import 'dart:html' as html;

void reloadApp() => html.window.location.reload();
