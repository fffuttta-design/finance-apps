import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/income_source_repository.dart';
import '../utils/formatters.dart';

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
    final clientCtrl = TextEditingController(text: initial?.clientName ?? '');
    final amountCtrl = TextEditingController(
        text: initial?.expectedAmount?.toString() ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
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
            final amount = int.tryParse(amountCtrl.text.trim());
            final day = int.tryParse(dayCtrl.text.trim());
            final clientName = clientCtrl.text.trim().isEmpty
                ? null
                : clientCtrl.text.trim();
            final memo =
                memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
            final result = IncomeSource(
              id: initial?.id ?? _genId(),
              name: name,
              clientName: clientName,
              expectedAmount: amount,
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
                          const SizedBox(height: 12),
                          TextField(
                            controller: clientCtrl,
                            decoration: const InputDecoration(
                              labelText: '取引先（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '想定金額 円（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
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
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '収入マスタを追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: config.sources.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: config.sources.length,
                      itemBuilder: (context, i) {
                        final s = config.sources[i];
                        return _tile(s, () => _edit(i), () => _delete(i));
                      },
                    ),
            ),
    );
  }

  Widget _tile(IncomeSource s, VoidCallback onEdit, VoidCallback onDelete) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_money,
                  size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF111827))),
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
