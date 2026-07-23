import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// AI（Claude API）の使用量を読むリポジトリ。
///
/// 🔥 なぜアプリ側で集計しないのか
/// Anthropic の公式使用量API（Admin API）は**個人アカウントでは鍵を発行できない**
/// （`platform.claude.com/settings/admin-keys` が404）。そのため各アプリが呼び出しのたびに
/// 二村秘書VPSへ自己申告し、VPSが集計して Firestore に書いたものをここで読むだけにしている。
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
  /// ⚠️ Claude Max（月額サブスク）は API 課金ではないので**別扱い**にする。
  /// 混ぜると「APIが高い」と誤読するため、`subscriptions` と `charges` に分けて返す。
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
      if (!label.contains('anthropic') && !label.contains('claude')) continue;
      final p = AiPurchase(
        date: DateTime.tryParse((m['date'] ?? '') as String? ?? '') ?? from,
        amountJpy: _i(m['amount']),
        usd: _usdInMemo((m['memo'] as String?) ?? ''),
        label: ((m['store'] as String?)?.isNotEmpty ?? false)
            ? m['store'] as String
            : ((m['description'] ?? '') as String),
      );
      (_isSubscription(m, label) ? subs : charges).add(p);
    }
    charges.sort((a, b) => a.date.compareTo(b.date));
    subs.sort((a, b) => a.date.compareTo(b.date));
    return AiPurchases(charges: charges, subscriptions: subs);
  }

  /// Anthropicへの支払いが「Claude Max（月額サブスク）」か「APIクレジット購入」かを判定する。
  ///
  /// 🔥 実データはどちらも store="Anthropic" / description="Claude API利用料（Anthropic）" で
  /// **文言では区別できない**。実際に効く手がかりは2つ:
  ///   1. memo の請求書番号の系列 … `Z8OT9YXC****` = APIクレジットの都度購入
  ///   2. memo の USD 金額 … サブスクは $100/$200 クラス、クレジット購入は $5〜$20 程度
  /// 2つとも無いときだけ、店名・摘要のキーワードで拾う。
  static bool _isSubscription(Map<String, dynamic> m, String label) {
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
  final DateTime? updatedAt;

  const AiUsageMonth({
    required this.month,
    required this.rate,
    required this.total,
    required this.apps,
    required this.models,
    required this.daily,
    this.updatedAt,
  });

  factory AiUsageMonth.fromJson(Map<String, dynamic> j) => AiUsageMonth(
        month: (j['month'] ?? '') as String,
        rate: _d(j['rate']),
        total: AiUsageTotals.fromJson(
            (j['total'] as Map?)?.cast<String, dynamic>() ?? const {}),
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
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String? ?? ''),
      );
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

  const AiUsageApp({
    required this.id,
    required this.name,
    required this.totals,
    required this.models,
  });

  factory AiUsageApp.fromJson(Map<String, dynamic> j) => AiUsageApp(
        id: (j['app'] ?? '') as String,
        name: (j['name'] ?? j['app'] ?? '') as String,
        totals: AiUsageTotals.fromJson(j),
        models: ((j['models'] as List?) ?? const [])
            .map((e) =>
                AiUsageModel.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class AiUsageModel {
  final String model;
  final AiUsageTotals totals;

  const AiUsageModel({required this.model, required this.totals});

  factory AiUsageModel.fromJson(Map<String, dynamic> j) => AiUsageModel(
        model: (j['model'] ?? '') as String,
        totals: AiUsageTotals.fromJson(j),
      );
}

class AiUsageDay {
  final String date; // YYYY-MM-DD
  final double usd;
  final double jpy;

  const AiUsageDay({required this.date, required this.usd, required this.jpy});

  factory AiUsageDay.fromJson(Map<String, dynamic> j) => AiUsageDay(
        date: (j['d'] ?? '') as String,
        usd: _d(j['usd']),
        jpy: _d(j['jpy']),
      );
}

/// Anthropic への支払い1件。
class AiPurchase {
  final DateTime date;
  final int amountJpy;
  final String label;

  /// 請求時のUSD額（メモから拾えたときだけ。0なら不明）。
  final double usd;

  const AiPurchase({
    required this.date,
    required this.amountJpy,
    required this.label,
    this.usd = 0,
  });
}

/// メモに埋まっている "$214.73 USD" のような表記からUSD額を拾う。
double _usdInMemo(String memo) {
  final m = RegExp(r'\$\s*([0-9]+(?:\.[0-9]+)?)\s*USD').firstMatch(memo);
  return double.tryParse(m?.group(1) ?? '') ?? 0;
}

/// 月内の Anthropic 支払い。API のクレジット購入とサブスクを分けて持つ。
class AiPurchases {
  final List<AiPurchase> charges;       // API のクレジット購入（変動費）
  final List<AiPurchase> subscriptions; // Claude Max などの月額（固定費）

  const AiPurchases({required this.charges, required this.subscriptions});

  int get chargeTotal =>
      charges.fold(0, (a, b) => a + b.amountJpy);
  int get subscriptionTotal =>
      subscriptions.fold(0, (a, b) => a + b.amountJpy);
}

int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
double _d(dynamic v) => v is double ? v : (v is num ? v.toDouble() : 0);
