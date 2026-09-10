import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// AI（Claude / ChatGPT …）のAPI使用量を読むリポジトリ。
///
/// 🔥 なぜアプリ側で集計しないのか
/// Anthropic の公式使用量API（Admin API）は**個人アカウントでは鍵を発行できない**
/// （`platform.claude.com/settings/admin-keys` が404）。そのため各アプリが呼び出しのたびに
/// 二村秘書VPSへ自己申告し、VPSが集計して Firestore に書いたものをここで読むだけにしている。
///
/// 🔥 **どのAIかは「モデル名」で仕分けされる**（2026-09-10〜）。集計する器には列を足していないので、
/// 過去に貯めた分もそのまま Claude / ChatGPT に分かれる。仕分けの実体はVPS側（`core/finance/usage`）。
///
/// 読み取り元: `users/{uid}/aiUsage/{YYYY-MM}` の `json` フィールド（文字列）
/// 書き込み元: 二村秘書VPS `core/ai_usage_sync.py`（10分おき）
class AiUsageRepository {
  AiUsageRepository._();
  static final AiUsageRepository instance = AiUsageRepository._();

  String? _uid;

  void useFirestore(String uid) => _uid = uid;
  void useLocal() => _uid = null;

  bool get available => _uid != null;

  static String monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// 指定月の「クレジット購入（チャージ）」を FutaFinance の取引から拾う。
  ///
  /// ⚠️ Claude Max / ChatGPT Plus（月額サブスク）は API 課金ではないので**別扱い**にする。
  /// 混ぜると「APIが高い」と誤読するため、`subscriptions` と `charges` に分けて返す。
  ///
  /// 🔥 支払い先（Claude / ChatGPT）も分ける。**財布が別だから**＝どちらにいくら払ったかは
  /// 合算されると分からなくなる。
  Future<AiPurchases> fetchPurchases(DateTime month) async {
    final uid = _uid;
    if (uid == null) return const AiPurchases(charges: [], subscriptions: []);
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 1);
    // ⚠️ mode と date の2条件を同時に where すると Firestore の**複合インデックス**が要る。
    //    未作成だと例外になり、画面が読み込み中のまま止まる（実際に踏んだ）。
    //    date だけで絞って mode はアプリ側で判定する＝単一フィールドの既定インデックスで済む。
    final snap = await FirebaseFirestore.instance
        .collection('users/$uid/transactions')
        .where('date',
            isGreaterThanOrEqualTo: from.toIso8601String(),
            isLessThan: to.toIso8601String())
        .get();

