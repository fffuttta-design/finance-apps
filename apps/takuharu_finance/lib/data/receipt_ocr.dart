import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'categories.dart';

/// レシートの読み取り結果（たくはる用・シンプル）。
class ReceiptResult {
  final int? amount;
  final DateTime? date;
  final String? store;
  final String? category;
  const ReceiptResult({this.amount, this.date, this.store, this.category});
}

/// レシート画像を Gemini で読み取り、合計金額・日付・店名・カテゴリを返す。
///
/// APIキーはビルド時に `--dart-define=GEMINI_API_KEY=...` で注入。
/// キーが無い環境（Web の通常ビルド等）では [available] が false。
class ReceiptOcr {
  ReceiptOcr._();
  static final ReceiptOcr instance = ReceiptOcr._();

  static const _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const _model = 'gemini-2.5-flash';

  static bool get available => _apiKey.isNotEmpty;

  String _prompt() {
    final cats = expenseCategories.map((c) => c.name).join('、');
    return '''このレシート画像を読み取り、次のJSONだけを返してください（説明文・コードフェンス不要）。
{
  "amount": 合計金額の整数（税込・最終支払額。円。数値のみ。読めなければ null）,
  "date": "YYYY-MM-DD（購入日。和暦や「2026年6月5日」も西暦に。読めなければ null）",
  "store": "店名（簡潔に。読めなければ空文字）",
  "category": "次のいずれか1つ: $cats"
}
カテゴリはレシートの内容から最も近いものを上の一覧から必ず選ぶこと。''';
  }

  Future<ReceiptResult?> recognize(Uint8List bytes,
      {String mime = 'image/jpeg'}) async {
    if (!available) return null;
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');
    final reqBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _prompt()},
            {
              'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)}
            },
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
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 429 || attempt >= 2) break;
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
    if (resp.statusCode == 429) {
      throw 'AIが混雑しています（429）。少し待って再試行してください。';
    }
    if (resp.statusCode != 200) {
      throw 'AIエラー（${resp.statusCode}）';
    }

    final body =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    var text = '';
    try {
      final parts = (((body['candidates'] as List).first
          as Map<String, dynamic>)['content']
          as Map<String, dynamic>)['parts'] as List;
      text = parts.map((p) => (p as Map<String, dynamic>)['text'] ?? '').join();
    } catch (_) {}

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (m == null) return const ReceiptResult();
      parsed = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    }

    int? amount;
    final a = parsed['amount'];
    if (a is num) {
      amount = a.toInt();
    } else if (a is String) {
      amount = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    DateTime? date;
    final d = parsed['date'];
    if (d is String && d.isNotEmpty) {
      date = DateTime.tryParse(d);
    }
    final store = (parsed['store'] as String?)?.trim();
    final category = (parsed['category'] as String?)?.trim();

    return ReceiptResult(
      amount: amount,
      date: date,
      store: (store == null || store.isEmpty) ? null : store,
      category: (category == null || category.isEmpty) ? null : category,
    );
  }
}
