import 'package:flutter/material.dart';

import '../data/budget_item.dart';
import '../data/budget_item_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// 税金・保険マスタ画面。
///
/// 法人税・消費税・社会保険料などの「支払予定」を登録する。ここで登録した
/// 予定は資金繰り（ランウェイ）予測に反映される（[BudgetItem] を流用）。
/// 金額は手入力の見積もり。事業/個人モードでデータは分かれる。
class BudgetItemsScreen extends StatefulWidget {
  const BudgetItemsScreen({super.key});

  @override
  State<BudgetItemsScreen> createState() => _BudgetItemsScreenState();
}

class _BudgetItemsScreenState extends State<BudgetItemsScreen> {
  static const _monthNames = [
    '1月', '2月', '3月', '4月', '5月', '6月',
    '7月', '8月', '9月', '10月', '11月', '12月',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('税金・保険',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: AnimatedBuilder(
        animation: BudgetItemRepository.instance,
        builder: (context, _) => FutureBuilder<BudgetItemsConfig>(
          future: BudgetItemRepository.instance.load(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _body(snap.data!);
          },
        ),
      ),
    );
  }

  Widget _body(BudgetItemsConfig cfg) {
    final annual = cfg.items.fold<int>(0, (s, i) => s + i.annualAmount);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // 説明
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '法人税・消費税・社会保険料などの支払予定を登録します。'
                  'ここで登録した予定は資金繰り（ランウェイ）予測に反映されます。'
                  '金額は手入力の見積もりでOK。あとで実績に合わせて直せます。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 年間合計
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_outlined,
                  size: 18, color: Color(0xFF1A237E)),
              const SizedBox(width: 8),
              const Text('年間の支払予定 合計',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const Spacer(),
              Text(formatYen(annual),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A237E),
                      fontFamily: 'monospace')),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // アクション
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _editItem(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('項目を追加'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addCorporatePreset(cfg),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('法人プリセット'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (cfg.items.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text('まだ項目がありません。\n「項目を追加」か「法人プリセット」から登録してください。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          )
        else
          ...cfg.items.map(_itemTile),
      ],
    );
  }

  Widget _itemTile(BudgetItem item) {
    // 支払時期の要約（毎月 or 指定月）。
    final months = item.schedule.map((s) => s.month).toSet().toList()..sort();
    String when;
    if (months.length >= 12) {
      when = '毎月';
    } else if (months.isEmpty) {
      when = '未設定';
    } else {
      when = months.map((m) => _monthNames[m - 1]).join('・');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        onTap: () => _editItem(item),
        leading: Text(item.kind.emoji, style: const TextStyle(fontSize: 22)),
        title: Text(item.name,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text('${item.kind.label}・$when',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('年 ${formatYen(item.annualAmount)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    fontFamily: 'monospace')),
            const SizedBox(height: 2),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  /// 法人向けプリセットを追加（既存と同名はスキップ）。
  Future<void> _addCorporatePreset(BudgetItemsConfig cfg) async {
    final existing = cfg.items.map((i) => i.name).toSet();
    // 決算9月末→申告納付は2ヶ月後の11月を既定に（ユーザーは後で月を調整可）。
    const taxMonth = 11;
    final presets = <BudgetItem>[
      _preset('法人税・地方法人税', BudgetKind.tax, [(taxMonth, 0)],
          note: '決算後（申告期限）。利益に応じて見積もりを入れてください。'),
      _preset('法人住民税（均等割含む）', BudgetKind.tax, [(taxMonth, 70000)],
          note: '赤字でも均等割（最低 年7万円〜）はかかります。'),
      _preset('法人事業税', BudgetKind.tax, [(taxMonth, 0)],
          note: '決算後（申告期限）。'),
      _preset('消費税', BudgetKind.tax, [(taxMonth, 0)],
          note: '3期目から課税事業者の想定。売上に応じて見積もり。'),
      _preset('社会保険料（会社負担）', BudgetKind.insurance,
          [for (int m = 1; m <= 12; m++) (m, 0)],
          note: '毎月の会社負担分。月額の見積もりを入れてください。'),
    ];
    final toAdd = presets.where((p) => !existing.contains(p.name)).toList();
    if (toAdd.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('法人プリセットは既に追加済みです')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('法人プリセットを追加'),
        content: Text('${toAdd.map((e) => '・${e.name}').join('\n')}\n\n'
            '金額0の項目は、あとで見積もりを入れてください。'
            '支払月は決算期（既定11月）に合わせて調整できます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('追加する')),
        ],
      ),
    );
    if (ok != true) return;
    for (final p in toAdd) {
      await BudgetItemRepository.instance.upsert(p);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${toAdd.length}件を追加しました')),
    );
  }

  BudgetItem _preset(String name, BudgetKind kind, List<(int, int)> months,
      {String? note}) {
    return BudgetItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_${name.hashCode}',
      name: name,
      kind: kind,
      schedule: [
        for (final (m, amt) in months)
          ScheduledPayment(month: m, day: 27, amount: amt),
      ],
      note: note,
    );
  }

  /// 項目の追加/編集ダイアログ（ボトムシート）。
  Future<void> _editItem(BudgetItem? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    var kind = existing?.kind ?? BudgetKind.tax;
    var day = existing?.schedule.isNotEmpty == true
        ? existing!.schedule.first.day
        : 27;
    // 支払予定の編集行（月 + 金額）。
    final rows = <_ScheduleRow>[];
    if (existing != null && existing.schedule.isNotEmpty) {
      for (final s in existing.schedule) {
        rows.add(_ScheduleRow(s.month, s.amount));
      }
    } else {
      rows.add(_ScheduleRow(DateTime.now().month, 0));
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.85,
                maxChildSize: 0.95,
                minChildSize: 0.5,
                builder: (_, scrollCtrl) => ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(existing == null ? '項目を追加' : '項目を編集',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),

                    _label('名前'),
                    TextField(
                      controller: nameCtrl,
                      decoration: _dec('例: 法人税・消費税・社会保険料'),
                    ),
                    const SizedBox(height: 16),

                    _label('種別'),
                    Wrap(
                      spacing: 8,
                      children: BudgetKind.values.map((k) {
                        final sel = k == kind;
                        return ChoiceChip(
                          label: Text('${k.emoji} ${k.label}'),
                          selected: sel,
                          onSelected: (_) => setSheet(() => kind = k),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        _label('支払予定'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setSheet(() {
                            // 毎月（12ヶ月）にする：金額は1行目の値を流用。
                            final amt = rows.isNotEmpty ? rows.first.amount : 0;
                            rows
                              ..clear()
                              ..addAll([
                                for (int m = 1; m <= 12; m++)
                                  _ScheduleRow(m, amt),
                              ]);
                          }),
                          icon: const Icon(Icons.repeat, size: 16),
                          label: const Text('毎月にする'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...rows.asMap().entries.map((e) {
                      final idx = e.key;
                      final row = e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            // 月
                            SizedBox(
                              width: 92,
                              child: DropdownButtonFormField<int>(
                                initialValue: row.month,
                                isDense: true,
                                decoration: _dec(null),
                                items: [
                                  for (int m = 1; m <= 12; m++)
                                    DropdownMenuItem(
                                        value: m,
                                        child: Text(_monthNames[m - 1])),
                                ],
                                onChanged: (v) =>
                                    setSheet(() => row.month = v ?? row.month),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 金額
                            Expanded(
                              child: TextFormField(
                                initialValue: row.amount > 0
                                    ? formatAmount(row.amount)
                                    : '',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  HalfWidthDigitsFormatter(),
                                  ThousandsSeparatorInputFormatter(),
                                ],
                                decoration: _dec('金額（円）').copyWith(
                                    prefixText: '¥ '),
                                onChanged: (v) =>
                                    row.amount = parseAmount(v) ?? 0,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Color(0xFFDC2626)),
                              onPressed: rows.length <= 1
                                  ? null
                                  : () => setSheet(() => rows.removeAt(idx)),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setSheet(() =>
                            rows.add(_ScheduleRow(DateTime.now().month, 0))),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('支払月を追加'),
                      ),
                    ),
                    const SizedBox(height: 8),

                    _label('支払日（目安）'),
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<int>(
                        initialValue: day,
                        isDense: true,
                        decoration: _dec(null),
                        items: [
                          for (int d = 1; d <= 28; d++)
                            DropdownMenuItem(value: d, child: Text('$d 日')),
                        ],
                        onChanged: (v) => setSheet(() => day = v ?? day),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _label('メモ（任意）'),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: _dec('決算期・算定根拠など'),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        if (existing != null) ...[
                          OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              await _confirmDelete(existing);
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('削除'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  const SnackBar(content: Text('名前を入力してください')),
                                );
                                return;
                              }
                              final schedule = rows
                                  .map((r) => ScheduledPayment(
                                      month: r.month,
                                      day: day,
                                      amount: r.amount))
                                  .toList();
                              final item = BudgetItem(
                                id: existing?.id ??
                                    DateTime.now()
                                        .microsecondsSinceEpoch
                                        .toString(),
                                name: name,
                                kind: kind,
                                schedule: schedule,
                                actuals: existing?.actuals ?? const [],
                                note: noteCtrl.text.trim().isEmpty
                                    ? null
                                    : noteCtrl.text.trim(),
                              );
                              await BudgetItemRepository.instance.upsert(item);
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('保存する'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(BudgetItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${item.name}」を削除しますか？'),
        content: const Text('元に戻せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await BudgetItemRepository.instance.remove(item.id);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280))),
      );

  InputDecoration _dec(String? hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: const OutlineInputBorder(),
      );
}

/// 編集中の支払予定1行（月＋金額）。
class _ScheduleRow {
  int month;
  int amount;
  _ScheduleRow(this.month, this.amount);
}