    final charges = <AiPurchase>[];
    final subs = <AiPurchase>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (m['mode'] != 'business') continue;
      final label = '${m['store'] ?? ''} ${m['description'] ?? ''}'.toLowerCase();
      final vendor = vendorOfLabel(label);
      if (vendor == null) continue;
      final p = AiPurchase(
        date: DateTime.tryParse((m['date'] ?? '') as String? ?? '') ?? from,
        amountJpy: _i(m['amount']),
        usd: _usdInMemo((m['memo'] as String?) ?? ''),
        label: ((m['store'] as String?)?.isNotEmpty ?? false)
            ? m['store'] as String
            : ((m['description'] ?? '') as String),
        vendor: vendor,
      );
      (_isSubscription(vendor, m, label) ? subs : charges).add(p);
    }
    charges.sort((a, b) => a.date.compareTo(b.date));
    subs.sort((a, b) => a.date.compareTo(b.date));
    return AiPurchases(charges: charges, subscriptions: subs);
  }

  /// 取引の店名・摘要から「どのAIへの支払いか」を判定する（AIと無関係なら null）。
  static String? vendorOfLabel(String label) {
    if (label.contains('anthropic') || label.contains('claude')) return 'claude';
    if (label.contains('openai') || label.contains('chatgpt')) return 'openai';
    if (label.contains('gemini')) return 'gemini';
    return null;
  }

  /// その支払いが「月額サブスク」か「APIクレジット購入」かを判定する。
  ///
  /// 🔥 Claude側の実データはどちらも store="Anthropic" / description="Claude API利用料（Anthropic）" で
  /// **文言では区別できない**。実際に効く手がかりは2つ:
  ///   1. memo の請求書番号の系列 … `Z8OT9YXC****` = APIクレジットの都度購入
  ///   2. memo の USD 金額 … サブスクは $100/$200 クラス、クレジット購入は $5〜$20 程度
  /// 2つとも無いときだけ、店名・摘要のキーワードで拾う。
  ///
  /// 🔥 ChatGPT側は逆に**文言で分かる**（ChatGPT Plus は $20 固定、APIクレジット購入も$5〜と
  /// 金額が近く、Claudeの「$100で切る」手が効かないため）:
  ///   store="OpenAI" / 摘要に "OpenAI API" → クレジット購入 ／ "ChatGPT" → 月額プラン
  static bool _isSubscription(String vendor, Map<String, dynamic> m, String label) {
    if (vendor == 'openai') {
      if (label.contains('openai api') || label.contains('api利用料')) return false;
      if (label.contains('chatgpt')) return true;
      return m['isFixed'] == true;
    }
    if (label.contains('max') || label.contains('サブスク')) return true;
    final memo = (m['memo'] as String?) ?? '';
    // ① 請求書番号の系列で判定（APIクレジット購入の系列なら確定でサブスクではない）
    if (memo.contains('Z8OT9YXC')) return false;
    // ② memo に埋まっている USD 額（例 "$214.73 USD"）で判定
    final usd = RegExp(r'\$\s*([0-9]+(?:\.[0-9]+)?)\s*USD').firstMatch(memo);
    if (usd != null) {
      final v = double.tryParse(usd.group(1) ?? '') ?? 0;
      if (v >= 100) return true;   // $100超はサブスク（クレジット購入は毎回$20未満）
      return false;
    }
    // ③ 手がかりが無ければ固定費フラグと金額で最後の判断
    if (m['isFixed'] == true) return true;
    return ((m['amount'] as num?)?.toInt() ?? 0) >= 15000;
  }

  /// 指定月の使用量サマリを取得する。未計測・未同期なら null。
  Future<AiUsageMonth?> fetch(DateTime month) async {
    final uid = _uid;
    if (uid == null) return null;
    final key = monthKey(month);
    final doc = await FirebaseFirestore.instance
        .doc('users/$uid/aiUsage/$key')
        .get();
    if (!doc.exists) return null;
    final raw = (doc.data() ?? const {})['json'];
    if (raw is! String || raw.isEmpty) return null;
    try {
      return AiUsageMonth.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// 1か月分の使用量サマリ。
class AiUsageMonth {
  final String month;

  /// USD→JPY の換算レート（VPS側の設定値）。
  final double rate;
  final AiUsageTotals total;
  final List<AiUsageApp> apps;
  final List<AiUsageModel> models;
  final List<AiUsageDay> daily;

  /// AI別（Claude / ChatGPT …）の内訳。消費の多い順。
  /// ⚠️ 古い月のデータ（AI別対応より前に書かれたもの）には入っていないので**空**になる。
  final List<AiUsageVendor> vendors;
  final DateTime? updatedAt;

  const AiUsageMonth({
    required this.month,
    required this.rate,
    required this.total,
    required this.apps,
    required this.models,
    required this.daily,
    this.vendors = const [],
    this.updatedAt,
  });

  factory AiUsageMonth.fromJson(Map<String, dynamic> j) => AiUsageMonth(
        month: (j['month'] ?? '') as String,
        rate: _d(j['rate']),
        total: AiUsageTotals.fromJson(
            (j['total'] as Map?)?.cast<String, dynamic>() ?? const {}),
        vendors: AiUsageVendor.listFrom(j['vendors']),
        apps: ((j['apps'] as List?) ?? const [])
            .map((e) => AiUsageApp.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        models: ((j['models'] as List?) ?? const [])
            .map((e) =>
                AiUsageModel.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        daily: ((j['daily'] as List?) ?? const [])
            .map((e) => AiUsageDay.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        // ⚠️ VPS側は `updated_at`（スネークケース）で書く。両方受ける。
        updatedAt: DateTime.tryParse(
            (j['updatedAt'] ?? j['updated_at'] ?? '') as String? ?? ''),
      );
}

/// AI別（Claude / ChatGPT …）の1まとまり。
class AiUsageVendor {
  /// 内部の符号（claude / openai / gemini / other）
  final String id;

  /// 画面に出す呼び名（Claude / ChatGPT …）。VPS側が付けてくる。
  final String name;
  final AiUsageTotals totals;

  const AiUsageVendor({
    required this.id,
    required this.name,
    required this.totals,
  });

  factory AiUsageVendor.fromJson(Map<String, dynamic> j) => AiUsageVendor(
        id: (j['vendor'] ?? '') as String,
        name: (j['name'] ?? j['vendor'] ?? '') as String,
        totals: AiUsageTotals.fromJson(j),
      );

  static List<AiUsageVendor> listFrom(dynamic v) =>
      ((v as List?) ?? const [])
          .map((e) => AiUsageVendor.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
}

class AiUsageTotals {
  final int calls;
  final int inTok;
  final int outTok;
  final int cacheWrite;
  final int cacheRead;
  final double usd;
  final double jpy;

  const AiUsageTotals({
    required this.calls,
    required this.inTok,
    required this.outTok,
    required this.cacheWrite,
    required this.cacheRead,
    required this.usd,
    required this.jpy,
  });

  int get totalTokens => inTok + outTok + cacheWrite + cacheRead;

  /// キャッシュ読み取りが入力全体に占める割合（＝節約できている度合い）。
  double get cacheHitRatio {
    final base = inTok + cacheRead;
    return base == 0 ? 0 : cacheRead / base;
  }

  factory AiUsageTotals.fromJson(Map<String, dynamic> j) => AiUsageTotals(
        calls: _i(j['n']),
        inTok: _i(j['i']),
        outTok: _i(j['o']),
        cacheWrite: _i(j['cw']),
        cacheRead: _i(j['cr']),
        usd: _d(j['usd']),
        jpy: _d(j['jpy']),
      );
}

class AiUsageApp {
  /// アプリID（＝Anthropic Console の APIキー名と揃えてある）
  final String id;
  final String name;
  final AiUsageTotals totals;
  final List<AiUsageModel> models;

  /// そのツールの中でのAI別内訳（1つのツールがClaudeとGPTを両方使うことがある）。
  final List<AiUsageVendor> vendors;

  const AiUsageApp({
    required this.id,
    required this.name,
    required this.totals,
    required this.models,
    this.vendors = const [],
  });

  factory AiUsageApp.fromJson(Map<String, dynamic> j) => AiUsageApp(
        id: (j['app'] ?? '') as String,
        name: (j['name'] ?? j['app'] ?? '') as String,
        totals: AiUsageTotals.fromJson(j),
        vendors: AiUsageVendor.listFrom(j['vendors']),
        models: ((j['models'] as List?) ?? const [])
            .map((e) =>
                AiUsageModel.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class AiUsageModel {
  final String model;
  final AiUsageTotals totals;

  /// どのAIのモデルか（claude / openai / …）。
  final String vendor;

  /// 単価が**推定**か（＝VPS側の単価表にこのモデルが無い）。
  /// 🔥 true が出たら単価表に足しどき。放っておくと金額がズレたままになる。
  final bool estimated;

  const AiUsageModel({
    required this.model,
    required this.totals,
    this.vendor = '',
    this.estimated = false,
  });

  factory AiUsageModel.fromJson(Map<String, dynamic> j) => AiUsageModel(
        model: (j['model'] ?? '') as String,
        totals: AiUsageTotals.fromJson(j),
        vendor: (j['vendor'] ?? '') as String,
        estimated: j['est'] == true,
      );
}

class AiUsageDay {
  final String date; // YYYY-MM-DD
  final double usd;
  final double jpy;

  /// その日の合計（呼び出し回数・トークン数）。
  final AiUsageTotals total;

  /// その日の「アプリ別」内訳（消費の多い順）。日付×アプリの使用履歴に使う。
  final List<AiUsageApp> apps;

  const AiUsageDay({
    required this.date,
    required this.usd,
    required this.jpy,
    required this.total,
    required this.apps,
  });

  factory AiUsageDay.fromJson(Map<String, dynamic> j) => AiUsageDay(
        date: (j['d'] ?? '') as String,
        usd: _d(j['usd']),
        jpy: _d(j['jpy']),
        total: AiUsageTotals.fromJson(j),
        apps: ((j['apps'] as List?) ?? const [])
            .map((e) => AiUsageApp.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// AI（Claude / ChatGPT …）への支払い1件。
class AiPurchase {
  final DateTime date;
  final int amountJpy;
  final String label;

  /// 請求時のUSD額（メモから拾えたときだけ。0なら不明）。
  final double usd;

  /// 支払い先（claude / openai / …）。
  final String vendor;

  const AiPurchase({
    required this.date,
    required this.amountJpy,
    required this.label,
    this.usd = 0,
    this.vendor = 'claude',
  });
}

/// メモに埋まっている "$214.73 USD" のような表記からUSD額を拾う。
double _usdInMemo(String memo) {
  final m = RegExp(r'\$\s*([0-9]+(?:\.[0-9]+)?)\s*USD').firstMatch(memo);
  return double.tryParse(m?.group(1) ?? '') ?? 0;
}

/// 月内のAIへの支払い。API のクレジット購入とサブスクを分けて持つ。
class AiPurchases {
  final List<AiPurchase> charges;       // API のクレジット購入（変動費）
  final List<AiPurchase> subscriptions; // Claude Max / ChatGPT Plus などの月額（固定費）

  const AiPurchases({required this.charges, required this.subscriptions});

  int get chargeTotal =>
      charges.fold(0, (a, b) => a + b.amountJpy);
  int get subscriptionTotal =>
      subscriptions.fold(0, (a, b) => a + b.amountJpy);

  /// 支払いのあったAIを、金額の多い順に返す。
  List<String> get vendors {
    final sum = <String, int>{};
    for (final p in [...charges, ...subscriptions]) {
      sum[p.vendor] = (sum[p.vendor] ?? 0) + p.amountJpy;
    }
    final keys = sum.keys.toList()
      ..sort((a, b) => (sum[b] ?? 0).compareTo(sum[a] ?? 0));
    return keys;
  }

  List<AiPurchase> chargesOf(String vendor) =>
      charges.where((p) => p.vendor == vendor).toList();
  List<AiPurchase> subscriptionsOf(String vendor) =>
      subscriptions.where((p) => p.vendor == vendor).toList();

  int chargeTotalOf(String v) =>
      chargesOf(v).fold(0, (a, b) => a + b.amountJpy);
  int subscriptionTotalOf(String v) =>
      subscriptionsOf(v).fold(0, (a, b) => a + b.amountJpy);
  double chargeUsdOf(String v) =>
      chargesOf(v).fold(0, (a, b) => a + b.usd);
  double subscriptionUsdOf(String v) =>
      subscriptionsOf(v).fold(0, (a, b) => a + b.usd);
}

/// 支払い先の呼び名。使用量側（VPSが付けてくる name）と揃える。
String aiVendorName(String vendor) => const {
      'claude': 'Claude',
      'openai': 'ChatGPT',
      'gemini': 'Gemini',
      'other': 'その他',
    }[vendor] ??
    vendor;

/// サブスクの呼び名（AIごとにプラン名が違う）。
String aiSubscriptionName(String vendor) => const {
      'claude': 'Claude Max サブスク',
      'openai': 'ChatGPT Plus サブスク',
    }[vendor] ??
    '月額サブスク';

int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
double _d(dynamic v) => v is double ? v : (v is num ? v.toDouble() : 0);
