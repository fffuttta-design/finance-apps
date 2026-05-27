import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/income_source_repository.dart';
import '../utils/formatters.dart';
import '../widgets/centered_body.dart';

/// 収入マスタのCRUD画面。
///
/// 継続収入・単発収入をテンプレ化して登録、入金時に呼び出して使う。
class IncomeMasterScreen extends StatefulWidget {
  const IncomeMasterScreen({super.key});

  @override
  State<IncomeMasterScreen> createState() => _IncomeMasterScreenState();
}

class _IncomeMasterScreenState extends State<IncomeMasterScreen> {
  final _repo = IncomeSourceRepository.instance;
  IncomeSourceConfig? _config;

  /// アーカイブ済みも一覧に表示するか。デフォルト false（隠す）。
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.load();
    if (!mounted) return;
    setState(() => _config = c);
  }

  Future<void> _save() async {
    final c = _config;
    if (c != null) await _repo.save(c);
  }

  void _update(List<IncomeSource> newList) {
    setState(() => _config = _config!.copyWith(sources: newList));
    _save();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<IncomeSource?> _editDialog(
      BuildContext context, IncomeSource? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
    // 取引先 / 想定金額 は UI から廃止。既存値は initial 経由で保持。
    final dayCtrl =
        TextEditingController(text: initial?.dayOfMonth?.toString() ?? '');
    IncomeCycle cycle = initial?.cycle ?? IncomeCycle.monthly;

    return showModalBottomSheet<IncomeSource?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isValid = nameCtrl.text.trim().isNotEmpty;

          void onSave() {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              Navigator.pop(ctx, null);
              return;
            }
            final day = int.tryParse(dayCtrl.text.trim());
            final memo =
                memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
            // 取引先 / 想定金額 は UI 廃止。既存値があれば維持。
            final result = IncomeSource(
              id: initial?.id ?? _genId(),
              name: name,
              clientName: initial?.clientName,
              expectedAmount: initial?.expectedAmount,
              cycle: cycle,
              dayOfMonth: cycle == IncomeCycle.oneTime ? null : day,
              memo: memo,
            );
            Navigator.pop(ctx, result);
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            initial == null ? '収入マスタを追加' : '収入マスタを編集',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Color(0xFF9CA3AF)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(ctx, null),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Expanded(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: nameCtrl,
                            autofocus: initial == null,
                            decoration: const InputDecoration(
                              labelText: '名称（必須）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            onChanged: (_) => setLocal(() {}),
                          ),
                          const SizedBox(height: 16),
                          const Text('発生サイクル',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280))),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<IncomeCycle>(
                            initialValue: cycle,
                            decoration: const InputDecoration(
                              isDense: true,
                            ),
                            items: IncomeCycle.values
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(IncomeSource(
                                              id: '_', name: '_', cycle: c)
                                          .cycleLabel),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setLocal(() => cycle = v);
                            },
                          ),
                          if (cycle != IncomeCycle.oneTime) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: dayCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 2,
                              decoration: const InputDecoration(
                                labelText: '入金日（1〜31、任意）',
                                counterText: '',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          // 備考欄（1行）
                          TextField(
                            controller: memoCtrl,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: '備考（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('キャンセル'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: isValid ? onSave : null,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('保存',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _add() async {
    final r = await _editDialog(context, null);
    if (r == null) return;
    _update([..._config!.sources, r]);
  }

  Future<void> _edit(int i) async {
    final r = await _editDialog(context, _config!.sources[i]);
    if (r == null) return;
    final list = [..._config!.sources];
    list[i] = r;
    _update(list);
  }

  Future<void> _delete(int i) async {
    final s = _config!.sources[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.name} を削除？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    final list = [..._config!.sources]..removeAt(i);
    _update(list);
  }

  /// アーカイブ状態を切り替え（archived ⇔ active）。
  void _toggleArchive(int i) {
    final list = [..._config!.sources];
    list[i] = list[i].copyWith(archived: !list[i].archived);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('収入マスタ',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          IconButton(
            icon: Icon(
              _showArchived
                  ? Icons.archive
                  : Icons.archive_outlined,
              color: _showArchived
                  ? const Color(0xFFEA580C)
                  : const Color(0xFF6B7280),
            ),
            tooltip: _showArchived
                ? 'アーカイブを隠す'
                : 'アーカイブも表示',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '収入マスタを追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: CenteredBody(
        child: Builder(builder: (ctx) {
          if (config == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // フィルタ: 表示モードに応じて actives / all を切替。
          // インデックスは _config.sources 上の元位置を保つ（edit/delete用）。
          final visibleIdx = <int>[];
          for (var i = 0; i < config.sources.length; i++) {
            if (_showArchived || !config.sources[i].archived) {
              visibleIdx.add(i);
            }
          }
          if (visibleIdx.isEmpty) return _empty();
          return SafeArea(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: visibleIdx.length,
              itemBuilder: (ctx, i) {
                final origIdx = visibleIdx[i];
                final s = config.sources[origIdx];
                return _tile(
                  s,
                  () => _edit(origIdx),
                  () => _delete(origIdx),
                  () => _toggleArchive(origIdx),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _tile(IncomeSource s, VoidCallback onEdit, VoidCallback onDelete,
      VoidCallback onArchiveToggle) {
    final archived = s.archived;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: archived ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: archived
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_money,
                  size: 18,
                  color: archived
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF16A34A)),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(s.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: archived
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF111827),
                              decoration: archived
                                  ? TextDecoration.lineThrough
                                  : null),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (archived) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('アーカイブ',
                            style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 18,
                    color: const Color(0xFFEA580C)),
                tooltip: archived ? 'アーカイブ解除' : 'アーカイブ',
                onPressed: onArchiveToggle,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit,
                    size: 18, color: Color(0xFF6B7280)),
                onPressed: onEdit,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFDC2626)),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (s.clientName != null)
                _chip(Icons.business, s.clientName!),
              _chip(Icons.repeat, s.cycleLabel),
              if (s.dayOfMonth != null)
                _chip(Icons.event, '毎月${s.dayOfMonth}日'),
              if (s.expectedAmount != null)
                _chip(Icons.payments,
                    formatYen(s.expectedAmount!),
                    color: const Color(0xFF16A34A)),
            ],
          ),
          if (s.memo != null) ...[
            const SizedBox(height: 4),
            Text(s.memo!,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) {
    final c = color ?? const Color(0xFF6B7280);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11, color: c)),
      ],
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.attach_money,
                size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('収入マスタが未登録です',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            const Text('継続/単発の収入源を登録して、入金時にワンタップで記録できます',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('収入マスタを追加'),
              onPressed: _add,
            ),
          ],
        ),
      );
}
