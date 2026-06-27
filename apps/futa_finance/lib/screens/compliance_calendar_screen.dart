import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/compliance_task.dart';
import '../data/compliance_task_repository.dart';

/// 手続き・届出カレンダー画面。
///
/// 算定基礎届・労働保険の年度更新・申告期限など、会社の手続き締切を管理する。
/// お金（税金・保険マスタ）とは別で、「いつ何をやるか」のTODO/締切。
class ComplianceCalendarScreen extends StatefulWidget {
  const ComplianceCalendarScreen({super.key});

  @override
  State<ComplianceCalendarScreen> createState() =>
      _ComplianceCalendarScreenState();
}

class _ComplianceCalendarScreenState extends State<ComplianceCalendarScreen> {
  static const _monthNames = [
    '1月', '2月', '3月', '4月', '5月', '6月',
    '7月', '8月', '9月', '10月', '11月', '12月',
  ];

  final _repo = ComplianceTaskRepository.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('手続き・届出カレンダー',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: AnimatedBuilder(
        animation: _repo,
        builder: (context, _) => FutureBuilder<ComplianceTasksConfig>(
          future: _repo.load(),
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

  Widget _body(ComplianceTasksConfig cfg) {
    final now = DateTime.now();
    // 次回期限つきタスク（毎年/毎月）を期日順に。
    final dated = cfg.tasks
        .map((t) => (task: t, due: t.nextDueFrom(now)))
        .where((e) => e.due != null)
        .toList()
      ..sort((a, b) => a.due!.compareTo(b.due!));
    final asNeeded = cfg.tasks
        .where((t) => t.recurrence == ComplianceRecurrence.asNeeded)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_available, size: 18, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '算定基礎届・労働保険の年度更新・各種申告期限など、会社の手続きの締切を管理します。'
                  'チェックを入れると今年ぶんは完了として翌年に送られます。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF065F46)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // アクション
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _editTask(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('手続きを追加'),
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
        const SizedBox(height: 18),

        if (cfg.tasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text(
                'まだ手続きがありません。\n「手続きを追加」か「法人プリセット」から登録してください。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text('期限が近い順',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
          ),
          ...dated.map((e) => _taskTile(e.task, e.due!, now)),
          if (asNeeded.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Text('随時（都度対応）',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280))),
            ),
            ...asNeeded.map((t) => _taskTile(t, null, now)),
          ],
        ],
      ],
    );
  }

  Widget _taskTile(ComplianceTask t, DateTime? due, DateTime now) {
    String dueLabel;
    Color dueColor = const Color(0xFF6B7280);
    if (due == null) {
      dueLabel = '随時';
    } else {
      final days = due.difference(DateTime(now.year, now.month, now.day)).inDays;
      dueLabel = '${due.year}/${due.month}/${due.day}'
          '（${days == 0 ? '今日' : days < 0 ? '期限超過' : 'あと$days日'}）';
      if (days < 0) {
        dueColor = const Color(0xFFDC2626);
      } else if (days <= 14) {
        dueColor = const Color(0xFFEA580C);
      }
    }
    final isYearly = t.recurrence == ComplianceRecurrence.yearly;
    final doneThisYear = isYearly && t.doneYears.contains(now.year);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        onTap: () => _editTask(t),
        leading: Text(t.category.emoji, style: const TextStyle(fontSize: 22)),
        title: Text(t.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('${t.category.label}・${t.recurrence.label}',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            Text(dueLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: dueColor)),
            if (t.note != null && t.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(t.note!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280))),
              ),
          ],
        ),
        trailing: isYearly
            ? Tooltip(
                message: doneThisYear ? '今年は完了' : '今年ぶんを完了にする',
                child: IconButton(
                  icon: Icon(
                    doneThisYear
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: doneThisYear
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFCBD5E1),
                  ),
                  onPressed: () => _toggleDone(t, now.year),
                ),
              )
            : const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
      ),
    );
  }

  Future<void> _toggleDone(ComplianceTask t, int year) async {
    final done = [...t.doneYears];
    if (done.contains(year)) {
      done.remove(year);
    } else {
      done.add(year);
    }
    await _repo.upsert(t.copyWith(doneYears: done));
  }

  Future<void> _addCorporatePreset(ComplianceTasksConfig cfg) async {
    final existing = cfg.tasks.map((t) => t.name).toSet();
    final presets = <ComplianceTask>[
      _p('源泉所得税の納付（納期特例・上期）', ComplianceCategory.tax,
          ComplianceRecurrence.yearly,
          month: 7, day: 10, note: '1〜6月分をまとめて納付（納期の特例の場合）'),
      _p('源泉所得税の納付（納期特例・下期）', ComplianceCategory.tax,
          ComplianceRecurrence.yearly,
          month: 1, day: 20, note: '7〜12月分をまとめて納付'),
      _p('社会保険料の納付', ComplianceCategory.socialInsurance,
          ComplianceRecurrence.monthly,
          note: '前月分を当月末に口座振替'),
      _p('社会保険 算定基礎届', ComplianceCategory.socialInsurance,
          ComplianceRecurrence.yearly,
          month: 7, day: 10, note: '7/1〜7/10提出。9月以降の標準報酬月額を決定'),
      _p('労働保険 年度更新', ComplianceCategory.laborInsurance,
          ComplianceRecurrence.yearly,
          month: 7, day: 10, note: '6/1〜7/10。概算・確定保険料の申告納付'),
      _p('賞与支払届', ComplianceCategory.socialInsurance,
          ComplianceRecurrence.asNeeded,
          note: '賞与支給後5日以内'),
      _p('年末調整', ComplianceCategory.tax, ComplianceRecurrence.yearly,
          month: 12, day: 31, note: '12月給与で実施'),
      _p('給与支払報告書・法定調書合計表', ComplianceCategory.tax,
          ComplianceRecurrence.yearly,
          month: 1, day: 31, note: '1/31まで（市区町村・税務署へ提出）'),
      _p('償却資産申告', ComplianceCategory.tax, ComplianceRecurrence.yearly,
          month: 1, day: 31, note: '1/31まで（固定資産がある場合）'),
      _p('法人税・消費税・地方税の申告納付', ComplianceCategory.tax,
          ComplianceRecurrence.yearly,
          month: 11, day: 30, note: '決算後2ヶ月（決算9月末→11月末）'),
      _p('決算公告・定時株主総会', ComplianceCategory.corporate,
          ComplianceRecurrence.yearly,
          month: 12, day: 31, note: '決算後3ヶ月以内（該当時）'),
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
        content: SizedBox(
          width: double.maxFinite,
          child: Text('${toAdd.map((e) => '・${e.name}').join('\n')}\n\n'
              '期限の月日は一般的な目安です。決算期や納期特例の有無に合わせて調整してください。'),
        ),
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
      await _repo.upsert(p);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${toAdd.length}件を追加しました')),
    );
  }

  ComplianceTask _p(String name, ComplianceCategory cat,
      ComplianceRecurrence rec,
      {int? month, int? day, String? note}) {
    return ComplianceTask(
      id: '${DateTime.now().microsecondsSinceEpoch}_${name.hashCode}',
      name: name,
      category: cat,
      recurrence: rec,
      month: month,
      day: day,
      note: note,
    );
  }

  Future<void> _editTask(ComplianceTask? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    var category = existing?.category ?? ComplianceCategory.tax;
    var recurrence = existing?.recurrence ?? ComplianceRecurrence.yearly;
    var month = existing?.month ?? DateTime.now().month;
    var day = existing?.day ?? lastDayOfMonth(month);

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
                    Text(existing == null ? '手続きを追加' : '手続きを編集',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),

                    _label('名前'),
                    TextField(
                      controller: nameCtrl,
                      decoration: _dec('例: 社会保険 算定基礎届'),
                    ),
                    const SizedBox(height: 16),

                    _label('分類'),
                    Wrap(
                      spacing: 8,
                      children: ComplianceCategory.values.map((c) {
                        return ChoiceChip(
                          label: Text('${c.emoji} ${c.label}'),
                          selected: c == category,
                          onSelected: (_) => setSheet(() => category = c),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    _label('繰り返し'),
                    Wrap(
                      spacing: 8,
                      children: ComplianceRecurrence.values.map((r) {
                        return ChoiceChip(
                          label: Text(r.label),
                          selected: r == recurrence,
                          onSelected: (_) => setSheet(() => recurrence = r),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // 期限の月日（随時では非表示）。
                    if (recurrence != ComplianceRecurrence.asNeeded) ...[
                      _label('期限'),
                      Row(
                        children: [
                          if (recurrence == ComplianceRecurrence.yearly) ...[
                            SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<int>(
                                initialValue: month,
                                isDense: true,
                                decoration: _dec(null),
                                items: [
                                  for (int m = 1; m <= 12; m++)
                                    DropdownMenuItem(
                                        value: m,
                                        child: Text(_monthNames[m - 1])),
                                ],
                                onChanged: (v) =>
                                    setSheet(() => month = v ?? month),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          SizedBox(
                            width: 100,
                            child: DropdownButtonFormField<int>(
                              initialValue: day.clamp(1, 31),
                              isDense: true,
                              decoration: _dec(null),
                              items: [
                                for (int d = 1; d <= 31; d++)
                                  DropdownMenuItem(
                                      value: d, child: Text('$d 日')),
                              ],
                              onChanged: (v) => setSheet(() => day = v ?? day),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (recurrence == ComplianceRecurrence.monthly)
                            const Expanded(
                              child: Text('毎月この日が期限',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF9CA3AF))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    _label('メモ（任意）'),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: _dec('提出先・必要書類など'),
                    ),
                    const SizedBox(height: 16),

                    _label('参考URL（任意）'),
                    TextField(
                      controller: urlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: _dec('手続きの案内ページなど'),
                    ),
                    if (existing?.url != null && existing!.url!.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openUrl(existing.url!),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('リンクを開く'),
                        ),
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
                                  const SnackBar(
                                      content: Text('名前を入力してください')),
                                );
                                return;
                              }
                              final asNeeded = recurrence ==
                                  ComplianceRecurrence.asNeeded;
                              final monthly =
                                  recurrence == ComplianceRecurrence.monthly;
                              final task = ComplianceTask(
                                id: existing?.id ??
                                    DateTime.now()
                                        .microsecondsSinceEpoch
                                        .toString(),
                                name: name,
                                category: category,
                                recurrence: recurrence,
                                month: asNeeded || monthly ? null : month,
                                day: asNeeded ? null : day,
                                note: noteCtrl.text.trim().isEmpty
                                    ? null
                                    : noteCtrl.text.trim(),
                                url: urlCtrl.text.trim().isEmpty
                                    ? null
                                    : urlCtrl.text.trim(),
                                doneYears: existing?.doneYears ?? const [],
                              );
                              await _repo.upsert(task);
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

  Future<void> _confirmDelete(ComplianceTask t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${t.name}」を削除しますか？'),
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
      await _repo.remove(t.id);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static int lastDayOfMonth([int? m]) {
    final now = DateTime.now();
    final mm = m ?? now.month;
    return DateTime(now.year, mm + 1, 0).day;
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
