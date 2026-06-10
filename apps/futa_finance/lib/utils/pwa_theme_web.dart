import 'package:web/web.dart' as web;

/// `meta[name=theme-color]` を書き換えて、インストール済みPWAの
/// タイトルバー色を実行時に変更する（Chromium 系ブラウザで反映される）。
/// 無ければ新規に作って head に追加する。
void setPwaThemeColor(String hexColor) {
  final head = web.document.head;
  if (head == null) return;
  var meta = web.document.querySelector('meta[name="theme-color"]')
      as web.HTMLMetaElement?;
  if (meta == null) {
    meta = web.document.createElement('meta') as web.HTMLMetaElement;
    meta.name = 'theme-color';
    head.appendChild(meta);
  }
  meta.content = hexColor;
}
