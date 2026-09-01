import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/special_expense.dart';
import '../data/special_expense_repository.dart';
import '../theme/app_theme.dart';
import 'special_expense_detail_screen.dart';

/// 特別支出（旅行・引っ越しなど）のホーム用カード。
/// 進行中のものがあればその名前を、無ければ入口だけを出す。
class SpecialExpenseSummaryCard extends StatelessWidget {
  const SpecialExpenseSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return const SizedBox.shrink();
    return StreamBuilder<List<SpecialExpense>>(
      stream: SpecialExpenseRepository.instance.watch(hid),
      builder: (context, snap) {
        final all = snap.data ?? const <SpecialExpense>[];
        final open = all.where((e) => !e.settled).toList();
        final label = open.isEmpty
            ? '旅行やイベントの出費をまとめる'
            : (open.length == 1 ? open.first.name : '進行中 ${open.length}件');
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SpecialExpensesScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.pinkSoft, width: 1.4),
            ),
            child: Row(
              children: [
                const Icon(Icons.luggage_rounded,
                    size: 20, color: AppColors.pink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSub)),
                ),
                Text(open.isEmpty ? '作る' : '見る',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.pinkDark)),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSub),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 特別支出の一覧。進行中と、精算が済んだものを分けて出す。
class SpecialExpensesScreen extends StatefulWidget {
  const SpecialExpensesScreen({super.key});

  @override
  State<SpecialExpensesScreen> createState() => _SpecialExpensesScreenState();
}

class _SpecialExpensesScreenState extends State<SpecialExpensesScreen> {
  Future<void> _openEdit() async {
    final result = await showModalBottomSheet<SpecialExpense>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const SpecialExpenseEditSheet(),
      ),
    );
    if (result == null) return;
    final hid = HouseholdService.instance.householdId;
    final uid = AuthService.instance.currentUser?.uid;
    if (hid == null || uid == null) return;
    await SpecialExpenseRepository.instance.save(hid, result, uid);
  }

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('特別支出')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEdit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('作る'),
      ),
      body: hid == null
          ? const SizedBox.shrink()
          : StreamBuilder<List<SpecialExpense>>(
              stream: SpecialExpenseRepository.instance.watch(hid),
              builder: (context, snap) {
                final all = snap.data ?? const <SpecialExpense>[];
                if (all.isEmpty) return _empty();
                final open = all.where((e) => !e.settled).toList();
                final done = all.where((e) => e.settled).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    if (open.isNotEmpty) ...[
                      _sectionTitle('進行中'),
                      const SizedBox(height: 8),
                      ...open.map(_tile),
                    ],
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _sectionTitle('精算が済んだもの'),
                      const SizedBox(height: 8),
                      ...done.map(_tile),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text));

  Widget _tile(SpecialExpense e) {
    final k = kindOf(e.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SpecialExpenseDetailScreen(item: e)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: k.color.withValues(alpha: 0.25),
                  child: Icon(k.icon, size: 18, color: AppColors.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${k.name}・${formatSpecialExpensePeriod(e)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ],
                  ),
                ),
                if (e.settled)
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppColors.income),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.luggage_rounded, size: 48, color: AppColors.pinkSoft),
              SizedBox(height: 12),
              Text('まだありません',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.textSub)),
              SizedBox(height: 6),
              Text('旅行やライブなど、日をまたぐ出費をひとまとめにして\n合計と精算を出せます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            ],
          ),
        ),
      );
}

/// 「2026/9/27〜9/29」の形で期間を短く表す。
String formatSpecialExpensePeriod(SpecialExpense e) {
  String md(DateTime d) => '${d.month}/${d.day}';
  if (e.end == null) return '${e.start.year}/${md(e.start)}';
  return '${e.start.year}/${md(e.start)}〜${md(e.endOrStart)}';
}

/// 特別支出の作成・編集シート。
class SpecialExpenseEditSheet extends StatefulWidget {
  const SpecialExpenseEditSheet({super.key, this.editing});
  final SpecialExpense? editing;

  @override
  State<SpecialExpenseEditSheet> createState() =>
      _SpecialExpenseEditSheetState();
}

class _SpecialExpenseEditSheetState extends State<SpecialExpenseEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.editing?.name ?? '');
  late String _kind = widget.editing?.kind ?? specialExpenseKinds.first.name;
  late DateTime _start = widget.editing?.start ?? DateTime.now();
  late DateTime? _end = widget.editing?.end;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final base = start ? _start : (_end ?? _start);
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (_end != null && _end!.isBefore(d)) _end = d;
      } else {
        _end = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.editing == null ? '特別支出を作る' : '特別支出を直す',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.editing == null,
              decoration: const InputDecoration(
                labelText: '名前',
                hintText: '例：仙台・松島旅行',
              ),
            ),
            const SizedBox(height: 16),
            const Text('種類',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSub)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: specialExpenseKinds.map((k) {
                final sel = k.name == _kind;
                return ChoiceChip(
                  selected: sel,
                  onSelected: (_) => setState(() => _kind = k.name),
                  avatar: Icon(k.icon,
                      size: 16, color: sel ? Colors.white : AppColors.text),
                  label: Text(k.name),
                  selectedColor: AppColors.pink,
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : AppColors.text,
                      fontWeight: FontWeight.w700),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _dateField('はじまり', _start, () => _pick(start: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateField('おわり', _end, () => _pick(start: false),
                      onClear:
                          _end == null ? null : () => setState(() => _end = null)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('期間に入っている日の支出は、登録するときに自動で候補に出ます。',
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('保存する'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final base = widget.editing;
    Navigator.pop(
      context,
      base == null
          ? SpecialExpense(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: name,
              kind: _kind,
              start: _start,
              end: _end,
              createdAt: DateTime.now(),
            )
          : base.copyWith(
              name: name,
              kind: _kind,
              start: _start,
              end: _end,
              clearEnd: _end == null,
            ),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap,
      {VoidCallback? onClear}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? const Icon(Icons.calendar_today_rounded, size: 16)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null ? '未定' : '${value.year}/${value.month}/${value.day}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
