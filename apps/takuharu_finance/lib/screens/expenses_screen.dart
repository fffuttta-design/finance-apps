import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'record_menu.dart';
import 'transaction_chat_screen.dart';

/// 支出タブ：月切替＋支出合計＋カテゴリ内訳＋支出一覧（可愛い系）。
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

enum _Sort { dateDesc, dateAsc, amountDesc, amountAsc }

extension _SortLabel on _Sort {
  String get label => switch (this) {
        _Sort.dateDesc => '日付が新しい順',
        _Sort.dateAsc => '日付が古い順',
        _Sort.amountDesc => '金額が高い順',
        _Sort.amountAsc => '金額が安い順',
      };
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _searchCtrl = TextEditingController();
  String _query = '';
  _Sort _sort = _Sort.dateDesc;
  final Set<String> _expanded = {}; // 展開中のレシート(receiptId)

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  /// 検索・並び替えを適用。
  List<core.Transaction> _applySearchSort(List<core.Transaction> list) {
    final q = _query.trim().toLowerCase();
    var l = list.where((t) {
      if (q.isEmpty) return true;
      return t.description.toLowerCase().contains(q) ||
          t.category.major.toLowerCase().contains(q) ||
          t.paymentMethod.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.dateDesc:
        l.sort((a, b) => b.date.compareTo(a.date));
      case _Sort.dateAsc:
        l.sort((a, b) => a.date.compareTo(b.date));
      case _Sort.amountDesc:
        l.sort((a, b) => b.amount.compareTo(a.amount));
      case _Sort.amountAsc:
        l.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return l;
  }

  bool _inMonth(core.Transaction t) =>
      t.date.year == _month.year && t.date.month == _month.month;

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('支出'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.shopping_bag_rounded, color: AppColors.expense),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showRecordMenu(context);
          if (changed && mounted) setState(() {});
        },
        backgroundColor: AppColors.expense,
        icon: const Icon(Icons.add_rounded),
        label: const Text('きろく',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<core.Transaction>>(
              stream: TxRepository.instance.watch(hid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? const <core.Transaction>[];
                final month = all
                    .where((t) => t.type == core.TransactionType.expense)
                    .where(_inMonth)
                    .toList()
                  ..sort((a, b) => b.date.compareTo(a.date));
                return _body(month);
              },
            ),
    );
  }

  Widget _body(List<core.Transaction> month) {
    final total = month.fold<int>(0, (s, t) => s + t.amount);
    final byCat = <String, int>{};
    for (final t in month) {
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
    }
    final cats = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _monthBar(),
        const SizedBox(height: 12),
        _totalCard(total, month.length),
        const SizedBox(height: 16),
        if (cats.isNotEmpty) ...[
          _sectionTitle('カテゴリ内訳'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [for (final e in cats) _catBar(e.key, e.value, total)],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            _sectionTitle('支出の記録'),
            const Spacer(),
            PopupMenuButton<_Sort>(
              tooltip: '並び替え',
              icon: const Icon(Icons.sort_rounded,
                  size: 20, color: AppColors.pinkDark),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => _Sort.values
                  .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: '内容・カテゴリ・支払方法で検索',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        if (month.isEmpty) _empty() else ..._buildList(month),
      ],
    );
  }

  /// 検索・並び替え・レシートまとめを適用した行ウィジェット群。
  List<Widget> _buildList(List<core.Transaction> month) {
    final rows = _applySearchSort(month);
    // receiptId が2件以上ある品目はまとめる
    final counts = <String, int>{};
    for (final t in rows) {
      final rid = t.receiptId;
      if (rid != null && rid.isNotEmpty) {
        counts[rid] = (counts[rid] ?? 0) + 1;
      }
    }
    final widgets = <Widget>[];
    final seen = <String>{};
    for (final t in rows) {
      final rid = t.receiptId;
      if (rid != null && rid.isNotEmpty && (counts[rid] ?? 0) >= 2) {
        if (seen.add(rid)) {
          final members =
              rows.where((x) => x.receiptId == rid).toList();
          widgets.add(_groupTile(rid, members));
        }
      } else {
        widgets.add(_tile(t));
      }
    }
    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
            child: Text('該当する支出がありません',
                style: TextStyle(color: AppColors.textSub, fontSize: 13))),
      ));
    }
    return widgets;
  }

  Widget _groupTile(String rid, List<core.Transaction> members) {
    final expanded = _expanded.contains(rid);
    final first = members.first;
    final total = members.fold<int>(0, (s, t) => s + t.amount);
    final store = members
        .map((t) => t.store?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'まとめ記録');
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22)),
            onTap: () => setState(() => expanded
                ? _expanded.remove(rid)
                : _expanded.add(rid)),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppColors.pinkSoft,
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.receipt_long_rounded,
                  color: AppColors.pinkDark),
            ),
            title: Text(store,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('${first.date.month}/${first.date.day}　'
                '🧾 ${members.length}件まとめ',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('-${formatYen(total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.expense)),
                Icon(expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final t in members)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: _tile(t),
            ),
      ],
    );
  }

  Widget _monthBar() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _shift(-1)),
          Text('${_month.year}年 ${_month.month}月',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _shift(1)),
        ],
      );

  Widget _totalCard(int total, int count) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF9AA2), Color(0xFFFF6B6B)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppColors.expense.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            const Text('今月の支出',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text('-${formatYen(total)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('$count件',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  Widget _catBar(String name, int amount, int total) {
    final c = categoryFor(name, income: false);
    final ratio = total == 0 ? 0.0 : amount / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(c.icon, size: 17, color: c.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Text(formatYen(amount),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppColors.pinkSoft,
              valueColor: AlwaysStoppedAnimation(c.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(core.Transaction t) {
    final c = categoryFor(t.category.major, income: false);
    final sub = '${t.date.month}/${t.date.day}　${t.category.major}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => TransactionChatScreen(transaction: t)),
          );
          if (changed == true && mounted) setState(() {});
        },
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(c.icon, color: c.color),
        ),
        title: Text(t.description.isEmpty ? t.category.major : t.description,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(sub,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chatBadge(t),
            Text('-${formatYen(t.amount)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.expense)),
          ],
        ),
      ),
    );
  }

  /// コメントが付いている取引に💬バッジ（タップでチャット）。
  Widget _chatBadge(core.Transaction t) {
    if (t.commentCount <= 0) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TransactionChatScreen(transaction: t)),
      ),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.pinkSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_rounded,
                size: 12, color: AppColors.pinkDark),
            const SizedBox(width: 3),
            Text('${t.commentCount}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.pinkDark)),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.shopping_bag_outlined,
                size: 48, color: Color(0xFFF3C6D2)),
            const SizedBox(height: 10),
            Text('${_month.month}月の支出はまだないよ',
                style: const TextStyle(color: AppColors.textSub, fontSize: 13)),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      );
}
