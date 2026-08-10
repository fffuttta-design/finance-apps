import 'dart:convert';
import 'dart:typed_data';

import 'package:finance_core/finance_core.dart';
import 'package:http/http.dart' as http;

import 'household_service.dart';

/// レシート記録画面のトグルで「まとめて1件 ⇄ 品目ごと」を切り替えるための
/// センチネル値。画面が pop の戻り値にこれを返すと、フローが反対モードを開き直す。
const String kReceiptSwitchMode = '__switch_record_mode__';

/// レシートの1品目。
class ReceiptItem {
  final String name;
  final int price;
  final String? category;
  const ReceiptItem({required this.name, required this.price, this.category});
}

/// レシートの読み取り結果（たくはる用）。
class ReceiptResult {
  final int? amount;
  final DateTime? date;
  final String? store;
  final String? category;
  final List<ReceiptItem> items;

  /// 水道等の使用量メタ（検針票のとき。無ければ null）。
  final UsageDetail? usage;
  const ReceiptResult({
    this.amount,
    this.date,
    this.store,
    this.category,
    this.items = const [],
    this.usage,
  });
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
    final cats =
        HouseholdService.instance.orderedCategoryNames(income: false).join('、');
    return '''このレシートまたは納品書の画像（イオンネットスーパー等のネットスーパー注文明細を含む）を読み取り、次のJSONだけを返してください（説明文・コードフェンス不要）。
{
  "amount": 合計金額の整数（税込・最終支払額。円。数値のみ。読めなければ null）,
  "date": "YYYY-MM-DD（購入日・注文日。和暦や「2026年6月5日」も西暦に。読めなければ null）",
  "store": "店名（簡潔に。ネットスーパーなら「イオンネットスーパー」等。読めなければ空文字）",
  "category": "レシート全体の代表カテゴリ。次のいずれか1つ: $cats",
  "items": [
    {"name": "品目名（簡潔に）", "price": その品目の金額の整数, "category": "次のいずれか1つ: $cats"}
  ],
  "water": {
    "isWaterBill": true/false（水道・上下水道の検針票/請求書/口座振替収書ならtrue。違えばfalseにしてこのブロックの他は無視）,
    "usage": 今回使用量の数値（m³。例 31。読めなければ null）,
    "prevUsage": 前年同時期の使用量（例 32。無ければ null）,
    "periodFrom": "YYYY-MM-DD（使用期間の開始。和暦→西暦）",
    "periodTo": "YYYY-MM-DD（使用期間の終了。和暦→西暦）",
    "waterCharge": 水道料金の税込額の整数（例 3668。無ければ null）,
    "sewerCharge": 下水道使用料の税込額の整数（例 2887。無ければ null）
  }
}
重要な読み取りルール:
- 水道・上下水道の検針票／請求書／口座振替収書なら water.isWaterBill=true にする。このとき:
  - items は必ず「水道料金」(price=waterCharge) と「下水道使用料」(price=sewerCharge) の2件だけにする（片方しか無ければその1件）。各 category="光熱費"。
  - amount はご請求金額（合計・税込）。store は "水道料金"。
  - water.usage は使用量(m³)であり、消費税額や料金(円)とは絶対に混同しない（135や104のような「指示値」ではなく「今回のご使用量 ①-②+③」の m³ を使う）。
  - 和暦（令和8年＝2026）は西暦に直す。
  - ★用紙が左右2枚に分かれている場合（名古屋市等）：左＝「水道ご使用量のお知らせ / Water Service Statement」＝今回分、右＝「上下水道料金領収書（口座振替払用）」＝前回分の領収書、で金額も期間も違う。必ず**左の「今回ご請求金額」側**の数値だけを使う：waterCharge/sewerCharge・amount（ご請求金額 Total Charge）・usage（今回のご使用量）・prevUsage（《参考》前年同時期のご使用量）・periodFrom/periodTo（ご使用期間）。右側の領収書（振替金額・別期間の使用量）は絶対に混ぜない・使わない。
- 水道でなければ water.isWaterBill=false にする（他フィールドは無視されてよい）。
- 品目の price は「数量込みの金額」を使う。数量が複数の行は単価ではなく『合計』列（単価×数量）の金額を使うこと。
- 外税（税抜）表記の伝票でも、各品目の price は表に記載されたその行の金額をそのまま使う。
- amount（合計金額）は一番下の「合計金額」＝税込の最終支払額を使う（外税表記でも税込総額。配送手数料も含む）。
- items は表に並ぶ商品を漏れなく全て出す（30品以上あっても全部）。配送手数料・送料があれば品目として含めてよい。
- 小計・値引・消費税・合計・お釣りの行は items に入れない。
- カテゴリは必ず上の一覧から最も近いものを選ぶこと。
読み取れなければ items は空配列。''';
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
        // 多品目(30品+)の伝票を取りこぼさないよう、出力上限を大きめに。
        // thinkingは無効化せず少し考えさせて完全性を上げる(長い納品書対策)。
        'maxOutputTokens': 16384,
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
    // 変換マスタ（表記ゆれ辞書）を店名・品目名に適用。
    final hs = HouseholdService.instance;
    final store =
        hs.applyReplacements((parsed['store'] as String?)?.trim() ?? '');
    final category = (parsed['category'] as String?)?.trim();

