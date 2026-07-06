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
  bool _loading = true;
  bool _busy = false;
  List<String> _stores = [];
  List<core.Transaction> _txns = [];

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final sorted = [..._stores]
      ..sort((a, b) => _count(b).compareTo(_count(a)));
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('場所マスタ'),
        actions: [
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
              child: sorted.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                      itemCount: sorted.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) => _row(sorted[i]),
                    ),
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

  Widget _row(String store) {
    final cnt = _count(store);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          const Icon(Icons.place_outlined,
              size: 18, color: Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(store,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('明細 $cnt 件',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
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
