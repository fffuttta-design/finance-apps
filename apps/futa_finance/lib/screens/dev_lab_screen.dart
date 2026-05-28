import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 🧪 開発中ラボ（事業モード専用）
///
/// PL/BS/予算管理など、まだ正式機能化していないプロトタイプを並べる場所。
/// 「見れば思い出せる、着想を得られる」を目的とした実験タブ。
/// 個人モードでは非表示（root_screen.dart でナビ制御）。
class DevLabScreen extends StatefulWidget {
  const DevLabScreen({super.key});

  @override
  State<DevLabScreen> createState() => _DevLabScreenState();
}

enum _LabView { pl, bs, budget }

class _DevLabScreenState extends State<DevLabScreen> with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _settings = SettingsRepository();
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  core.PaymentMethodsConfig? _payments;
  _LabView _view = _LabView.pl;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    PaymentsChangeNotifier.instance.addListener(_load);
  }

  @override
  void dispose() {
    _sub?.cancel();
    PaymentsChangeNotifier.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _settings.loadPayments();
    final txns = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _payments = p;
      _transactions = txns;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Text('🧪', style: TextStyle(fontSize: 20)),
            SizedBox(width: 6),
            Text('開発中（事業）',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _viewToggle(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(child: _seg(_LabView.pl, 'PL', Icons.assessment)),
            Expanded(child: _seg(_LabView.bs, 'BS', Icons.balance)),
            Expanded(child: _seg(_LabView.budget, '予算', Icons.event_note)),
          ],
        ),
      ),
    );
  }

  Widget _seg(_LabView v, String label, IconData icon) {
    final selected = _view == v;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _view = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4)
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFF1A237E)
                        : const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_payments == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_view) {
      _LabView.pl => _plView(),
      _LabView.bs => _bsView(),
      _LabView.budget => _budgetView(),
    };
  }

  // ═══════════════════════════════════════════════
  // PL（損益計算書）プロトタイプ
  // ═══════════════════════════════════════════════
  Widget _plView() {
    final now = DateTime.now();
    // 直近12ヶ月の月次集計
    final months = List.generate(12, (i) {
      final m = DateTime(now.year, now.month - (11 - i), 1);
      return m;
    });

    int incomeIn(DateTime m) => _transactions
        .where((t) =>
            t.type == core.TransactionType.income &&
            t.date.year == m.year &&
            t.date.month == m.month)
        .fold<int>(0, (s, t) => s + t.amount);

    int expenseIn(DateTime m) => _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.date.year == m.year &&
            t.date.month == m.month)
        .fold<int>(0, (s, t) => s + t.amount);

    final yearIncome =
        months.fold<int>(0, (s, m) => s + incomeIn(m));
    final yearExpense =
        months.fold<int>(0, (s, m) => s + expenseIn(m));
    final yearProfit = yearIncome - yearExpense;

    // カテゴリ別経費（直近12ヶ月）
    final categoryTotals = <String, int>{};
    for (final t in _transactions) {
      if (t.type != core.TransactionType.expense) continue;
      final months12Ago = DateTime(now.year, now.month - 11, 1);
      if (t.date.isBefore(months12Ago)) continue;
      categoryTotals[t.category.major] =
          (categoryTotals[t.category.major] ?? 0) + t.amount;
    }
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _devNote('PL（損益計算書） - プロトタイプ',
            '直近12ヶ月の売上・経費・利益。\n会計科目グルーピングは未実装で、カテゴリそのまま。'),
        const SizedBox(height: 12),
        // 年間サマリー（主役）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('直近12ヶ月',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              _plRow('売上', yearIncome, const Color(0xFF16A34A)),
              _plRow('経費', -yearExpense, const Color(0xFFDC2626)),
              const Divider(),
              _plRow('利益（売上 − 経費）', yearProfit,
                  yearProfit >= 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  big: true),
              if (yearIncome > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('利益率',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                    const Spacer(),
                    Text(
                      '${(yearProfit / yearIncome * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: yearProfit >= 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 月次テーブル
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text('月次推移',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              _plMonthHeader(),
              const Divider(height: 1),
              ...months.reversed.map((m) {
                final i = incomeIn(m);
                final e = expenseIn(m);
                return _plMonthRow(m, i, e);
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // カテゴリ別経費（直近12ヶ月）
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text('カテゴリ別経費（直近12ヶ月）',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: sortedCategories.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('経費の記録なし',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF9CA3AF))),
                    ),
                  ]
                : sortedCategories.map((e) {
                    final ratio = yearExpense == 0
                        ? 0.0
                        : e.value / yearExpense;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(e.key,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Text(
                            formatYen(e.value),
                            style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 44,
                            child: Text(
                                '${(ratio * 100).toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF))),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _plRow(String label, int amount, Color color,
      {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: big ? 14 : 13,
                  fontWeight: big ? FontWeight.w700 : FontWeight.w500,
                  color: const Color(0xFF111827))),
          Text(
            formatYen(amount, withSign: true),
            style: TextStyle(
                fontSize: big ? 24 : 16,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _plMonthHeader() {
    const style = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: const [
          SizedBox(width: 48, child: Text('月', style: style)),
          Expanded(
              child: Text('売上',
                  style: style, textAlign: TextAlign.right)),
          SizedBox(width: 8),
          Expanded(
              child: Text('経費',
                  style: style, textAlign: TextAlign.right)),
          SizedBox(width: 8),
          Expanded(
              child: Text('利益',
                  style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _plMonthRow(DateTime m, int income, int expense) {
    final profit = income - expense;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 48,
              child: Text('${m.month}月',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827)))),
          Expanded(
              child: Text(formatYen(income),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF16A34A)))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(formatYen(expense),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFFDC2626)))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(formatYen(profit, withSign: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: profit >= 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626)))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // BS（貸借対照表）プロトタイプ
  // ═══════════════════════════════════════════════
  Widget _bsView() {
    final p = _payments!;
    final now = DateTime.now();

    // 資産: 銀行口座の現在残高合計（startingBalance + 取引集計）
    final bankNames = p.bankAccounts.map((b) => b.name).toSet();
    final delta = <String, int>{};
    for (final t in _transactions) {
      if (t.type == core.TransactionType.transfer) {
        if (t.transferFromAccount != null &&
            bankNames.contains(t.transferFromAccount)) {
          delta[t.transferFromAccount!] =
              (delta[t.transferFromAccount!] ?? 0) - t.amount;
        }
        if (t.transferToAccount != null &&
            bankNames.contains(t.transferToAccount)) {
          delta[t.transferToAccount!] =
              (delta[t.transferToAccount!] ?? 0) + t.amount;
        }
        continue;
      }
      if (!bankNames.contains(t.paymentMethod)) continue;
      if (t.type == core.TransactionType.income) {
        delta[t.paymentMethod] = (delta[t.paymentMethod] ?? 0) + t.amount;
      } else {
        delta[t.paymentMethod] = (delta[t.paymentMethod] ?? 0) - t.amount;
      }
    }
    int balanceOf(core.RegisteredBankAccount b) =>
        (b.startingBalance ?? 0) + (delta[b.name] ?? 0);

    final byKind = <core.AccountType, List<core.RegisteredBankAccount>>{};
    for (final b in p.bankAccounts) {
      byKind.putIfAbsent(b.accountType, () => []).add(b);
    }
    final bankTotal = (byKind[core.AccountType.bank] ?? [])
        .fold<int>(0, (s, b) => s + balanceOf(b));
    final cashTotal = (byKind[core.AccountType.cash] ?? [])
        .fold<int>(0, (s, b) => s + balanceOf(b));
    final emoneyTotal = (byKind[core.AccountType.emoney] ?? [])
        .fold<int>(0, (s, b) => s + balanceOf(b));
    final assetTotal = bankTotal + cashTotal + emoneyTotal;

    // 負債: クレカの当月利用合計（暫定）
    final cardNames = p.creditCards.map((c) => c.name).toSet();
    final cardUsage = <String, int>{};
    for (final t in _transactions) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.date.year != now.year || t.date.month != now.month) continue;
      if (!cardNames.contains(t.paymentMethod)) continue;
      cardUsage[t.paymentMethod] =
          (cardUsage[t.paymentMethod] ?? 0) + t.amount;
    }
    final cardLiability =
        cardUsage.values.fold<int>(0, (s, v) => s + v);
    final liabilityTotal = cardLiability;

    final netWorth = assetTotal - liabilityTotal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _devNote('BS（貸借対照表） - プロトタイプ',
            '資産 − 負債 = 純資産。負債モデル未実装のため、クレカの当月利用を暫定的に負債扱い。'),
        const SizedBox(height: 12),
        // 純資産（主役）
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: (netWorth >= 0
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEE2E2))
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (netWorth >= 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626))
                    .withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('純資産',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827))),
                  Text('資産 − 負債',
                      style: TextStyle(
                          fontSize: 10, color: Color(0xFF6B7280))),
                ],
              ),
              Text(
                formatYen(netWorth, withSign: true),
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: netWorth >= 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 資産セクション
        _bsSection('資産', const Color(0xFF1A237E), assetTotal, [
          _BsItem('銀行口座', bankTotal),
          _BsItem('現金', cashTotal),
          _BsItem('電子マネー', emoneyTotal),
        ]),
        const SizedBox(height: 12),
        // 負債セクション
        _bsSection('負債', const Color(0xFFDC2626), liabilityTotal, [
          _BsItem('クレカ当月利用（暫定）', cardLiability),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '⚠️ 借入金/未払金などの本格的な負債モデルは未実装。\n'
            '今は「クレカの当月利用」だけを負債として暫定計算しています。',
            style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
          ),
        ),
      ],
    );
  }

  Widget _bsSection(
      String label, Color tint, int total, List<_BsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10)),
              border: Border(
                  left: BorderSide(color: tint, width: 4)),
            ),
            child: Row(
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tint)),
                const Spacer(),
                Text(formatYen(total),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: Color(0xFF111827))),
              ],
            ),
          ),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(it.label,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text(formatYen(it.amount),
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 予算管理 - プレースホルダ
  // ═══════════════════════════════════════════════
  Widget _budgetView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _devNote('予算管理（税金・保険料） - 構想段階',
            '次フェーズ実装予定。BudgetItem モデル新設 + 不定期支払いスケジュール対応。'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Phase 構成',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
              SizedBox(height: 12),
              _PhaseTile(
                  num: 1,
                  title: 'BudgetItem モデル + 一覧画面',
                  body:
                      '年額 + 支払スケジュール（月/日/金額）。 設定からアクセス可能に。',
                  done: false),
              _PhaseTile(
                  num: 2,
                  title: 'ホームに「来月の予定支払」セクション',
                  body: '予算項目のスケジュールから直近30日を抽出して表示。',
                  done: false),
              _PhaseTile(
                  num: 3,
                  title: '取引保存時に予算項目を紐付け',
                  body: 'Transaction に budgetItemId を追加。',
                  done: false),
              _PhaseTile(
                  num: 4,
                  title: '予実突合（予算 vs 実績）ビュー',
                  body: '集計タブ or この開発中タブに表示。',
                  done: false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '💡 想定する税金・保険料の例:\n'
            '・住民税（年4回払い: 6/8/10/1月）\n'
            '・所得税（年1回 or 予定納税3回）\n'
            '・国民健康保険（年10回など自治体次第）\n'
            '・国民年金（毎月）\n'
            '・生命保険（年払い/月払い）\n'
            '・自動車税（5月）\n'
            '・固定資産税（年4回）',
            style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  // 共通: 開発中バナー
  // ═══════════════════════════════════════════════
  Widget _devNote(String title, String body) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science,
                  size: 14, color: Color(0xFFEA580C)),
              const SizedBox(width: 4),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C2D12))),
            ],
          ),
          const SizedBox(height: 4),
          Text(body,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF7C2D12))),
        ],
      ),
    );
  }
}

class _BsItem {
  final String label;
  final int amount;
  _BsItem(this.label, this.amount);
}

class _PhaseTile extends StatelessWidget {
  const _PhaseTile(
      {required this.num,
      required this.title,
      required this.body,
      required this.done});

  final int num;
  final String title;
  final String body;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: done
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('$num',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: done
                        ? Colors.white
                        : const Color(0xFF6B7280))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
