// PWA（Web）のタイトルバー色（theme-color メタ）を実行時に切り替える。
// 事業=グレー / 個人=オレンジ のように、モードでブラウザ枠の色を出し分ける。
// 非Web（Android 等）では何もしない（条件付きインポートでスタブに切替）。
export 'pwa_theme_stub.dart'
    if (dart.library.js_interop) 'pwa_theme_web.dart';
