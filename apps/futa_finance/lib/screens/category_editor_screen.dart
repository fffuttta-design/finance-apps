import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';

/// 大カテゴリ・小カテゴリのCRUD画面。
///
/// - 大カテゴリ: 追加・名称変更・削除・順序変更（並べ替え）
/// - 小カテゴリ: 各大カテゴリの中で追加・名称変更・削除
class CategoryEditorScreen extends StatefulWidget {
  const CategoryEditorScreen({super.key});

  @override
  State<CategoryEditorScreen> createState() => _CategoryEditorScreenState();
}

class _CategoryEditorScreenState extends State<CategoryEditorScreen> {
  final _repo = SettingsRepository();
  CategoryConfig? _config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.loadCategories();
    if (!mounted) return;
    setState(() => _config = c);
  }

  Future<void> _save() async {
    final c = _config;
    if (c != null) await _repo.saveCategories(c);
  }

  void _update(List<MajorCategory> newMajors) {
    setState(() => _config = _config!.copyWith(majors: newMajors));
    _save();
  }

  void _addMajor() async {
    final name = await _promptText(context, title: '大カテゴリを追加', label: '名前');
    if (name == null || name.trim().isEmpty) return;
    final list = [..._config!.majors, MajorCategory(name: name.trim(), subs: [])];
    _update(list);
  }

  void _renameMajor(int index) async {
    final current = _config!.majors[index].name;
    final name = await _promptText(context,
        title: '大カテゴリ名を変更', label: '名前', initial: current);
    if (name == null || name.trim().isEmpty) return;
    final list = [..._config!.majors];
    list[index] = list[index].copyWith(name: name.trim());
    _update(list);
  }

  void _deleteMajor(int index) async {
    final ok = await _confirm(context,
        title: '${_config!.majors[index].displayName(index)} を削除？',
        body: 'このカテゴリ内の小カテゴリも全て削除されます。');
    if (!ok) return;
    final list = [..._config!.majors]..removeAt(index);
    _update(list);
  }

  void _moveMajor(int oldIndex, int newIndex) {
    final list = [..._config!.majors];
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _update(list);
  }

  void _addSub(int majorIndex) async {
    final name = await _promptText(context, title: '小カテゴリを追加', label: '名前');
    if (name == null || name.trim().isEmpty) return;
    final list = [..._config!.majors];
    final major = list[majorIndex];
    list[majorIndex] =
        major.copyWith(subs: [...major.subs, name.trim()]);
    _update(list);
  }

  void _renameSub(int majorIndex, int subIndex) async {
    final current = _config!.majors[majorIndex].subs[subIndex];
    final name = await _promptText(context,
        title: '小カテゴリ名を変更', label: '名前', initial: current);
    if (name == null || name.trim().isEmpty) return;
    final list = [..._config!.majors];
    final subs = [...list[majorIndex].subs];
    subs[subIndex] = name.trim();
    list[majorIndex] = list[majorIndex].copyWith(subs: subs);
    _update(list);
  }

  void _deleteSub(int majorIndex, int subIndex) async {
    final ok = await _confirm(context,
        title: '${_config!.majors[majorIndex].subs[subIndex]} を削除？',
        body: '');
    if (!ok) return;
    final list = [..._config!.majors];
    final subs = [...list[majorIndex].subs]..removeAt(subIndex);
    list[majorIndex] = list[majorIndex].copyWith(subs: subs);
    _update(list);
  }

  Future<String?> _promptText(BuildContext context,
      {required String title, required String label, String? initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context,
      {required String title, required String body}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: body.isEmpty ? null : Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'カテゴリ編集',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '大カテゴリを追加',
            onPressed: config == null ? null : _addMajor,
          ),
        ],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: config.majors.length,
                onReorder: _moveMajor,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final major = config.majors[index];
                  return _MajorTile(
                    key: ValueKey('major-$index-${major.name}'),
                    index: index,
                    major: major,
                    onRename: () => _renameMajor(index),
                    onDelete: () => _deleteMajor(index),
                    onAddSub: () => _addSub(index),
                    onRenameSub: (subIdx) => _renameSub(index, subIdx),
                    onDeleteSub: (subIdx) => _deleteSub(index, subIdx),
                  );
                },
              ),
            ),
    );
  }
}

class _MajorTile extends StatelessWidget {
  final int index;
  final MajorCategory major;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddSub;
  final void Function(int subIndex) onRenameSub;
  final void Function(int subIndex) onDeleteSub;

  const _MajorTile({
    super.key,
    required this.index,
    required this.major,
    required this.onRename,
    required this.onDelete,
    required this.onAddSub,
    required this.onRenameSub,
    required this.onDeleteSub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          leading: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_indicator, color: Color(0xFF9CA3AF)),
          ),
          title: Text(
            major.displayName(index),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827)),
          ),
          subtitle: Text(
            '${major.subs.length} 件の小カテゴリ',
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit,
                    size: 18, color: Color(0xFF6B7280)),
                onPressed: onRename,
                tooltip: '名前変更',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFDC2626)),
                onPressed: onDelete,
                tooltip: '削除',
              ),
            ],
          ),
          children: [
            ...major.subs.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value;
              return Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text(
                      '・$s',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF374151)),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit,
                        size: 16, color: Color(0xFF9CA3AF)),
                    onPressed: () => onRenameSub(i),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close,
                        size: 16, color: Color(0xFFDC2626)),
                    onPressed: () => onDeleteSub(i),
                  ),
                ],
              );
            }),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('小カテゴリを追加'),
              onPressed: onAddSub,
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1A237E)),
            ),
          ],
        ),
      ),
    );
  }
}
