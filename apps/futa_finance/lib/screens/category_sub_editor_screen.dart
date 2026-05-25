import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../utils/category_icons.dart';

/// 1つの大カテゴリのサブカテゴリ専用CRUD画面。
///
/// ExpansionTileで重かったのを別画面遷移にして高速化。
class CategorySubEditorScreen extends StatefulWidget {
  final int majorIndex;

  const CategorySubEditorScreen({super.key, required this.majorIndex});

  @override
  State<CategorySubEditorScreen> createState() =>
      _CategorySubEditorScreenState();
}

class _CategorySubEditorScreenState extends State<CategorySubEditorScreen> {
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

  MajorCategory get _major => _config!.majors[widget.majorIndex];

  void _updateSubs(List<String> newSubs) {
    final majors = [..._config!.majors];
    majors[widget.majorIndex] = _major.copyWith(subs: newSubs);
    setState(() => _config = _config!.copyWith(majors: majors));
    _save();
  }

  Future<String?> _promptText(
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
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = await _promptText(title: '小カテゴリを追加', label: '名前');
    if (name == null || name.trim().isEmpty) return;
    _updateSubs([..._major.subs, name.trim()]);
  }

  Future<void> _rename(int i) async {
    final name = await _promptText(
        title: '小カテゴリ名を変更', label: '名前', initial: _major.subs[i]);
    if (name == null || name.trim().isEmpty) return;
    final subs = [..._major.subs];
    subs[i] = name.trim();
    _updateSubs(subs);
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${_major.subs[i]} を削除？'),
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
    final subs = [..._major.subs]..removeAt(i);
    _updateSubs(subs);
  }

  void _reorder(int oldIndex, int newIndex) {
    final subs = [..._major.subs];
    if (newIndex > oldIndex) newIndex--;
    final item = subs.removeAt(oldIndex);
    subs.insert(newIndex, item);
    _updateSubs(subs);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(iconForKey(_major.iconKey),
                color: const Color(0xFF1A237E), size: 22),
            const SizedBox(width: 8),
            Text(_major.displayName(widget.majorIndex),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '小カテゴリを追加',
            onPressed: _add,
          ),
        ],
      ),
      body: SafeArea(
        child: _major.subs.isEmpty
            ? _empty()
            : ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _major.subs.length,
                onReorder: _reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, i) {
                  final sub = _major.subs[i];
                  return Container(
                    key: ValueKey('sub-$i-$sub'),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: ListTile(
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_indicator,
                            color: Color(0xFF9CA3AF)),
                      ),
                      title: Text(sub,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF111827))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit,
                                size: 18, color: Color(0xFF6B7280)),
                            onPressed: () => _rename(i),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Color(0xFFDC2626)),
                            onPressed: () => _delete(i),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.subdirectory_arrow_right,
                  size: 64, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              const Text('小カテゴリが未登録です',
                  style:
                      TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('小カテゴリを追加'),
                onPressed: _add,
              ),
            ],
          ),
        ),
      );
}
