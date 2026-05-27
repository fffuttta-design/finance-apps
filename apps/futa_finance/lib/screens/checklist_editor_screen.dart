import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/checklist_repository.dart';

/// 月末締めチェックリストのCRUD画面。
/// - メイン項目（親）を並べ替え可能
/// - 各メイン項目にサブ項目（子）を追加可能（2階層）
class ChecklistEditorScreen extends StatefulWidget {
  const ChecklistEditorScreen({super.key});

  @override
  State<ChecklistEditorScreen> createState() => _ChecklistEditorScreenState();
}

class _ChecklistEditorScreenState extends State<ChecklistEditorScreen> {
  final _repo = ChecklistRepository.instance;
  ChecklistConfig? _config;

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

  void _update(List<ChecklistItem> newItems) {
    setState(() => _config = _config!.copyWith(items: newItems));
    _save();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// 親/子共用の編集ダイアログ。
  Future<ChecklistItem?> _editDialog(
      BuildContext context, ChecklistItem? initial,
      {required bool isChild}) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final urlCtrl = TextEditingController(text: initial?.url ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');

    return showModalBottomSheet<ChecklistItem?>(
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
            final url =
                urlCtrl.text.trim().isEmpty ? null : urlCtrl.text.trim();
            final memo =
                memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
            if (initial == null) {
              Navigator.pop(
                  ctx,
                  ChecklistItem(
                      id: _genId(), name: name, url: url, memo: memo));
            } else {
              Navigator.pop(ctx,
                  initial.copyWith(name: name, url: url, memo: memo));
            }
          }

          final title = initial == null
              ? (isChild ? 'サブ項目を追加' : 'チェック項目を追加')
              : (isChild ? 'サブ項目を編集' : 'チェック項目を編集');

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: FractionallySizedBox(
              heightFactor: 0.7,
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
                            title,
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
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: nameCtrl,
                            autofocus: initial == null,
                            decoration: InputDecoration(
                              labelText: '項目名（必須）',
                              hintText: isChild
                                  ? '例: 通帳記入'
                                  : '例: 銀行口座の入出金を確認',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            onChanged: (_) => setLocal(() {}),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: urlCtrl,
                            decoration: const InputDecoration(
                              labelText: '確認用URL（任意）',
                              hintText: 'https://www.smbc-card.com/',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: memoCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'メモ（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
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
                    padding:
                        const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
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

  Future<void> _addParent() async {
    final r = await _editDialog(context, null, isChild: false);
    if (r == null) return;
    _update([..._config!.items, r]);
  }

  Future<void> _editParent(int i) async {
    final r = await _editDialog(context, _config!.items[i], isChild: false);
    if (r == null) return;
    final list = [..._config!.items];
    list[i] = r;
    _update(list);
  }

  Future<void> _deleteParent(int i) async {
    final item = _config!.items[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${item.name} を削除？'),
        content: item.hasChildren
            ? Text('サブ項目 ${item.children.length} 件も一緒に削除されます')
            : null,
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
    final list = [..._config!.items]..removeAt(i);
    _update(list);
  }

  Future<void> _addChild(int parentIndex) async {
    final r = await _editDialog(context, null, isChild: true);
    if (r == null) return;
    final parent = _config!.items[parentIndex];
    final newParent =
        parent.copyWith(children: [...parent.children, r]);
    final list = [..._config!.items];
    list[parentIndex] = newParent;
    _update(list);
  }

  Future<void> _editChild(int parentIndex, int childIndex) async {
    final parent = _config!.items[parentIndex];
    final r =
        await _editDialog(context, parent.children[childIndex], isChild: true);
    if (r == null) return;
    final newChildren = [...parent.children];
    newChildren[childIndex] = r;
    final newParent = parent.copyWith(children: newChildren);
    final list = [..._config!.items];
    list[parentIndex] = newParent;
    _update(list);
  }

  Future<void> _deleteChild(int parentIndex, int childIndex) async {
    final parent = _config!.items[parentIndex];
    final child = parent.children[childIndex];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${child.name} を削除？'),
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
    final newChildren = [...parent.children]..removeAt(childIndex);
    final newParent = parent.copyWith(children: newChildren);
    final list = [..._config!.items];
    list[parentIndex] = newParent;
    _update(list);
  }

  void _reorder(int oldIndex, int newIndex) {
    final list = [..._config!.items];
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '月末締めチェックリスト',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: 'チェック項目を追加',
            onPressed: config == null ? null : _addParent,
          ),
        ],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: config.items.isEmpty
                  ? _empty()
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: config.items.length,
                      onReorder: _reorder,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, i) {
                        final item = config.items[i];
                        return _parentCard(item, i);
                      },
                    ),
            ),
    );
  }

  Widget _parentCard(ChecklistItem item, int i) {
    return Container(
      key: ValueKey('item-${item.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // 親行
          ListTile(
            leading: ReorderableDragStartListener(
              index: i,
              child: const Icon(Icons.drag_indicator,
                  color: Color(0xFF9CA3AF)),
            ),
            title: Text(item.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
            subtitle: item.url == null && item.memo == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.url != null)
                        Text(item.url!,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF3B82F6)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      if (item.memo != null)
                        Text(item.memo!,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF9CA3AF)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit,
                      size: 18, color: Color(0xFF6B7280)),
                  onPressed: () => _editParent(i),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Color(0xFFDC2626)),
                  onPressed: () => _deleteParent(i),
                ),
              ],
            ),
          ),
          // 動的リンク項目（銀行/クレカと自動紐付け）はサブ項目編集不可
          if (item.isLinked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.link,
                      size: 14, color: Color(0xFF1A237E)),
                  const SizedBox(width: 4),
                  Text(
                    item.linkType == 'bank_accounts'
                        ? '登録ウォレットから自動展開'
                        : item.linkType == 'credit_cards'
                            ? '登録クレジットカードから自動展開'
                            : '自動展開',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1A237E),
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            )
          else ...[
            // サブ項目セクション
            if (item.children.isNotEmpty)
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
            ...item.children.asMap().entries.map((e) =>
                _childRow(parentIndex: i, childIndex: e.key, child: e.value)),
            // サブ項目追加ボタン
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addChild(i),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('サブ項目を追加',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 0),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _childRow({
    required int parentIndex,
    required int childIndex,
    required ChecklistItem child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 4, 8, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF9FAFB))),
      ),
      child: Row(
        children: [
          // インデントだけで階層を表現（矢印アイコンは廃止）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(child.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827))),
                if (child.url != null)
                  Text(child.url!,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF3B82F6)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                if (child.memo != null)
                  Text(child.memo!,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF9CA3AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit,
                size: 16, color: Color(0xFF6B7280)),
            onPressed: () => _editChild(parentIndex, childIndex),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 16, color: Color(0xFFDC2626)),
            onPressed: () => _deleteChild(parentIndex, childIndex),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.checklist_outlined,
                  size: 64, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              const Text('チェック項目が未登録です',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 4),
              const Text('銀行/カード/PayPay/源泉徴収などを登録',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('チェック項目を追加'),
                onPressed: _addParent,
              ),
            ],
          ),
        ),
      );
}
