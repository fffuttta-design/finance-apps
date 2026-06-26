/// CSVファイルを選んでバイト列を得る（プラットフォーム別実装の切替）。
///
/// - モバイル/ネイティブ: `file_picker`
/// - Web(Electronデスクトップ含む): ブラウザ標準の `<input type=file>` を直接使用。
///   Electron+Flutter Web では file_picker が結果を返さないことがあるため、確実な
///   ブラウザネイティブ実装に切り替える。
library;

export 'csv_picker_io.dart'
    if (dart.library.js_interop) 'csv_picker_web.dart';
