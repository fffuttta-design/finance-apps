import 'package:flutter/material.dart';

import '../data/ai_usage_repository.dart';

/// Claude API の使用量（どのツールがいくら使ったか）を見る画面。
///
/// 🔥 数字の出どころ
/// - **消費**: 各アプリが呼び出しのたびに二村秘書VPSへ自己申告 → VPSが集計 → Firestore
///   （Anthropicの公式使用量APIは個人アカウントでは鍵が発行できないため自前方式）
///   ＝ トークン数 × 公式単価 の**概算**。Console の実額とは数%ずれる。
/// - **購入**: FutaFinance の事業取引そのもの（クレカ引き落とし）＝**実額**。
class AiUsageScreen extends StatefulWidget {
  const AiUsageScreen({super.key});

  @override
  State<AiUsageScreen> createState() => _AiUsageScreenState();
}

class _AiUsageScreenState extends State<AiUsageScreen> {
  late DateTime _month;
  AiUsageMonth? _usage;
  AiPurchases? _purchases;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = AiUsageRepository.instance;
    final u = await repo.fetch(_month);
    final p = await repo.fetchPurchases(_month);
    if (!mounted) return;
    setState(() {
      _usage = u;
      _purchases = p;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API使用量'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            _monthSwitcher(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _summaryCard(),
              const SizedBox(height: 12),
              _appRankingCard(),
              const SizedBox(height: 12),
              _modelCard(),
              const SizedBox(height: 12),
              _dailyCard(),
              const SizedBox(height: 12),
              _purchaseCard(),
              const SizedBox(height: 12),
              _footnote(),
            ],
          ],
        ),
      ),
    );
  }

  // ── パーツ ───────────────────────────────────────────────

  Widget _monthSwitcher() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${_month.year}年${_month.month}月',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        IconButton(
          onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _card({required String title, IconData? icon, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                ],
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final u = _usage;
    final p = _purchases;
    final spentJpy = u?.total.jpy ?? 0;
    final spentUsd = u?.total.usd ?? 0;
    final chargedJpy = p?.chargeTotal ?? 0;
    final subJpy = p?.subscriptionTotal ?? 0;

    return _card(
      title: '今月のまとめ',
      icon: Icons.query_stats,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('使った額（概算）  ',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text('¥${_fmt(spentJpy)}',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('(\$${spentUsd.toStringAsFixed(2)})',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),
          _kv('クレジット購入（実額）', '¥${_fmt(chargedJpy.toDouble())}',
              note: 'カードから実際に引き落とされた額'),
          _kv('呼び出し回数', '${_fmt((u?.total.calls ?? 0).toDouble())} 回'),
          _kv('トークン合計', _fmt((u?.total.totalTokens ?? 0).toDouble())),
          if ((u?.total.cacheRead ?? 0) > 0)
            _kv('キャッシュ節約率',
                '${((u!.total.cacheHitRatio) * 100).toStringAsFixed(1)}%',
                note: '入力のうちキャッシュから読めた割合（高いほど安い）'),
          if (subJpy > 0) ...[
            const Divider(height: 24),
            _kv('Claude サブスク（別枠）', '¥${_fmt(subJpy.toDouble())}',
                note: '月額プラン。API課金ではないので上の金額には含めていない'),
          ],
        ],
      ),
    );
  }

  Widget _appRankingCard() {
    final apps = _usage?.apps ?? const <AiUsageApp>[];
    if (apps.isEmpty) {
      return _card(
        title: 'ツール別ランキング',
        icon: Icons.leaderboard_outlined,
        child: _empty(),
      );
    }
    final max = apps.first.totals.jpy;
    final total = _usage?.total.jpy ?? 0;
    return _card(
      title: 'ツール別ランキング',
      icon: Icons.leaderboard_outlined,
      child: Column(
        children: [
          for (final a in apps)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(a.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('¥${_fmt(a.totals.jpy)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          total > 0
                              ? '${(a.totals.jpy / total * 100).toStringAsFixed(0)}%'
                              : '-',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _bar(max <= 0 ? 0 : a.totals.jpy / max),
                  const SizedBox(height: 2),
                  Text('${_fmt(a.totals.calls.toDouble())}回',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _modelCard() {
    final models = _usage?.models ?? const <AiUsageModel>[];
    if (models.isEmpty) {
      return _card(
          title: 'モデル別', icon: Icons.memory_outlined, child: _empty());
    }
    final total = _usage?.total.jpy ?? 0;
    return _card(
      title: 'モデル別',
      icon: Icons.memory_outlined,
      child: Column(
        children: [
          for (final m in models)
            _kv(m.model.isEmpty ? '(不明)' : m.model, '¥${_fmt(m.totals.jpy)}',
                note: total > 0
                    ? '${(m.totals.jpy / total * 100).toStringAsFixed(0)}% / ${_fmt(m.totals.calls.toDouble())}回'
                    : null),
        ],
      ),
    );
  }

  Widget _dailyCard() {
    final daily = _usage?.daily ?? const <AiUsageDay>[];
    if (daily.isEmpty) {
      return _card(
          title: '日別の推移', icon: Icons.show_chart, child: _empty());
    }
    final max = daily.fold<double>(0, (a, b) => b.jpy > a ? b.jpy : a);
    return _card(
      title: '日別の推移',
      icon: Icons.show_chart,
      child: SizedBox(
        height: 120,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in daily)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('¥${d.jpy.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 9)),
                      const SizedBox(height: 2),
                      Container(
                        width: 16,
                        height: max <= 0 ? 2 : (d.jpy / max * 78).clamp(2, 78),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(d.date.length >= 10 ? d.date.substring(8) : d.date,
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _purchaseCard() {
    final p = _purchases;
    final all = [...?p?.charges, ...?p?.subscriptions]
      ..sort((a, b) => a.date.compareTo(b.date));
    return _card(
      title: '支払い履歴（Anthropic）',
      icon: Icons.receipt_long_outlined,
      child: all.isEmpty
          ? const Text('この月の記録はありません。',
              style: TextStyle(fontSize: 12, color: Colors.grey))
          : Column(
              children: [
                for (final t in all)
                  _kv('${t.date.month}/${t.date.day}  ${t.label}',
                      '¥${_fmt(t.amountJpy.toDouble())}'),
              ],
            ),
    );
  }

  Widget _footnote() {
    final at = _usage?.updatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '※「使った額」は各アプリの自己申告をトークン数×公式単価で計算した概算です。'
        'Anthropicの公式使用量APIは個人アカウントでは使えないため、この方式にしています。'
        '「クレジット購入」はカードの実額です。'
        '${at != null ? '\n最終更新: ${at.month}/${at.day} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}（10分おきに自動更新）' : ''}',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }

  Widget _empty() => const Text(
        'この月の記録はまだありません。\n'
        'アプリ側に計測を入れると、次にAIを使ったタイミングから貯まりはじめます。',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );

  Widget _bar(double ratio) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: ratio.clamp(0, 1),
        minHeight: 6,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation(Colors.indigo.shade300),
      ),
    );
  }

  Widget _kv(String k, String v, {String? note}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: const TextStyle(fontSize: 12)),
                if (note != null)
                  Text(note,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(v,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    final s = v.abs() < 100 && v != v.roundToDouble()
        ? v.toStringAsFixed(1)
        : v.round().toString();
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
  }
}
