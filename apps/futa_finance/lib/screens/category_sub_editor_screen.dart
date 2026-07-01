import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/emoji_palette.dart';
import '../widgets/centered_body.dart';
import '../widgets/emoji_picker_dialog.dart';
import 'category_reassign_screen.dart';

/// 番号プレフィックス（"7."）を外した素の名前。
String _bareName(String s) =>
    s.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();

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
  List<Transaction> _txns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.loadCategories();
    List<Transaction> txns = const [];
    try {
      txns = await TransactionRepository.instance.loadAll();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _config = c;
      _txns = txns;
    });
  }

  /// この小カテゴリに紐づく明細件数。
  int _subCount(String sub) {
    final majorName = _bareName(_major.name);
    return _txns
        .where((t) =>
            _bareName(t.category.major) == majorName && t.category.sub == sub)
        .length;
  }

  Future<void> _save() async {
    final c = _config;
    if (c != null) await _repo.saveCategories(c);
  }

  MajorCategory get _major => _config!.majors[widget.majorIndex];

  /// MajorCategory 全体を置き換え（subs + subIcons 同時更新用）
  void _updateMajor(MajorCategory newMajor) {
    final majors = [..._config!.majors];
    majors[widget.majorIndex] = newMajor;
    setState(() => _config = _config!.copyWith(majors: majors));
    _save();
  }

  void _updateSubs(List<String> newSubs) {
    _updateMajor(_major.copyWith(subs: newSubs));
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
    final oldName = _major.subs[i];
    final name = await _promptText(
        title: '小カテゴリ名を変更', label: '名前', initial: oldName);
    if (name == null || name.trim().isEmpty) return;
    final newName = name.trim();
    if (newName == oldName) return;

    final subs = [..._major.subs];
    subs[i] = newName;

    // アイコンマップのキーを移行（古い名前→新しい名前）
    Map<String, String>? newIcons;
    if (_major.subIcons != null && _major.subIcons!.containsKey(oldName)) {
      newIcons = {..._major.subIcons!};
      final iconValue = newIcons.remove(oldName);
      if (iconValue != null) newIcons[newName] = iconValue;
    }

    _updateMajor(_major.copyWith(
      subs: subs,
      subIcons: newIcons ?? _major.subIcons,
    ));
  }

  Future<void> _delete(int i) async {
    final subName = _major.subs[i];
    final count = _subCount(subName);
    if (count > 0) {
      // 紐づく明細があるので、先に別カテゴリへ付け替えてから削除。
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryReassignScreen(
            config: _config!,
            sourceMajorDisplay:
                _config!.majors[widget.majorIndex].displayName(widget.majorIndex),
            sourceSub: subName,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      if (done != true) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$subName を削除？'),
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
    }
    if (!mounted) return;

    final subs = [..._major.subs]..removeAt(i);

    // アイコンマップから該当キーを削除
    Map<String, String>? newIcons;
    if (_major.subIcons != null && _major.subIcons!.containsKey(subName)) {
      newIcons = {..._major.subIcons!}..remove(subName);
    }

    _updateMajor(_major.copyWith(
      subs: subs,
      subIcons: newIcons ?? _major.subIcons,
    ));
  }

  /// 小カテゴリのアイコンを選択（絵文字 or 画像URL）。
  Future<void> _editIcon(int i) async {
    final subName = _major.subs[i];
    final current = _major.iconForSub(subName);
    final picked =
        await showEmojiPickerDialog(context, currentEmoji: current);
    // ダイアログでキャンセル時は null。「クリア」の場合も null が返るので
    // 区別するため、ここでは「null = キャンセル」として扱う。
    if (picked == null) return;

    final newIcons = {...(_major.subIcons ?? <String, String>{})};
    if (picked.isEmpty) {
      newIcons.remove(subName);
    } else {
      newIcons[subName] = picked;
    }
    _updateMajor(_major.copyWith(subIcons: newIcons));
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
            categoryIconWidget(_major.iconKey,
                color: const Color(0xFF1A237E), size: 22),
            const SizedBox(width: 8),
            Text(_major.name,
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
        // Web/PC で横に広がりすぎないよう中央寄せ＋最大幅。スマホは全幅のまま。
        child: CenteredBody(
          maxWidth: 680,
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.drag_indicator,
                                  color: Color(0xFF9CA3AF)),
                            ),
                          ),
                          // アイコン（タップで編集）
                          InkWell(
                            onTap: () => _editIcon(i),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: categoryIconWidget(
                                _major.iconForSub(sub),
                                color: const Color(0xFF6B7280),
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(sub,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF111827))),
                                const SizedBox(height: 1),
                                Text('明細${_subCount(sub)}件',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9CA3AF))),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit,
                                size: 18, color: Color(0xFF6B7280)),
                            onPressed: () => _rename(i),
                            tooltip: '名前変更',
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Color(0xFFDC2626)),
                            onPressed: () => _delete(i),
                            tooltip: '削除',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
