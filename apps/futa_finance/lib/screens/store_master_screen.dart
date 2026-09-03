import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/store_master_repository.dart';
import '../data/transaction_repository.dart';
import '../widgets/centered_body.dart';

/// 場所マスタの管理画面。
/// - 追加 / 名前変更 / 削除
/// - 統合（表記ゆれをまとめる）：A を B にまとめると、過去の明細の場所も一括で B に書き換える
/// - 履歴から取り込み：過去の明細に出てくる場所をまとめてマスタに登録
///
/// 事業/個人で共通（モード非依存）。
class StoreMasterScreen extends StatefulWidget {
  const StoreMasterScreen({super.key});

  @override
  State<StoreMasterScreen> createState() => _StoreMasterScreenState();
}

class _StoreMasterScreenState extends State<StoreMasterScreen> {
  final _repo = StoreMasterRepository.instance;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  List<String> _stores = [];
  List<core.Transaction> _txns = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stores = await _repo.load();
    List<core.Transaction> txns = const [];
    try {
      txns = await TransactionRepository.instance.loadAll();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _stores = [...stores];
      _txns = txns;
      _loading = false;
    });
  }

  int _count(String store) =>
      _txns.where((t) => (t.store ?? '').trim() == store).length;

  /// 全モードの取引で store==from を to に一括書き換え。
  Future<int> _rewriteStore(String from, String to) async {
    var n = 0;
    for (final t in _txns) {
      if ((t.store ?? '').trim() == from) {
        await TransactionRepository.instance.update(t.copyWith(store: to));
        n++;
      }
    }
    return n;
  }

  Future<void> _addStore() async {
    final name = await _promptText('場所を追加', '');
    if (name == null || name.trim().isEmpty) return;
    await _repo.add(name.trim());
    await _load();
  }

  Future<void> _importFromHistory() async {
    final used = _txns
        .map((t) => (t.store ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final add = used.where((s) => !_stores.contains(s)).toList();
    if (add.isEmpty) {
      _snack('新しく取り込む場所はありませんでした');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('履歴から取り込み'),
        content: Text('過去の明細に出てくる ${add.length} 件の場所をマスタに追加します。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('取り込む')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await _repo.addAll(add);
    await _load();
    if (mounted) setState(() => _busy = false);
    _snack('${add.length} 件を取り込みました');
  }

  Future<void> _rename(String store) async {
    final name = await _promptText('名前を変更', store);
    final to = name?.trim() ?? '';
    if (to.isEmpty || to == store) return;
    setState(() => _busy = true);
    // 明細も一括で書き換え（過去分もそろえる）。
    final n = await _rewriteStore(store, to);
    final next =
        _stores.map((s) => s == store ? to : s).toList();
    await _repo.save(next);
    await _load();
    if (mounted) setState(() => _busy = false);
    _snack('「$store」→「$to」に変更（明細 $n 件も更新）');
  }

  Future<void> _merge(String from) async {
    final others = _stores.where((s) => s != from).toList();
    if (others.isEmpty) {
      _snack('統合先がありません（他の場所を追加してください）');
      return;
    }
    String? target = others.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('「$from」を統合'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('この場所を、選んだ場所にまとめます。',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              const Text('過去の明細の場所も、まとめて書き換わります。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: target,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'まとめ先', border: OutlineInputBorder()),
                items: [
                  for (final s in others)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setLocal(() => target = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('統合する')),
          ],
        ),
      ),
    );
    if (ok != true || target == null) return;
    final to = target!;
    setState(() => _busy = true);
    final n = await _rewriteStore(from, to);
    // from をマスタから消し、to は残す。
    final next = _stores.where((s) => s != from).toList();
    if (!next.contains(to)) next.add(to);
    await _repo.save(next);
    await _load();
    if (mounted) setState(() => _busy = false);
    _snack('「$from」を「$to」に統合（明細 $n 件も更新）');
  }

  Future<void> _delete(String store) async {
    final cnt = _count(store);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('「$store」を削除'),
        content: Text(cnt > 0
            ? 'マスタから削除します（この場所を使っている明細 $cnt 件はそのまま残ります）。'
            : 'マスタから削除します。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.save(_stores.where((s) => s != store).toList());
    await _load();
  }

  Future<String?> _promptText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '例: ファミリーマート', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // 「未分類」グループの内部キー（実在のセクション名と衝突しない番兵）。
  static const _unassignedKey = ' __unassigned__';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('場所マスタ'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _addSection,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('セクション追加'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _importFromHistory,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('履歴から取込'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addStore,
        icon: const Icon(Icons.add),
        label: const Text('場所を追加'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredBody(
              maxWidth: 640,
              child: Column(
                children: [
                  if (_stores.isNotEmpty) _searchBar(),
                  Expanded(
                    child: _stores.isEmpty
                        ? _empty()
                        : (_query.trim().isEmpty
                            ? _sectionedList()
                            : _filteredList()),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: '場所を検索（例: ファミマ）',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'クリア',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
      ),
    );
  }

  /// 検索中はセクションを無視して、名前が一致する場所を平らに並べる。
  /// （並び替えは検索中は意味を成さないのでドラッグハンドルは出さない。）
  Widget _filteredList() {
    final q = _query.trim().toLowerCase();
    final hits = _stores.where((s) => s.toLowerCase().contains(q)).toList();
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off,
                  size: 36, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 10),
              Text('「${_query.trim()}」に一致する場所はありません',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280))),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('${hits.length} 件',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ),
        for (final store in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _row(store, null),
          ),
      ],
    );
  }

  /// セクションごとに場所をまとめて表示。各セクション内はドラッグで並び替え。
  Widget _sectionedList() {
    final sectionNames = _repo.sections;
    final groups = <String, List<String>>{
      for (final s in sectionNames) s: <String>[],
      _unassignedKey: <String>[],
    };
    for (final store in _stores) {
      final sec = _repo.sectionOf(store);
      if (sec != null && groups.containsKey(sec)) {
        groups[sec]!.add(store);
      } else {
        groups[_unassignedKey]!.add(store);
      }
    }
    final order = [...sectionNames, _unassignedKey];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final key in order)
          if (key != _unassignedKey || groups[key]!.isNotEmpty)
            _sectionCard(key, groups[key]!),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text(
              'ハンドル（⋮⋮）をドラッグで並び替え。フォルダ🗂ボタンでセクションを変更できます。',
              style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ),
      ],
    );
  }

  Widget _sectionCard(String key, List<String> stores) {
    final isUnassigned = key == _unassignedKey;
    final title = isUnassigned ? '未分類' : key;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(isUnassigned ? Icons.inbox_outlined : Icons.folder_outlined,
                  size: 18, color: const Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Text('$title（${stores.length}）',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (!isUnassigned) ...[
                IconButton(
                  tooltip: 'セクション名を変更',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: Color(0xFF6B7280)),
                  onPressed: _busy ? null : () => _renameSection(key),
                ),
                IconButton(
                  tooltip: 'セクションを削除（中の場所は未分類に戻る）',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Color(0xFFDC2626)),
                  onPressed: _busy ? null : () => _deleteSection(key),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          if (stores.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text('（このセクションの場所はありません）',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: stores.length,
              onReorder: (o, n) => _reorderWithin(key, stores, o, n),
              itemBuilder: (_, i) => Padding(
                key: ValueKey('$key|${stores[i]}'),
                padding: const EdgeInsets.only(bottom: 6),
                child: _row(stores[i], i),
              ),
            ),
        ],
      ),
    );
  }

  /// セクション内の並びを、_stores 全体の該当位置に書き戻して保存する。
  void _reorderWithin(
      String key, List<String> sectionStores, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = [...sectionStores];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    // _stores の中で、このセクションに属する要素の位置を集める。
    bool belongs(String s) {
      final sec = _repo.sectionOf(s);
      return key == _unassignedKey
          ? (sec == null || !_repo.sections.contains(sec))
          : sec == key;
    }

    final positions = <int>[];
    for (int i = 0; i < _stores.length; i++) {
      if (belongs(_stores[i])) positions.add(i);
    }
    final next = [..._stores];
    for (int j = 0; j < positions.length && j < reordered.length; j++) {
      next[positions[j]] = reordered[j];
    }
    setState(() => _stores = next);
    _repo.save(next);
  }

  Future<void> _addSection() async {
    final name = await _promptText('セクションを追加', '');
    if (name == null || name.trim().isEmpty) return;
    await _repo.saveSections([..._repo.sections, name.trim()]);
    await _load();
    _snack('セクション「${name.trim()}」を追加しました');
  }

  Future<void> _renameSection(String old) async {
    final name = await _promptText('セクション名を変更', old);
    if (name == null || name.trim().isEmpty || name.trim() == old) return;
    await _repo.renameSection(old, name.trim());
    await _load();
  }

  Future<void> _deleteSection(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('「$name」を削除'),
        content: const Text('セクションを削除します（中の場所は「未分類」に戻ります。場所自体は消えません）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('削除する')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.saveSections(_repo.sections.where((s) => s != name).toList());
    await _load();
  }

  /// 場所を別のセクションへ移す（未分類も選べる）。
  Future<void> _moveToSection(String store) async {
    final current = _repo.sectionOf(store);
    final choice = await showModalBottomSheet<String>(
      // 広い画面ではシートが横いっぱいに伸びるので、幅を抑えて中央に置く。
      constraints: const BoxConstraints(maxWidth: 560),
      context: context,
      builder: (sctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('セクションを選ぶ',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未分類'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(sctx, _unassignedKey),
            ),
            for (final s in _repo.sections)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(s),
                trailing: current == s ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sctx, s),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新しいセクションを作る…'),
              onTap: () => Navigator.pop(sctx, ''),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice.isEmpty) {
      final name = await _promptText('セクションを追加', '');
      if (name == null || name.trim().isEmpty) return;
      await _repo.assignSection(store, name.trim());
    } else {
      await _repo.assignSection(
          store, choice == _unassignedKey ? null : choice);
    }
    await _load();
  }

  static String _yen(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}¥${b.toString()}';
  }

  static String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  /// この場所に紐づく明細の一覧をボトムシートで表示する（新しい順）。
  Future<void> _showTransactions(String store) async {
    final list = _txns.where((t) => (t.store ?? '').trim() == store).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) {
      _snack('「$store」を使っている明細はまだありません');
      return;
    }
    final total = list.fold<int>(0, (a, t) {
      final signed =
          t.type == core.TransactionType.income ? t.amount : -t.amount;
      return a + signed;
    });
    await showModalBottomSheet<void>(
      // 広い画面ではシートが横いっぱいに伸びるので、幅を抑えて中央に置く。
      constraints: const BoxConstraints(maxWidth: 560),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sctx) {
        final h = MediaQuery.of(sctx).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: h,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 20, color: Color(0xFF6B7280)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(store,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text('明細 ${list.length} 件 ・ 合計 ${_yen(total)}',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF6B7280))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) => _txnTile(list[i]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _txnTile(core.Transaction t) {
    final isIncome = t.type == core.TransactionType.income;
    final signed = isIncome ? t.amount : -t.amount;
    final title = t.description.trim().isNotEmpty
        ? t.description.trim()
        : (t.category.sub.trim().isNotEmpty ? t.category.sub : '(内容なし)');
    final sub = <String>[
      _ymd(t.date),
      if (t.category.sub.trim().isNotEmpty) t.category.sub,
      if (t.paymentMethod.trim().isNotEmpty) t.paymentMethod,
    ].join(' ・ ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_yen(signed),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isIncome
                      ? const Color(0xFF059669)
                      : const Color(0xFF111827))),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place_outlined,
                  size: 40, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              const Text('場所マスタは空です',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              const Text(
                  '「履歴から取込」で今までの場所をまとめて登録するか、\n「場所を追加」で1件ずつ登録できます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
        ),
      );

  Widget _row(String store, int? index) {
    final cnt = _count(store);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 6, 8),
      child: Row(
        children: [
          // ドラッグハンドル（このセクション内で並び替え）。検索中(index==null)は出さない。
          if (index != null)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_indicator,
                    size: 18, color: Color(0xFF9CA3AF)),
              ),
            )
          else
            const SizedBox(width: 12),
          const Icon(Icons.place_outlined,
              size: 18, color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          // 名前部分をタップすると、この場所の明細一覧を出す。
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showTransactions(store),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(store,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Text('明細 $cnt 件',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF))),
                        if (cnt > 0) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              size: 13, color: Color(0xFF9CA3AF)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'セクションを変更',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.folder_outlined,
                size: 18, color: Color(0xFF6B7280)),
            onPressed: _busy ? null : () => _moveToSection(store),
          ),
          IconButton(
            tooltip: '名前を変更',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: Color(0xFF6B7280)),
            onPressed: _busy ? null : () => _rename(store),
          ),
          IconButton(
            tooltip: 'ほかの場所に統合',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.merge_type,
                size: 18, color: Color(0xFF2563EB)),
            onPressed: _busy ? null : () => _merge(store),
          ),
          IconButton(
            tooltip: '削除',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFFDC2626)),
            onPressed: _busy ? null : () => _delete(store),
          ),
        ],
      ),
    );
  }
}
