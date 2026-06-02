import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../utils/emoji_palette.dart';
import '../utils/subcategory_icon_suggester.dart';
import '../widgets/centered_body.dart';
import '../widgets/emoji_picker_dialog.dart';
import 'category_sub_editor_screen.dart';

/// 大カテゴリのCRUD + アイコン設定画面。
///
/// 小カテゴリの編集は CategorySubEditorScreen に分離（ExpansionTile式の重さ解消）。
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

  /// アイコン未設定の小カテゴリに、名前から推測した絵文字を一括付与する。
  /// 既存のアイコン設定は絶対に上書きしない（ユーザーの選択を尊重）。
  Future<void> _autoAssignSubIcons() async {
    final config = _config;
    if (config == null) return;
    final (newConfig, applied) =
        SubcategoryIconSuggester.applyToConfig(config);
    if (applied == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('未設定の小カテゴリはありませんでした')),
      );
      return;
    }
    setState(() => _config = newConfig);
    await _repo.saveCategories(newConfig);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$applied 件の小カテゴリにアイコンを自動付与しました')),
    );
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

  Future<bool> _confirm({required String title, required String body}) async {
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
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  void _addMajor() async {
    final name = await _promptText(title: '大カテゴリを追加', label: '名前');
    if (name == null || name.trim().isEmpty) return;
    final list = [..._config!.majors, MajorCategory(name: name.trim(), subs: [])];
    _update(list);
  }

  void _renameMajor(int index) async {
    final current = _config!.majors[index].name;
    final name = await _promptText(
        title: '大カテゴリ名を変更', label: '名前', initial: current);
    if (name == null || name.trim().isEmpty) return;
    final list = [..._config!.majors];
    list[index] = list[index].copyWith(name: name.trim());
    _update(list);
  }

  void _deleteMajor(int index) async {
    final ok = await _confirm(
        title: '${_config!.majors[index].displayName(index)} を削除？',
        body: 'このカテゴリ内の小カテゴリも全て削除されます。');
    if (!ok) return;
    final list = [..._config!.majors]..removeAt(index);
    _update(list);
  }

  Future<void> _pickIcon(int index) async {
    final current = _config!.majors[index].iconKey;
    final newEmoji =
        await showEmojiPickerDialog(context, currentEmoji: current);
    if (newEmoji == null) return;
    final list = [..._config!.majors];
    list[index] = list[index].copyWith(iconKey: newEmoji);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '支出カテゴリ',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: Color(0xFFEA580C)),
            tooltip: 'アイコン未設定の小カテゴリに自動推測アイコンを付与',
            onPressed: config == null ? null : _autoAssignSubIcons,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '大カテゴリを追加',
            onPressed: config == null ? null : _addMajor,
          ),
        ],
      ),
      body: CenteredBody(
        child: config == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(child: _buildSectioned(config)),
      ),
    );
  }

  /// 大カテゴリをセクション（会計科目のまとまり）ごとに見出し付きで表示。
  /// 一律フラットだと数が多くて見づらいので、セクションで束ねる。
  /// 並び順（=表示番号）は変更しない（過去取引の参照とズレないようにするため）。
  Widget _buildSectioned(CategoryConfig config) {
    // セクション → そのセクションに属する (グローバル index, 大カテゴリ) のリスト。
    // index は config.majors 上の位置（displayName / 編集操作で使う）。
    final bySection = <String, List<(int, MajorCategory)>>{};
    for (var i = 0; i < config.majors.length; i++) {
      final m = config.majors[i];
      final key = (m.section == null || m.section!.isEmpty)
          ? 'その他'
          : m.section!;
      bySection.putIfAbsent(key, () => []).add((i, m));
    }
    final sections = config.sectionsInOrder;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in sections) ...[
          _sectionHeader(section, bySection[section]?.length ?? 0),
          for (final (index, major)
              in bySection[section] ?? const <(int, MajorCategory)>[])
            _majorCard(index, major),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _sectionHeader(String section, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            section,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A237E)),
          ),
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _majorCard(int index, MajorCategory major) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategorySubEditorScreen(majorIndex: index),
            ),
          ).then((_) => _load()); // 戻り後に再読込
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // アイコン（タップで変更）
              InkWell(
                onTap: () => _pickIcon(index),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: categoryIconWidget(
                    major.iconKey,
                    color: const Color(0xFF1A237E),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      major.displayName(index),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${major.subs.length}件の小カテゴリ',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit,
                    size: 18, color: Color(0xFF6B7280)),
                onPressed: () => _renameMajor(index),
                tooltip: '名前変更',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFDC2626)),
                onPressed: () => _deleteMajor(index),
                tooltip: '削除',
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
