import 'dart:convert';

import 'package:http/http.dart' as http;

/// 店名から会計科目（大カテゴリ／小カテゴリ）を **まとめて1回のAPI呼び出しで** 推定する。
///
/// クレカ明細CSVの取り込みなど、店名だけが分かっていてカテゴリを自動で付けたい場面で使う。
/// APIキーはビルド時に `--dart-define=GEMINI_API_KEY=...` で注入（gitには載せない）。
class StoreCategoryClassifier {
  StoreCategoryClassifier._();
  static final StoreCategoryClassifier instance = StoreCategoryClassifier._();

  static const _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const _model = 'gemini-2.5-flash';

  static bool get available => _apiKey.isNotEmpty;

  /// [stores]（店名/利用先のリスト）それぞれに対し `{major, sub}` を推定して返す。
  /// 戻り値は [stores] と同じ順・同じ件数。推定できなかった要素は null。
  /// [categories] は「大カテゴリ名 → 小カテゴリ名リスト」。
  Future<List<Map<String, String>?>> classify(
    List<String> stores,
    Map<String, List<String>> categories,
  ) async {
    if (stores.isEmpty) return [];
    if (!available || categories.isEmpty) {
      return List<Map<String, String>?>.filled(stores.length, null);
    }

    final catLines = categories.entries
        .map((e) => '  - 「${e.key}」: [${e.value.join(", ")}]')
        .join('\n');
    final storeLines = [
      for (var i = 0; i < stores.length; i++) '  $i: ${stores[i]}'
    ].join('\n');

    final prompt = '''
あなたは日本の経費仕訳アシスタントです。クレジットカード明細の利用先(店名)ごとに、最も適切な会計科目を下の候補から選んでください。
出力は次の形のJSON配列のみ:
[{"i": 行番号(整数), "major": 大カテゴリ名(候補の「」内からそのまま), "sub": 小カテゴリ名(同じ大カテゴリ内の候補からそのまま。無ければ"")}]
- major は必ず候補の大カテゴリ名と完全一致させること。判断できない時は最も無難な科目を選ぶ。
- すべての行番号(0〜${stores.length - 1})について1つずつ返すこと。

# 会計科目の候補(大カテゴリ: [小カテゴリ...]):
$catLines

# 利用先(行番号: 店名):
$storeLines
''';

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');
    final reqBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    late http.Response resp;
    for (var attempt = 0;; attempt++) {
      resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: reqBody)
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 429 || attempt >= 2) break;
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
    if (resp.statusCode != 200) {
      // 失敗時は全て null（呼び出し側で「未分類」にフォールバック）。
      return List<Map<String, String>?>.filled(stores.length, null);
    }

    final body =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final candidates = body['candidates'] as List?;
    final text = (candidates != null && candidates.isNotEmpty)
        ? ((((candidates.first as Map<String, dynamic>)['content']
                    as Map<String, dynamic>?)?['parts'] as List?)
                ?.map((p) => (p as Map<String, dynamic>)['text'] ?? '')
                .join() ??
            '')
        : '';

    List<dynamic> arr;
    try {
      arr = jsonDecode(text) as List<dynamic>;
    } catch (_) {
      final m = RegExp(r'\[[\s\S]*\]').firstMatch(text);
      if (m == null) {
        return List<Map<String, String>?>.filled(stores.length, null);
      }
      try {
        arr = jsonDecode(m.group(0)!) as List<dynamic>;
      } catch (_) {
        return List<Map<String, String>?>.filled(stores.length, null);
      }
    }

    final out = List<Map<String, String>?>.filled(stores.length, null);
    for (final e in arr) {
      if (e is! Map) continue;
      final i = (e['i'] as num?)?.toInt();
      if (i == null || i < 0 || i >= stores.length) continue;
      final major = (e['major'] as String?)?.trim() ?? '';
      if (major.isEmpty) continue;
      // major が候補に無ければ採用しない（表記ゆれ防止）。
      if (!categories.containsKey(major)) continue;
      final sub = (e['sub'] as String?)?.trim() ?? '';
      final validSub =
          (sub.isNotEmpty && (categories[major]?.contains(sub) ?? false))
              ? sub
              : '';
      out[i] = {'major': major, 'sub': validSub};
    }
    return out;
  }
}