    final items = <ReceiptItem>[];
    final rawItems = parsed['items'];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is! Map) continue;
        final name =
            hs.applyReplacements((it['name'] as String?)?.trim() ?? '');
        if (name.isEmpty) continue;
        final p = it['price'];
        int price = 0;
        if (p is num) {
          price = p.toInt();
        } else if (p is String) {
          price = int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        }
        final ic = (it['category'] as String?)?.trim();
        items.add(ReceiptItem(
          name: name,
          price: price,
          category: (ic == null || ic.isEmpty) ? null : ic,
        ));
      }
    }

    // 水道検針票の使用量メタ（isWaterBill のときだけ）。
    UsageDetail? usage;
    var effItems = items;
    var effStore = store;
    var effCategory = category;
    final w = parsed['water'];
    if (w is Map && w['isWaterBill'] == true) {
      int? pInt(dynamic v) {
        if (v is num) return v.toInt();
        if (v is String) {
          return int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
        }
        return null;
      }

      double? pDbl(dynamic v) {
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));
        return null;
      }

      DateTime? pDate(dynamic v) =>
          (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

      final usageAmt = pDbl(w['usage']);
      final prevUsage = pDbl(w['prevUsage']);
      final periodFrom = pDate(w['periodFrom']);
      final periodTo = pDate(w['periodTo']);
      if (usageAmt != null || periodFrom != null || periodTo != null) {
        usage = UsageDetail(
          amount: usageAmt,
          unit: 'm3',
          prevAmount: prevUsage,
          periodFrom: periodFrom,
          periodTo: periodTo,
          kind: 'water',
        );
      }

      // items が空でも waterCharge / sewerCharge から2品目を組み立てる（OCRブレ対策）。
      if (effItems.isEmpty) {
        final waterCharge = pInt(w['waterCharge']);
        final sewerCharge = pInt(w['sewerCharge']);
        effItems = <ReceiptItem>[
          if (waterCharge != null && waterCharge > 0)
            ReceiptItem(name: '水道料金', price: waterCharge, category: '光熱費'),
          if (sewerCharge != null && sewerCharge > 0)
            ReceiptItem(name: '下水道使用料', price: sewerCharge, category: '光熱費'),
        ];
      }
      if (effStore.isEmpty) effStore = '水道料金';
      effCategory = (effCategory == null || effCategory.isEmpty)
          ? '光熱費'
          : effCategory;
    }

    return ReceiptResult(
      amount: amount,
      date: date,
      store: effStore.isEmpty ? null : effStore,
      category:
          (effCategory == null || effCategory.isEmpty) ? null : effCategory,
      items: effItems,
      usage: usage,
    );
  }
}
