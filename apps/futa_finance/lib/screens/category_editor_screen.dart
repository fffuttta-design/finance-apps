import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/nav_history.dart';
import '../data/settings_repository.dart';
import '../utils/category_colors.dart';
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

  void _toggleInactive(int index) {
    final list = [..._config!.majors];
    list[index] = list[index].copyWith(inactive: !list[index].inactive);
    _update(list);
  }

  /// カテゴリ色を10色プリセットから選ぶ（「自動」で指定解除）。
  Future<void> _pickColor(int index) async {
    final current = _config!.majors[index].colorValue;
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('カテゴリの色'),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final v in CategoryColors.palette)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, v),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current == v
                            ? const Color(0xFF111827)
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: current == v
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 20)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1), // -1 = 自動（解除）
            child: const Text('自動（指定なし）'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('キャンセル')),
        ],
      ),
    );
    if (result == null) return; // キャンセル
    final list = [..._config!.majors];
    list[index] = result == -1
        ? list[index].copyWith(clearColor: true)
        : list[index].copyWith(colorValue: result);
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
  /// 各セクション内はドラッグで並び替え可能。番号(0.1.2…)は並びに合わせて
  /// 振り直すが、集計はカテゴリ名で行う（v2_report の _bareMajor が番号を無視）
  /// ため、過去取引の金額集計はズレない。
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

    // セクションが実質「その他」だけ（＝個人モード等でPLセクション未設定）の場合は、
    // 「その他」の見出しを出さずフラットに並べる（全部その他に見える違和感を解消）。
    final onlyOther = sections.length == 1 && sections.first == 'その他';
    if (onlyOther) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionReorderable(
              'その他', bySection['その他'] ?? const <(int, MajorCategory)>[]),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in sections) ...[
          _sectionHeader(section, bySection[section]?.length ?? 0),
          _sectionReorderable(
              section, bySection[section] ?? const <(int, MajorCategory)>[]),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// 1セクション分の大カテゴリを、ドラッグで並び替え可能なリストで表示。
  Widget _sectionReorderable(
      String section, List<(int, MajorCategory)> items) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) =>
          _reorderWithinSection(section, oldIndex, newIndex),
      itemBuilder: (context, i) {
        final (globalIndex, major) = items[i];
        return _majorCard(
          globalIndex,
          major,
          dragIndex: i,
          key: ValueKey('major-$globalIndex-${major.name}'),
        );
      },
    );
  }

  /// セクション内の並び替え。section に属する大カテゴリのスロット（config.majors
  /// 上の位置）はそのままに、その中身だけを並べ替える（他セクションは不動）。
  void _reorderWithinSection(String section, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final config = _config!;
    // section に属する major の global index（config.majors 上の位置）順リスト。
    final slots = <int>[];
    for (var i = 0; i < config.majors.length; i++) {
      final m = config.majors[i];
      final key = (m.section == null || m.section!.isEmpty)
          ? 'その他'
          : m.section!;
      if (key == section) slots.add(i);
    }
    if (oldIndex < 0 ||
        oldIndex >= slots.length ||
        newIndex < 0 ||
        newIndex >= slots.length) {
      return;
    }
    // セクション内の major を取り出して並べ替え。
    final ordered = slots.map((gi) => config.majors[gi]).toList();
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    // 元の majors の「セクションのスロット」へ並べ替え後の major を流し込む。
    final newMajors = [...config.majors];
    for (var k = 0; k < slots.length; k++) {
      newMajors[slots[k]] = ordered[k];
    }
    setState(() => _config = config.copyWith(majors: newMajors));
    _save();
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

  Widget _majorCard(int index, MajorCategory major,
      {required int dragIndex, Key? key}) {
    // カテゴリ色。手動指定があれば即その色（_config の生値を読むので色変更が
    // その場で反映される）。無ければ名前/並び順から散りばめた既定色。
    final c = major.colorValue != null
        ? Color(major.colorValue!)
        : CategoryColors.autoColor(major.name);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        // 行の背景もカテゴリ色の薄いトーンにして、ひと目で色が分かるようにする。
        color: Color.alphaBlend(c.withValues(alpha: 0.08), Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.30)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          NavHistory.instance.push(
            context,
            (_) => CategorySubEditorScreen(majorIndex: index),
            onReturn: _load, // 戻り後に再読込
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // ドラッグして並び替え。
              ReorderableDragStartListener(
                index: dragIndex,
                child: const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(Icons.drag_indicator,
                      color: Color(0xFF9CA3AF)),
                ),
              ),
              // アイコン（タップで変更）。カテゴリ色を反映。
              InkWell(
                onTap: () => _pickIcon(index),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: categoryIconWidget(
                    major.iconKey,
                    color: c,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: major.inactive ? 0.45 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // 自動番号(0.1.2…)は付けず、カテゴリ名のみ表示。
                        major.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827)),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (major.inactive) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('休眠',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6B7280))),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${major.subs.length}件の小カテゴリ',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.palette_outlined,
                    size: 18,
                    color: major.colorValue != null
                        ? Color(major.colorValue!)
                        : const Color(0xFF9CA3AF)),
                onPressed: () => _pickColor(index),
                tooltip: '色を選ぶ',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    major.inactive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: major.inactive
                        ? const Color(0xFFEA580C)
                        : const Color(0xFF9CA3AF)),
                onPressed: () => _toggleInactive(index),
                tooltip: major.inactive ? '休眠を解除' : '休眠にする（入力候補から隠す）',
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
