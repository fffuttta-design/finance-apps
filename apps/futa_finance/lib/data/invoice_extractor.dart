import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 請求書PDF 1枚から Gemini が抽出した内容。
class InvoiceExtract {
  /// 売上(自社が発行した請求＝入金/収入)らしいと推定したら true、
  /// 支払・外注(他社からの請求＝支出)らしければ false。
  /// あくまで推定値。プレビュー画面でユーザーが種別を上書きできる。
  final bool isSalesGuess;

  /// 発行元（請求する側）の会社名。
  final String? issuer;

  /// 宛先（請求される側）の会社名。
  final String? billedTo;

  /// 請求日 / 発行日。
  final DateTime? date;

  /// 税込合計金額（円）。
  final int? total;

  /// 品目・摘要の要約（備考や取引内容用）。
  final String? summary;

  /// 支出の場合の会計科目候補（大カテゴリ名。一覧から1つ）。
  final String? categoryMajor;

  /// 解析できなかった場合などの生テキスト（デバッグ/確認用）。
  final String? rawText;

  const InvoiceExtract({
    this.isSalesGuess = false,
    this.issuer,
    this.billedTo,
    this.date,
    this.total,
    this.summary,
    this.categoryMajor,
    this.rawText,
  });

  /// 金額も取引先も取れなかった＝実質失敗。
  bool get isEmpty =>
      total == null &&
      (issuer == null || issuer!.trim().isEmpty) &&
      (billedTo == null || billedTo!.trim().isEmpty);
}

/// クラウド（Gemini）で請求書PDFを読み取るサービス。
///
/// Gemini は PDF を直接（スキャンPDFも）読めるので、PDFバイトをそのまま
/// inline_data で送って構造化抽出する。
/// APIキーはビルド時に `--dart-define=GEMINI_API_KEY=...` で注入（gitには載せない）。
/// キーが無い環境（Web の自動ビルド等）では [available] が false。
class InvoiceExtractor {
  InvoiceExtractor._();
  static final InvoiceExtractor instance = InvoiceExtractor._();

  static const _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const _model = 'gemini-2.5-flash';

  /// クラウド読取が使えるか（キーが注入されているか）。
  static bool get available => _apiKey.isNotEmpty;

  static String _buildPrompt(List<String>? expenseCategories) {
    final catLine = (expenseCategories == null || expenseCategories.isEmpty)
        ? '  "categoryMajor": 支出(支払/外注)の場合の会計科目の推定(外注費/仕入/支払報酬/広告宣伝費/通信費/消耗品費 等から1つ。売上なら不要でnull),'
        : '  "categoryMajor": 支出(支払/外注)の場合の会計科目(下の候補から**そのまま**1つ選ぶ。売上ならnull),\n'
            '  // 会計科目の候補: [${expenseCategories.join(", ")}]';
    return '''
あなたは日本の請求書(インボイス)読み取りアシスタントです。PDFの請求書から以下をJSONで返してください。
{
  "isSales": この請求書が「売上(自社が顧客に発行し入金される側)」ならtrue、「支払・外注(他社/外注先から自社が請求され支払う側)」ならfalse(boolean),
  "issuer": 発行元(請求する側)の会社名・氏名(文字列, 不明ならnull),
  "billedTo": 宛先(請求される側=「御中」「様」が付く相手)の会社名・氏名(文字列, 不明ならnull),
  "date": 請求日または発行日("YYYY-MM-DD"形式, 不明ならnull),
  "total": 税込みの合計請求金額(整数・円, "ご請求金額/合計/お支払金額"の最終値。不明ならnull),
  "summary": 品目・摘要の簡潔な要約(文字列。例「3月分 動画編集外注費」。無ければnull),
$catLine
  "items": 明細品目の配列([{"name": 品名, "amount": 金額(税込,整数円)}], 無ければ[])
}
- isSales の判定: 発行元(請求する側)が外注先・業者で、自社がそれを支払うなら false(支出)。自社が発行し顧客に請求しているなら true(売上)。
- total は登録番号(インボイスのT番号)・電話番号・口座番号などの数字と混同しないこと。
- categoryMajor は候補がある場合は必ずその表記と完全一致させること。
- JSONのみを返すこと。''';
  }

  /// 請求書PDFのバイト列を Gemini で解析する。
  /// [expenseCategories] に支出の会計科目候補（大カテゴリ名）を渡すと、
  /// 支出時の科目をその中から選んで返す。
  Future<InvoiceExtract> extract(
    Uint8List pdfBytes, {
    List<String>? expenseCategories,
  }) async {
    final prompt = _buildPrompt(expenseCategories);
    final b64 = base64Encode(pdfBytes);

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');
    final reqBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'application/pdf', 'data': b64}
            },
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    // 429(混雑/レート上限)は短い待機を挟んで自動リトライ（最大3回）。
    late http.Response resp;
    for (var attempt = 0;; attempt++) {
      resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: reqBody)
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 429 || attempt >= 2) break;
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }

    if (resp.statusCode == 429) {
      throw 'Geminiが混雑/利用上限(429)です。少し時間をおいて再試行してください'
          '（無料枠の1分/1日あたりの上限の可能性）';
    }
    if (resp.statusCode != 200) {
      throw 'Gemini APIエラー (${resp.statusCode})';
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

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (m == null) {
        return InvoiceExtract(rawText: text);
      }
      parsed = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    }

    String? str(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    DateTime? date;
    final ds = parsed['date'] as String?;
    if (ds != null) {
      try {
        date = DateTime.parse(ds);
      } catch (_) {}
    }

    // 明細 → 要約に補う（summary が無ければ items から作る）。
    String? summary = str(parsed['summary']);
    final items = parsed['items'];
    if (summary == null && items is List && items.isNotEmpty) {
      final lines = <String>[];
      for (final it in items) {
        if (it is Map) {
          final n = str(it['name']);
          final a = (it['amount'] as num?)?.toInt();
          if (n == null) continue;
          lines.add(a != null ? '$n ¥$a' : n);
        }
      }
      if (lines.isNotEmpty) summary = lines.join(' / ');
    }

    return InvoiceExtract(
      isSalesGuess: parsed['isSales'] == true,
      issuer: str(parsed['issuer']),
      billedTo: str(parsed['billedTo']),
      date: date,
      total: (parsed['total'] as num?)?.toInt(),
      summary: summary,
      categoryMajor: str(parsed['categoryMajor']),
      rawText: text,
    );
  }
}
