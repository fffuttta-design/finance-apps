import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/household_service.dart';
import '../data/plan_item.dart';
import '../data/plan_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_button.dart';
import 'plan_detail_screen.dart';

/// プランニング：やりたいこと／行きたい場所／行きたいお店（世帯共有）。
class PlanningScreen extends StatelessWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('プランニング'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.star_rounded, color: AppColors.pink),
        ),
        actions: const [SettingsButton()],
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<PlanItem>>(
              stream: PlanRepository.instance.watch(hid),
              builder: (context, snap) {
                final all = snap.data ?? const <PlanItem>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  children: [
                    for (final kind in PlanKind.values)
                      _KindSection(
                        hid: hid,
                        kind: kind,
                        items: all.where((e) => e.kind == kind).toList()
                          ..sort((a, b) => a.order.compareTo(b.order)),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _KindSection extends StatelessWidget {
  final String hid;
  final PlanKind kind;
  final List<PlanItem> items;
  const _KindSection({
    required this.hid,
    required this.kind,
    required this.items,
  });

  String get _uid => AuthService.instance.currentUser?.uid ?? '';

  Future<void> _addOrEdit(BuildContext context, {PlanItem? editing}) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(kind: kind, editing: editing),
    );
    if (result == null) return;
    final repo = PlanRepository.instance;
    if (result.delete && editing != null) {
      await repo.delete(hid, editing.id);
      return;
    }
    if (editing != null) {
      await repo.save(
          hid, editing.copyWith(name: result.name, memo: result.memo), _uid);
    } else {
      final nextOrder =
          items.isEmpty ? 0 : items.map((e) => e.order).reduce((a, b) => a > b ? a : b) + 1;
      await repo.save(
        hid,
        PlanItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          kind: kind,
          name: result.name,
          memo: result.memo,
          order: nextOrder,
        ),
        _uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(kind.label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.pinkSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${items.length}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.pinkDark)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addOrEdit(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('追加'),
                ),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 0, 4),
                child: Text('まだありません。「追加」から登録してね',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final reordered = [...items];
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, moved);
                  await PlanRepository.instance
                      .reorder(hid, reordered, _uid);
                },
                itemBuilder: (context, i) {
                  final it = items[i];
                  return _PlanTile(
                    key: ValueKey(it.id),
                    index: i,
                    item: it,
                    onToggle: () => PlanRepository.instance
                        .save(hid, it.copyWith(done: !it.done), _uid),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PlanDetailScreen(item: it)),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final int index;
  final PlanItem item;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  const _PlanTile({
    super.key,
    required this.index,
    required this.item,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: item.done,
              activeColor: AppColors.pink,
              shape: const CircleBorder(),
              onChanged: (_) => onToggle(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: item.done ? AppColors.textSub : AppColors.text,
                      decoration:
                          item.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (item.memo != null && item.memo!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(item.memo!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ),
                ],
              ),
            ),
            // コメントが付いていれば件数バッジ。
            if (item.commentCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 14, color: AppColors.pinkDark),
                    const SizedBox(width: 2),
                    Text('${item.commentCount}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.pinkDark)),
                  ],
                ),
              ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_handle_rounded,
                    size: 20, color: AppColors.textSub),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditResult {
  final String name;
  final String? memo;
  final bool delete;
  const _EditResult(this.name, this.memo, {this.delete = false});
}

class _EditDialog extends StatefulWidget {
  final PlanKind kind;
  final PlanItem? editing;
  const _EditDialog({required this.kind, this.editing});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.editing?.name ?? '');
  late final TextEditingController _memo =
      TextEditingController(text: widget.editing?.memo ?? '');

  @override
  void dispose() {
    _name.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    return AlertDialog(
      title: Text(isEdit ? '${widget.kind.label}を編集' : '${widget.kind.label}を追加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名前（必須）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memo,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '詳細（任意）',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _EditResult('', null, delete: true)),
            child: const Text('削除', style: TextStyle(color: AppColors.expense)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            final n = _name.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(
                context,
                _EditResult(
                    n, _memo.text.trim().isEmpty ? null : _memo.text.trim()));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
