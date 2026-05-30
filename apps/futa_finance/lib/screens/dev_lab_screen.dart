import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/budget_item.dart';
import '../data/budget_item_repository.dart';
import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

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
  /// カテゴリ名が「原価」か判定する。
  /// 「原価」「外注」「仕入」「材料」のいずれかを含むカテゴリは原価扱い。
  /// それ以外の経費は販管費扱い。
  /// 後でカテゴリ編集に「会計科目マッピング」を入れたら、これを置き換える。
  bool _isCostOfSales(String majorCategory) {
    const costKeywords = ['原価', '外注', '仕入', '材料'];
    return costKeywords.any((k) => majorCategory.contains(k));
  }

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

    // 月別の原価/販管費を分けて集計
    int costInMonth(DateTime m) => _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.date.year == m.year &&
            t.date.month == m.month &&
            _isCostOfSales(t.category.major))
        .fold<int>(0, (s, t) => s + t.amount);

    int sgaInMonth(DateTime m) => _transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.date.year == m.year &&
            t.date.month == m.month &&
            !_isCostOfSales(t.category.major))
        .fold<int>(0, (s, t) => s + t.amount);

    final yearIncome =
        months.fold<int>(0, (s, m) => s + incomeIn(m));
    final yearExpense =
        months.fold<int>(0, (s, m) => s + expenseIn(m));
    final yearProfit = yearIncome - yearExpense;
    final yearCost = months.fold<int>(0, (s, m) => s + costInMonth(m));
    final yearSga = months.fold<int>(0, (s, m) => s + sgaInMonth(m));
    final yearGrossProfit = yearIncome - yearCost; // 粗利

    // 比率（売上が0なら0扱い）
    double pct(int part) =>
        yearIncome == 0 ? 0 : part / yearIncome * 100;

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
            '直近12ヶ月の売上・原価・販管費・利益。\n'
            '原価判定はカテゴリ名に「原価」「外注」「仕入」「材料」を含むものを自動判別。\n'
            '後で「会計科目マッピング」UIで個別調整できるようにする予定。'),
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
              _plRow('原価', -yearCost, const Color(0xFFDC2626)),
              const Divider(),
              _plRow('粗利（売上 − 原価）', yearGrossProfit,
                  yearGrossProfit >= 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626)),
              _plRow('販管費', -yearSga, const Color(0xFFDC2626)),
              const Divider(),
              _plRow('営業利益（粗利 − 販管費）', yearProfit,
                  yearProfit >= 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  big: true),
              if (yearIncome > 0) ...[
                const SizedBox(height: 10),
                // 3つの率を横並びで主役表示
                Row(
                  children: [
                    Expanded(
                        child: _ratioBadge(
                            '原価率', pct(yearCost),
                            const Color(0xFFDC2626))),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _ratioBadge(
                            '粗利率', pct(yearGrossProfit),
                            const Color(0xFF16A34A))),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _ratioBadge(
                            '営業利益率', pct(yearProfit),
                            yearProfit >= 0
                                ? const Color(0xFF1A237E)
                                : const Color(0xFFDC2626))),
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
        // 会計風 PL 表（横スクロール）
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(children: [
            Icon(Icons.table_chart_outlined,
                size: 14, color: Color(0xFF6B7280)),
            SizedBox(width: 4),
            Text('会計風 月次表（横スクロール）',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _accountingTable(months, incomeIn, costInMonth,
                sgaInMonth, yearIncome, yearCost, yearSga),
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

  /// 比率バッジ（原価率 / 粗利率 / 営業利益率の3つを横並びで使う）。
  Widget _ratioBadge(String label, double pct, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 2),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  /// 会計風 月次表（横スクロール）。
  /// 縦に項目（売上/原価/粗利/販管費/営業利益）、横に月（12ヶ月 + 累計 + 売上比%）。
  /// 添付画像の「収益計算表」っぽい構造に寄せる。
  Widget _accountingTable(
      List<DateTime> months,
      int Function(DateTime) incomeIn,
      int Function(DateTime) costInMonth,
      int Function(DateTime) sgaInMonth,
      int yearIncome,
      int yearCost,
      int yearSga) {
    final yearGross = yearIncome - yearCost;
    final yearOp = yearGross - yearSga;

    // 月別の値を縦項目ごとに事前計算
    final salesPerMonth =
        months.map((m) => incomeIn(m)).toList();
    final costPerMonth =
        months.map((m) => costInMonth(m)).toList();
    final grossPerMonth = [
      for (int i = 0; i < months.length; i++)
        salesPerMonth[i] - costPerMonth[i]
    ];
    final sgaPerMonth =
        months.map((m) => sgaInMonth(m)).toList();
    final opPerMonth = [
      for (int i = 0; i < months.length; i++)
        grossPerMonth[i] - sgaPerMonth[i]
    ];

    String yenLabel(int v) {
      if (v == 0) return '0';
      return formatYen(v);
    }

    Color amountColor(int v, {bool isProfit = false}) {
      if (isProfit) {
        return v >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
      }
      return const Color(0xFF111827);
    }

    Widget headerCell(String text,
        {double width = 70, Color? bg, Color? fg}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: bg ?? const Color(0xFFF9FAFB),
          border: const Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        alignment: Alignment.center,
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg ?? const Color(0xFF6B7280))),
      );
    }

    Widget labelCell(String text,
        {double width = 110,
        bool bold = false,
        Color? bg,
        Color? fg}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg ?? Colors.white,
          border: const Border(
              right: BorderSide(color: Color(0xFFE5E7EB)),
              bottom: BorderSide(color: Color(0xFFF3F4F6))),
        ),
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w500,
                color: fg ?? const Color(0xFF111827))),
      );
    }

    Widget dataCell(int amount,
        {double width = 70,
        bool isProfit = false,
        bool bold = false,
        Color? bg}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: bg ?? Colors.white,
          border: const Border(
              bottom: BorderSide(color: Color(0xFFF3F4F6))),
        ),
        alignment: Alignment.centerRight,
        child: Text(yenLabel(amount),
            style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: amountColor(amount, isProfit: isProfit))),
      );
    }

    Widget pctCell(double pct,
        {double width = 60, Color? bg, Color? fg}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: bg ?? const Color(0xFFFDF4FF),
          border: const Border(
              bottom: BorderSide(color: Color(0xFFF3F4F6))),
        ),
        alignment: Alignment.centerRight,
        child: Text('${pct.toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: fg ?? const Color(0xFF7C2D12))),
      );
    }

    Widget row({
      required String label,
      required List<int> values,
      required int total,
      bool isProfit = false,
      bool emphasize = false,
    }) {
      final ratio = yearIncome == 0 ? 0.0 : total / yearIncome * 100;
      final bg = emphasize ? const Color(0xFFFEF9C3) : null;
      return Row(
        children: [
          labelCell(label, bold: emphasize, bg: bg),
          for (int i = 0; i < values.length; i++)
            dataCell(values[i],
                isProfit: isProfit, bold: emphasize, bg: bg),
          dataCell(total,
              isProfit: isProfit, bold: true, bg: bg),
          pctCell(ratio),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダー
        Row(
          children: [
            headerCell('項目', width: 110),
            for (final m in months)
              headerCell('${m.month}月'),
            headerCell('1年累計', width: 80, bg: const Color(0xFFF3F4F6)),
            headerCell('売上比',
                width: 60, bg: const Color(0xFFFDF4FF)),
          ],
        ),
        // 売上
        row(
            label: '売上',
            values: salesPerMonth,
            total: yearIncome,
            emphasize: false),
        // 原価
        row(
            label: '原価',
            values: costPerMonth,
            total: yearCost,
            emphasize: false),
        // 粗利（強調）
        row(
            label: '粗利',
            values: grossPerMonth,
            total: yearGross,
            isProfit: true,
            emphasize: true),
        // 販管費
        row(
            label: '販管費',
            values: sgaPerMonth,
            total: yearSga,
            emphasize: false),
        // 営業利益（強調）
        row(
            label: '営業利益',
            values: opPerMonth,
            total: yearOp,
            isProfit: true,
            emphasize: true),
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
  // 予算管理 - Phase 1〜4 実装
  // ═══════════════════════════════════════════════
  Widget _budgetView() {
    return AnimatedBuilder(
      animation: BudgetItemRepository.instance,
      builder: (context, _) => FutureBuilder<BudgetItemsConfig>(
        future: BudgetItemRepository.instance.load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cfg = snap.data!;
          return _budgetBody(cfg);
        },
      ),
    );
  }

  Widget _budgetBody(BudgetItemsConfig cfg) {
    final now = DateTime.now();
    final year = now.year;

    // Phase 2: 来月の予定支払い（今日から30日以内）
    final upcoming = <_UpcomingItem>[];
    for (final item in cfg.items) {
      for (final s in item.schedule) {
        final next = s.nextDateFrom(now);
        final diffDays = next.difference(now).inDays;
        if (diffDays <= 30) {
          upcoming.add(
              _UpcomingItem(item: item, scheduled: s, date: next));
        }
      }
    }
    upcoming.sort((a, b) => a.date.compareTo(b.date));

    // Phase 4: 予実突合（年度ベース）
    final annualBudget =
        cfg.items.fold<int>(0, (s, i) => s + i.annualAmount);
    final annualActual = cfg.items
        .fold<int>(0, (s, i) => s + i.actualTotal(year: year));
    final remaining = annualBudget - annualActual;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _devNote('予算管理（税金・保険料） - Phase 1〜4 試作',
            '開発中ラボ内で完結する実装。Transaction との本紐付けは未対応で、'
            '「実績マーク」ボタンで予実を手動付与する仕様。'),
        const SizedBox(height: 12),

        // ── Phase 4: 年間予実サマリー ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      size: 16, color: Color(0xFF1A237E)),
                  const SizedBox(width: 6),
                  Text('$year 年の予実',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add,
                        color: Color(0xFFEA580C)),
                    tooltip: '予算項目を追加',
                    onPressed: () => _editBudgetDialog(null),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _budgetSummaryRow('年間予算', annualBudget,
                  const Color(0xFF1A237E)),
              _budgetSummaryRow('実績合計', annualActual,
                  const Color(0xFF16A34A)),
              const Divider(),
              _budgetSummaryRow('残予算', remaining,
                  remaining < 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF6B7280),
                  big: true),
              if (annualBudget > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (annualActual / annualBudget).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      annualActual >= annualBudget
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '達成率 ${(annualActual / annualBudget * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Phase 2: 直近30日の予定支払い ──
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(children: [
            Icon(Icons.event, size: 14, color: Color(0xFFEA580C)),
            SizedBox(width: 4),
            Text('直近30日の予定支払',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: upcoming.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('30日以内の予定はなし',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                )
              : Column(
                  children: upcoming
                      .map((u) => _upcomingTile(u))
                      .toList(),
                ),
        ),

        const SizedBox(height: 14),

        // ── Phase 1: 予算項目一覧 ──
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(children: [
            Icon(Icons.list_alt, size: 14, color: Color(0xFF1A237E)),
            SizedBox(width: 4),
            Text('予算項目',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
          ]),
        ),
        if (cfg.items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                const Text('まだ予算項目がありません',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('予算項目を追加'),
                  onPressed: () => _editBudgetDialog(null),
                ),
                const SizedBox(height: 12),
                _budgetHints(),
              ],
            ),
          )
        else
          ...cfg.items.map((i) => _budgetItemTile(i, year)),
      ],
    );
  }

  Widget _budgetSummaryRow(String label, int amount, Color color,
      {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: big ? 14 : 12,
                  fontWeight: big ? FontWeight.w700 : FontWeight.w500,
                  color: const Color(0xFF111827))),
          Text(formatYen(amount, withSign: big),
              style: TextStyle(
                  fontSize: big ? 22 : 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _upcomingTile(_UpcomingItem u) {
    final daysLeft = u.date.difference(DateTime.now()).inDays;
    final urgent = daysLeft <= 7;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Text(u.item.kind.emoji,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.item.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827))),
                Row(
                  children: [
                    Text('${u.scheduled.month}/${u.scheduled.day}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: urgent
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFE0E7FF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        daysLeft <= 0
                            ? '今日'
                            : daysLeft == 1
                                ? '明日'
                                : 'あと $daysLeft 日',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: urgent
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF1A237E)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatYen(u.scheduled.amount),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                      fontFamily: 'monospace')),
              const SizedBox(height: 2),
              SizedBox(
                height: 24,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _markActual(u),
                  child: const Text('払った',
                      style: TextStyle(fontSize: 10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _budgetItemTile(BudgetItem item, int year) {
    final actual = item.actualTotal(year: year);
    final progress = item.progress(year: year).clamp(0.0, 1.0);
    final remaining = item.annualAmount - actual;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _editBudgetDialog(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(item.kind.emoji,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827))),
                        Text(
                          '${item.kind.label} / 年${item.schedule.length}回 / 年額 ${formatYen(item.annualAmount)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Color(0xFFDC2626)),
                    onPressed: () => _deleteBudget(item),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 進捗バー
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFF3F4F6),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('実績 ${formatYen(actual)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF16A34A),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('残 ${formatYen(remaining)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: remaining < 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF6B7280),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _budgetHints() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '💡 想定例: 住民税(6/8/10/1月) / 国民健康保険 / 国民年金 / 生命保険 / 自動車税 / 固定資産税',
        style: TextStyle(fontSize: 11, color: Color(0xFF1E3A8A)),
      ),
    );
  }

  // ── 追加・編集ダイアログ ──
  Future<void> _editBudgetDialog(BudgetItem? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final noteCtrl = TextEditingController(text: initial?.note ?? '');
    var kind = initial?.kind ?? BudgetKind.tax;
    final scheduleItems = [...(initial?.schedule ?? <ScheduledPayment>[])];

    final saved = await showModalBottomSheet<BudgetItem?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final annual =
            scheduleItems.fold<int>(0, (s, p) => s + p.amount);
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              children: [
                // ヘッダー
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      Text(initial == null ? '予算項目を追加' : '予算項目を編集',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: '項目名（必須）',
                            floatingLabelBehavior:
                                FloatingLabelBehavior.always,
                          ),
                          onChanged: (_) => setLocal(() {}),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<BudgetKind>(
                          initialValue: kind,
                          decoration: const InputDecoration(
                            labelText: '種別',
                            floatingLabelBehavior:
                                FloatingLabelBehavior.always,
                          ),
                          items: BudgetKind.values
                              .map((k) => DropdownMenuItem(
                                    value: k,
                                    child: Text('${k.emoji} ${k.label}'),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setLocal(() => kind = v ?? kind),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteCtrl,
                          decoration: const InputDecoration(
                            labelText: '備考（任意）',
                            floatingLabelBehavior:
                                FloatingLabelBehavior.always,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('支払スケジュール',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6B7280))),
                            const Spacer(),
                            Text('年額 ${formatYen(annual)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF111827))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...List.generate(scheduleItems.length, (i) {
                          final s = scheduleItems[i];
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${s.month}月 ${s.day}日',
                                    style: const TextStyle(
                                        fontSize: 13),
                                  ),
                                ),
                                Text(formatYen(s.amount),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600)),
                                IconButton(
                                  icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Color(0xFFDC2626)),
                                  onPressed: () => setLocal(() =>
                                      scheduleItems.removeAt(i)),
                                ),
                              ],
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('支払予定を追加'),
                          onPressed: () async {
                            final added = await _editSchedulePayment(null);
                            if (added != null) {
                              setLocal(() => scheduleItems.add(added));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // フッター: 保存
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        top: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  padding:
                      const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('キャンセル'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: nameCtrl.text.trim().isEmpty
                              ? null
                              : () {
                                  final item = BudgetItem(
                                    id: initial?.id ??
                                        DateTime.now()
                                            .microsecondsSinceEpoch
                                            .toString(),
                                    name: nameCtrl.text.trim(),
                                    kind: kind,
                                    schedule: scheduleItems,
                                    actuals: initial?.actuals ?? const [],
                                    note: noteCtrl.text.trim().isEmpty
                                        ? null
                                        : noteCtrl.text.trim(),
                                  );
                                  Navigator.pop(ctx, item);
                                },
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );

    if (saved != null) {
      await BudgetItemRepository.instance.upsert(saved);
    }
  }

  // ── 支払予定 1件を編集 ──
  Future<ScheduledPayment?> _editSchedulePayment(
      ScheduledPayment? initial) async {
    int month = initial?.month ?? DateTime.now().month;
    int day = initial?.day ?? 1;
    final amountCtrl = TextEditingController(
        text: initial != null ? formatAmount(initial.amount) : '');

    return showDialog<ScheduledPayment?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('支払予定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: month,
                      decoration: const InputDecoration(labelText: '月'),
                      items: List.generate(12, (i) => i + 1)
                          .map((m) => DropdownMenuItem(
                              value: m, child: Text('$m月')))
                          .toList(),
                      onChanged: (v) => setLocal(() => month = v ?? 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: day,
                      decoration: const InputDecoration(labelText: '日'),
                      items: List.generate(31, (i) => i + 1)
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text('$d日')))
                          .toList(),
                      onChanged: (v) => setLocal(() => day = v ?? 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  ThousandsSeparatorInputFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: '金額（円）',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                final a = parseAmount(amountCtrl.text);
                if (a == null) return;
                Navigator.pop(
                    ctx,
                    ScheduledPayment(
                        month: month, day: day, amount: a));
              },
              child: const Text('OK'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _markActual(_UpcomingItem u) async {
    // 「払った」確定: その日付・金額で actuals に追加
    final newActuals = [
      ...u.item.actuals,
      ActualPayment(
        date: DateTime.now(),
        amount: u.scheduled.amount,
        note: '${u.scheduled.month}/${u.scheduled.day} 予定分',
      ),
    ];
    final updated = u.item.copyWith(actuals: newActuals);
    await BudgetItemRepository.instance.upsert(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '${u.item.name}: ${formatYen(u.scheduled.amount)} の実績を記録しました'),
          duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _deleteBudget(BudgetItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${item.name} を削除？'),
        content: const Text('予算項目と実績記録ごと削除されます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await BudgetItemRepository.instance.remove(item.id);
    }
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

/// 来月以内の予定支払いの内部表現。
class _UpcomingItem {
  final BudgetItem item;
  final ScheduledPayment scheduled;
  final DateTime date;
  _UpcomingItem(
      {required this.item, required this.scheduled, required this.date});
}
