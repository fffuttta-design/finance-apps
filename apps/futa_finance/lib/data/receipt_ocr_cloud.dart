import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'receipt_ocr.dart';

/// クラウド（Gemini Vision）でレシートを高精度に読み取る版。
///
/// APIキーはビルド時に `--dart-define=GEMINI_API_KEY=...` で注入（gitには載せない）。
/// キーが無い環境（Web の自動ビルド等）では [available] が false になり、UI 側で非表示にする。
class ReceiptOcrCloud {
  ReceiptOcrCloud._();
  static final ReceiptOcrCloud instance = ReceiptOcrCloud._();

  static const _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const _model = 'gemini-2.5-flash';

  /// クラウド読取が使えるか（キーが注入されているか）。
  static bool get available => _apiKey.isNotEmpty;

  /// カテゴリ一覧（大→小）を渡さない場合のプロンプト。
  static String _buildPrompt(Map<String, List<String>>? categories) {
    final catSection = (categories == null || categories.isEmpty)
        ? '  "categoryMajor": 経費の会計科目の推定(消耗品費/会議費/交際費/旅費交通費/通信費/雑費 等から1つ。不明ならnull),\n'
            '  "categorySub": null,'
        : () {
            final lines = categories.entries
                .map((e) =>
                    '    - 「${e.key}」: [${e.value.join(", ")}]')
                .join('\n');
            return '  "categoryMajor": この経費に最も合う大カテゴリ名(下の一覧の「」内の名前を**そのまま**1つ。不明ならnull),\n'
                '  "categorySub": その大カテゴリ内の小カテゴリ名(同じく一覧からそのまま1つ。不明ならnull),\n'
                '  // カテゴリ一覧(大カテゴリ: [小カテゴリ...]):\n$lines';
          }();
    return '''
あなたは日本のレシート読み取りアシスタントです。画像のレシートから以下をJSONで返してください。
{
  "store": 店名(文字列, 不明ならnull),
  "date": 日付("YYYY-MM-DD"形式, 不明ならnull),
  "total": 税込みの合計金額(整数・円, "合計/お会計"の値。値引後の実支払額。不明ならnull),
$catSection
  "items": 購入品目の配列([{"name": 品名, "price": 金額(整数・円)}], レジ袋等も含む。無ければ[])
}
合計は登録番号・電話番号・店コードなどの数字と混同しないこと。categoryMajor/categorySubは必ず一覧の表記と完全一致させること。JSONのみを返すこと。''';
  }

  /// 画像を選択（カメラ/ギャラリー）→ Gemini で解析。
  /// [categories] に大→小カテゴリ一覧を渡すと、その中から大/小を選んで返す。
  Future<ReceiptOcrResult?> captureAndRecognize(
      {required ImageSource source,
      Map<String, List<String>>? categories}) async {
    final prompt = _buildPrompt(categories);
    final picker = ImagePicker();
    // 高速化：解像度・画質をさらに抑えてアップロード/推論を軽くする
    // （レシートの文字は十分読める範囲）。モデルは精度優先で flash 据え置き。
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 55,
      maxWidth: 1024,
    );
    if (xfile == null) return null;

    final bytes = await xfile.readAsBytes();
    final b64 = base64Encode(bytes);
    final mime = xfile.mimeType ??
        (xfile.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg');

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                  {
                    'inline_data': {'mime_type': mime, 'data': b64}
                  },
                ]
              }
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
              // 高速化：2.5 Flash の思考(thinking)を無効化してレイテンシ削減。
              'thinkingConfig': {'thinkingBudget': 0},
            },
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw 'Gemini APIエラー (${resp.statusCode})';
    }

    final body = jsonDecode(utf8.decode(resp.bodyBytes))
        as Map<String, dynamic>;
    final text = (((body['candidates'] as List?)?.first
            as Map<String, dynamic>?)?['content']
                as Map<String, dynamic>?)?['parts'] is List
        ? ((((body['candidates'] as List).first
                    as Map<String, dynamic>)['content']
                as Map<String, dynamic>)['parts'] as List)
            .map((p) => (p as Map<String, dynamic>)['text'] ?? '')
            .join()
        : '';

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      // 念のため JSON 部分だけ抜き出して再試行。
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (m == null) {
        return ReceiptOcrResult(rawText: text);
      }
      parsed = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    }

    final store = (parsed['store'] as String?)?.trim();
    final total = (parsed['total'] as num?)?.toInt();
    final category = (parsed['category'] as String?)?.trim();
    final catMajor = (parsed['categoryMajor'] as String?)?.trim();
    final catSub = (parsed['categorySub'] as String?)?.trim();
    DateTime? date;
    final ds = parsed['date'] as String?;
    if (ds != null) {
      try {
        date = DateTime.parse(ds);
      } catch (_) {}
    }

    // 内訳（品目）→ 構造化リスト＋備考用の要約文字列。
    String? itemsMemo;
    final structured = <ReceiptItem>[];
    final items = parsed['items'];
    if (items is List && items.isNotEmpty) {
      final lines = <String>[];
      for (final it in items) {
        if (it is Map) {
          final n = (it['name'] as String?)?.trim() ?? '';
          final p = (it['price'] as num?)?.toInt();
          if (n.isEmpty) continue;
          lines.add(p != null ? '$n ¥$p' : n);
          if (p != null) structured.add(ReceiptItem(name: n, price: p));
        }
      }
      if (lines.isNotEmpty) itemsMemo = lines.join('\n');
    }

    final majorOut =
        (catMajor != null && catMajor.isNotEmpty) ? catMajor : null;
    final subOut = (catSub != null && catSub.isNotEmpty) ? catSub : null;

    final rawSummary = [
      if (store != null) '店名: $store',
      if (date != null) '日付: ${date.year}/${date.month}/${date.day}',
      if (total != null) '合計: ¥$total',
      if (majorOut != null)
        '科目候補: $majorOut${subOut != null ? ' › $subOut' : ''}',
      if (itemsMemo != null) '内訳:\n$itemsMemo',
    ].join('\n');

    return ReceiptOcrResult(
      rawText: rawSummary.isEmpty ? text : rawSummary,
      amount: total,
      date: date,
      storeName: store,
      memo: itemsMemo,
      items: structured.isEmpty ? null : structured,
      categoryMajor: majorOut,
      categorySub: subOut,
      categoryGuess: (category != null && category.isNotEmpty) ? category : null,
    );
  }
}
