import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/payments_change_notifier.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../widgets/brand_logo.dart';

/// クレジットカード詳細（利用明細）画面。
/// 銀行通帳の AccountDetailScreen に相当するクレカ版。
///
/// 機能:
/// - 月セレクター（取引のある月 + 当月）
/// - サマリー: 当月利用合計（大）/ 件数 / 引落予定日
/// - 利用履歴: その月のカード利用一覧（日付→明細→金額）
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.card});

  final core.RegisteredCreditCard card;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

const double _kContentMaxWidth = 1000;

class _CardDetailScreenState extends State<CardDetailScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];
  DateTime? _selectedMonth;
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// 編集後のカードスナップショット（paymentDay変更時に画面に即反映するため）。
  /// null なら widget.card を使う。
  core.RegisteredCreditCard? _updatedCard;
  core.RegisteredCreditCard get _card => _updatedCard ?? widget.card;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
    _sub = TransactionRepository.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _all = list);
    });
    // 他画面で payments が更新された時、このカードの最新値を反映する
    // （引落日を保存 → 戻る → 再表示で消える問題を防ぐ）
    PaymentsChangeNotifier.instance.addListener(_refreshCardFromPayments);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    PaymentsChangeNotifier.instance.removeListener(_refreshCardFromPayments);
    super.dispose();
  }

  Future<void> _refreshCardFromPayments() async {
    try {
      final cfg = await SettingsRepository.instance.loadPayments();
      core.RegisteredCreditCard? found;
      for (final c in cfg.creditCards) {
        if (c.id == widget.card.id) {
          found = c;
          break;
        }
      }
      if (found == null || !mounted) return;
      setState(() => _updatedCard = found);
    } catch (_) {}
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() => _all = list);
  }

  /// このカードに紐づく取引（paymentMethod が一致）。
  List<core.Transaction> _cardTransactions() {
    final name = _card.name;
    return _all.where((t) {
      return t.type == core.TransactionType.expense &&
          t.paymentMethod == name;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 月選択肢: 当月 + 取引月（降順）+ 全期間。
  List<DateTime?> _availableMonths() {
    final name = _card.name;
    final set = <DateTime>{};
    final now = DateTime.now();
    set.add(DateTime(now.year, now.month));
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.paymentMethod != name) continue;
      set.add(DateTime(t.date.year, t.date.month));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return [null, ...list];
  }

  @override
  Widget build(BuildContext context) {
    final allTxns = _cardTransactions();
    final monthTxns = _selectedMonth == null
        ? allTxns
        : allTxns
            .where((t) =>
                t.date.year == _selectedMonth!.year &&
                t.date.month == _selectedMonth!.month)
            .toList();
    final monthTotal =
        monthTxns.fold<int>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_card.iconUrl != null && _card.iconUrl!.isNotEmpty)
              BrandLogo(
                  iconUrl: _card.iconUrl,
                  fallbackEmoji: '💳',
                  size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_card.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle,
                color: Color(0xFFDC2626)),
            tooltip: '月別請求を追加',
            onPressed: _showAddBillingDialog,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final content = Column(
            children: [
              // 共通: サマリー（利用合計/件数/引落予定日）
              _summaryCard(monthTotal, monthTxns.length),
              // タブバー
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFFDC2626),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: const Color(0xFFDC2626),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.receipt_long_outlined, size: 18),
                      text: '明細',
                      height: 48,
                    ),
                    Tab(
                      icon: Icon(Icons.show_chart, size: 18),
                      text: '請求推移',
                      height: 48,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // ── タブ1: その月の明細 ──
                    Column(
                      children: [
                        _monthSelector(),
                        const Divider(height: 1),
                        Expanded(child: _historyList(monthTxns)),
                      ],
                    ),
                    // ── タブ2: 月別請求推移 ──
                    _monthlyBillingPage(),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth >= 900) {
            // Row+Spacer で中央寄せ（Align+SizedBox(height) より安定）
            return Row(
              children: [
                const Spacer(),
                SizedBox(width: _kContentMaxWidth, child: content),
                const Spacer(),
              ],
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _monthSelector() {
    final months = _availableMonths();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Text('期間: ',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          DropdownButton<DateTime?>(
            value: _selectedMonth,
            underline: const SizedBox.shrink(),
            items: months.map((m) {
              final label = m == null ? '全期間' : '${m.year}年${m.month}月';
              return DropdownMenuItem<DateTime?>(
                  value: m, child: Text(label));
            }).toList(),
            onChanged: (v) => setState(() => _selectedMonth = v),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int monthTotal, int txnCount) {
    final paymentDay = _card.paymentDay;
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // 利用合計（主役）
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                    width: 1.5),
              ),
              child: Column(
                children: [
                  const Text('利用合計',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    formatYen(monthTotal),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 件数 + 引落予定日
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      const Text('件数',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 2),
                      Text('$txnCount 件',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // 引落予定日: タップで編集ダイアログ
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _editPaymentDay,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('引落予定日',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF9CA3AF))),
                              const SizedBox(width: 2),
                              const Icon(Icons.edit,
                                  size: 10, color: Color(0xFF9CA3AF)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                              paymentDay == null
                                  ? '未設定（タップで設定）'
                                  : '毎月 $paymentDay 日',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: paymentDay == null
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFF1A237E))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyList(List<core.Transaction> txns) {
    if (txns.isEmpty) {
      return const Center(
        child: Text('この期間の利用はありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    return ListView.separated(
      itemCount: txns.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final t = txns[i];
        return _historyRow(t);
      },
    );
  }

  Widget _historyRow(core.Transaction t) {
    final dateLabel =
        '${t.date.month.toString().padLeft(2, '0')}/${t.date.day.toString().padLeft(2, '0')}';
    final yearLabel = '${t.date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          // 日付
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        fontFamily: 'monospace')),
                Text(yearLabel,
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 明細（カテゴリ + 説明）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${t.category.major}${t.category.sub.isNotEmpty ? ' · ${t.category.sub}' : ''}',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 金額
          Text(
            '-${formatYen(t.amount)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  // ─── 月別請求推移ページ（タブ2の本体） ──
  Widget _monthlyBillingPage() {
    final name = _card.name;
    final billing = <String, int>{};
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.paymentMethod != name) continue;
      final ym =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      billing[ym] = (billing[ym] ?? 0) + t.amount;
    }
    if (billing.isEmpty) {
      return const Center(
        child: Text('まだ利用履歴がありません',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    final entries = billing.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    // 全体の最大値を取得（バー幅の正規化用）
    final maxAmount =
        entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        return _billingRow(e.key, e.value, maxAmount: maxAmount);
      },
    );
  }

  Widget _billingRow(String yearMonth, int amount,
      {required int maxAmount}) {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final paymentDay = _card.paymentDay;
    String? billingLabel;
    if (paymentDay != null) {
      final billYear = month == 12 ? year + 1 : year;
      final billMonth = month == 12 ? 1 : month + 1;
      billingLabel =
          '$billYear/${billMonth.toString().padLeft(2, '0')}/${paymentDay.toString().padLeft(2, '0')} 引落';
    }
    final ratio = maxAmount > 0 ? (amount / maxAmount).clamp(0.0, 1.0) : 0.0;
    return InkWell(
      onTap: () {
        setState(() => _selectedMonth = DateTime(year, month));
        // 明細タブに切替（その月の利用を見られるよう）
        _tabController.animateTo(0);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
          ),
        ),
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
                Text(formatYen(amount),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: Color(0xFFDC2626))),
              ],
            ),
            const SizedBox(height: 6),
            // 棒グラフ（金額比較で視覚化）
            Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
            if (billingLabel != null) ...[
              const SizedBox(height: 4),
              Text(billingLabel,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1A237E),
                      fontFamily: 'monospace')),
            ],
          ],
        ),
      ),
    );
  }

  // ─── 引落予定日 編集 ──
  Future<void> _editPaymentDay() async {
    int? selected = _card.paymentDay;
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('引落予定日を設定'),
          content: SizedBox(
            width: 280,
            child: DropdownButtonFormField<int?>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: '毎月',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— 未設定 —',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                ),
                for (var d = 1; d <= 31; d++)
                  DropdownMenuItem<int?>(
                    value: d,
                    child: Text('$d 日'),
                  ),
              ],
              onChanged: (v) => setLocal(() => selected = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                confirmed = true;
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      }),
    );
    if (!confirmed) return;
    try {
      final cfg = await SettingsRepository.instance.loadPayments();
      final newCards = <core.RegisteredCreditCard>[];
      core.RegisteredCreditCard? updatedSelf;
      for (final c in cfg.creditCards) {
        if (c.id == _card.id) {
          final newC = c.copyWith(
            paymentDay: selected,
            clearPaymentDay: selected == null,
          );
          newCards.add(newC);
          updatedSelf = newC;
        } else {
          newCards.add(c);
        }
      }
      await SettingsRepository.instance.savePayments(
        core.PaymentMethodsConfig(
          bankAccounts: cfg.bankAccounts,
          creditCards: newCards,
        ),
      );
      PaymentsChangeNotifier.instance.notifyChanged();
      if (!mounted) return;
      setState(() {
        if (updatedSelf != null) _updatedCard = updatedSelf;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(selected == null
              ? '引落予定日をクリアしました'
              : '引落予定日を毎月 $selected 日 に設定しました'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

  // ─── 月別請求の追加ダイアログ（過去請求を一括入力するため） ──
  Future<void> _showAddBillingDialog() async {
    final now = DateTime.now();
    int year = now.year;
    int month = now.month;
    final amountCtrl = NoComposingUnderlineController();
    final memoCtrl =
        TextEditingController(text: '$month月のオリコ請求まとめ');
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('月別請求を追加',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 年月
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: year,
                        decoration: const InputDecoration(
                          labelText: '年',
                          floatingLabelBehavior:
                              FloatingLabelBehavior.always,
                        ),
                        items: [
                          for (var y = now.year - 5;
                              y <= now.year + 1;
                              y++)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => year = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: month,
                        decoration: const InputDecoration(
                          labelText: '月',
                          floatingLabelBehavior:
                              FloatingLabelBehavior.always,
                        ),
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(value: m, child: Text('$m月')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setLocal(() {
                              month = v;
                              // メモも月変更で自動更新（ユーザーが変えてなければ）
                              memoCtrl.text =
                                  '$month月の${_card.name}請求まとめ';
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    HalfWidthDigitsFormatter(),
                    ThousandsSeparatorInputFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: '請求金額（円）',
                    prefixText: '¥ ',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: memoCtrl,
                  decoration: const InputDecoration(
                    labelText: '摘要',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '※ 1取引として登録します。月末日付・カテゴリは「特別出費/高額投資」固定',
                  style:
                      TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                confirmed = true;
                Navigator.pop(ctx);
              },
              child: const Text('追加'),
            ),
          ],
        );
      }),
    );
    if (!confirmed) return;
    final amount = parseAmount(amountCtrl.text);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金額を正しく入力してください')),
      );
      return;
    }
    // その月の月末日を計算
    final lastDay = DateTime(year, month + 1, 0).day;
    final txn = core.Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: DateTime(year, month, lastDay),
      type: core.TransactionType.expense,
      category: const core.Category(
          major: '9.特別出費', sub: '高額投資'),
      paymentMethod: _card.name,
      description: memoCtrl.text.trim().isEmpty
          ? '$month月の${_card.name}請求'
          : memoCtrl.text.trim(),
      amount: amount,
      memo: '月別請求として一括登録（カード詳細画面から追加）',
    );
    try {
      await TransactionRepository.instance.add(txn);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$year年$month月の請求 ${formatYen(amount)} を追加しました'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('追加に失敗しました: $e')),
      );
    }
  }
}
