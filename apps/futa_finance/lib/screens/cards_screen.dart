import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/ui_preferences.dart';
import '../utils/formatters.dart';
import '../widgets/brand_logo.dart';
import 'card_detail_screen.dart';
import 'card_editor_screen.dart';

/// クレカタブ画面。
/// クレカ一覧 + 各カードの当月利用合計 + 引落予定日。
/// タップで CardDetailScreen（明細画面）に遷移。
/// 上部「設定」ボタンから CardEditorScreen（編集一覧）に遷移。
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _settings = SettingsRepository();
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig? _payments;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    PaymentsChangeNotifier.instance.addListener(_load);
    UiPreferences.instance.addListener(_onUiPrefsChanged);
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    UiPreferences.instance.removeListener(_onUiPrefsChanged);
    super.dispose();
  }

  void _onUiPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _payments = p;
    });
  }

  /// 当月のカード使用合計をカード名キーで返す。
  Map<String, int> _monthlyUsage(List<core.RegisteredCreditCard> cards) {
    final now = DateTime.now();
    final nameSet = cards.map((c) => c.name).toSet();
    final usage = <String, int>{};
    for (final t in _transactions) {
      if (t.date.year != now.year || t.date.month != now.month) continue;
      if (t.type != core.TransactionType.expense) continue;
      if (!nameSet.contains(t.paymentMethod)) continue;
      usage[t.paymentMethod] =
          (usage[t.paymentMethod] ?? 0) + t.amount;
    }
    return usage;
  }

  @override
  Widget build(BuildContext context) {
    final p = _payments;
    if (p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // 計算は全カードで実施 → 表示直前に hideZero フィルタ。
    // 累積額（当月利用 + 過去請求の入力分）が 0 のカードは「休眠中」として除外。
    final allCards = p.creditCards;
    final usage = _monthlyUsage(allCards);
    final monthTotal = usage.values.fold<int>(0, (s, v) => s + v);
    final hideZero = UiPreferences.instance.hideZeroBalance;
    final cards = hideZero
        ? allCards.where((c) {
            final accum = (usage[c.name] ?? 0) + c.displayBalance;
            return accum != 0;
          }).toList()
        : allCards;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('クレカ', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Color(0xFF6B7280)),
            tooltip: 'クレカ設定（追加・削除・並び替え）',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardEditorScreen(),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _totalCard(monthTotal, cards.length),
            const SizedBox(height: 12),
            // ── 月別請求一覧（全カード合算） ──
            if (cards.isNotEmpty) ...[
              _monthlyBillingSection(cards),
              const SizedBox(height: 12),
            ],
            if (cards.isEmpty)
              _emptyState()
            else
              ...cards.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _cardTile(c, usage[c.name] ?? 0),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _totalCard(int monthTotal, int cardCount) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card,
                  color: Color(0xFFDC2626), size: 18),
              const SizedBox(width: 6),
              Text(
                '${now.month}月のカード利用合計',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatYen(monthTotal),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDC2626),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$cardCount 枚のカード · 翌月以降に銀行口座から引き落とされる予定',
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _cardTile(core.RegisteredCreditCard c, int amount) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CardDetailScreen(card: c),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              BrandLogo(
                iconUrl: c.iconUrl,
                fallbackEmoji: '💳',
                size: 40,
                borderRadius: 6,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (c.paymentDay != null) ...[
                          const Icon(Icons.event,
                              size: 11, color: Color(0xFF1A237E)),
                          const SizedBox(width: 2),
                          Text(
                            '毎月${c.paymentDay}日引落',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF1A237E),
                                fontWeight: FontWeight.w600),
                          ),
                        ] else
                          const Text(
                            '引落日未設定',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                      ],
                    ),
                    if (c.memo != null && c.memo!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        c.memo!,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                            fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '当月利用',
                    style:
                        TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatYen(amount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                      color: amount > 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 18, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  /// 月別請求一覧（全カード合算）。
  /// 各月のカード合計請求額と、カード毎の内訳サマリーを表示。
  Widget _monthlyBillingSection(
      List<core.RegisteredCreditCard> cards) {
    final cardNameSet = cards.map((c) => c.name).toSet();
    // yearMonth (e.g. '2026-05') → カード名 → 合計
    final byMonthCard = <String, Map<String, int>>{};
    for (final t in _transactions) {
      if (t.type != core.TransactionType.expense) continue;
      if (!cardNameSet.contains(t.paymentMethod)) continue;
      final ym =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      final m = byMonthCard.putIfAbsent(ym, () => <String, int>{});
      m[t.paymentMethod] = (m[t.paymentMethod] ?? 0) + t.amount;
    }
    if (byMonthCard.isEmpty) return const SizedBox.shrink();
    final entries = byMonthCard.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Icon(Icons.calendar_month,
                    color: Color(0xFF1A237E), size: 18),
                SizedBox(width: 6),
                Text('月別請求一覧',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
                SizedBox(width: 4),
                Text('（全カード合算）',
                    style: TextStyle(
                        fontSize: 10, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < entries.length; i++)
            _monthRow(entries[i].key, entries[i].value, cards,
                isLast: i == entries.length - 1),
        ],
      ),
    );
  }

  Widget _monthRow(String yearMonth, Map<String, int> byCard,
      List<core.RegisteredCreditCard> cards,
      {required bool isLast}) {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final total = byCard.values.fold<int>(0, (s, v) => s + v);
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$year年$month月',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
              ),
              Text(formatYen(total),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                      color: Color(0xFFDC2626))),
            ],
          ),
          const SizedBox(height: 4),
          // カード毎の内訳（金額の大きい順）
          ...() {
            final usedCards = cards
                .where((c) => (byCard[c.name] ?? 0) > 0)
                .toList()
              ..sort((a, b) =>
                  (byCard[b.name] ?? 0).compareTo(byCard[a.name] ?? 0));
            return usedCards.map((c) {
              final amount = byCard[c.name] ?? 0;
              final paymentDay = c.paymentDay;
              String? billingLabel;
              if (paymentDay != null) {
                final billY = month == 12 ? year + 1 : year;
                final billM = month == 12 ? 1 : month + 1;
                billingLabel =
                    '$billY/${billM.toString().padLeft(2, '0')}/${paymentDay.toString().padLeft(2, '0')} 引落';
              }
              return Padding(
                padding: const EdgeInsets.only(top: 3, left: 4),
                child: Row(
                  children: [
                    const Text('• ',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF))),
                    Expanded(
                      child: Text(
                        billingLabel != null
                            ? '${c.name}  ·  $billingLabel'
                            : c.name,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(formatYen(amount),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            fontFamily: 'monospace')),
                  ],
                ),
              );
            }).toList();
          }(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          const Icon(Icons.credit_card_outlined,
              size: 40, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 8),
          const Text(
            'まだクレジットカードが登録されていません',
            style: TextStyle(color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('カードを追加'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardEditorScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
