import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../widgets/centered_body.dart';

/// カテゴリ削除の前に、そのカテゴリに紐づく明細を別カテゴリへ付け替える画面。
///
/// - [sourceMajorDisplay]（番号付きの表示名）に一致する取引が対象。
/// - [sourceSub] が null なら「大カテゴリまるごと」、指定ありなら「その小カテゴリだけ」。
/// - 一括変更（全件を選んだカテゴリへ）と、1件ずつの付け替えの両方に対応。
/// - 対象が 0 件になったら「削除できます」＝ pop(true) で呼び出し元が削除する。
class CategoryReassignScreen extends StatefulWidget {
  final CategoryConfig config;
  final String sourceMajorDisplay;
  final String? sourceSub;

  const CategoryReassignScreen({
    super.key,
    required this.config,
    required this.sourceMajorDisplay,
    this.sourceSub,
  });

  @override
  State<CategoryReassignScreen> createState() =>
      _CategoryReassignScreenState();
}

String _bare(String s) =>
    s.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();

class _CategoryReassignScreenState extends State<CategoryReassignScreen> {
  List<Transaction> _all = [];
  bool _loading = true;

  // 一括変更でよく使う宛先（ダイアログの初期選択に使う）。
  int? _targetMajorIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  bool _isSource(Transaction t) {
    if (_bare(t.category.major) != _bare(widget.sourceMajorDisplay)) {
      return false;
    }
    if (widget.sourceSub != null && t.category.sub != widget.sourceSub) {
      return false;
    }
    return true;
  }

  List<Transaction> get _linked =>
      _all.where(_isSource).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// 付け替え先の候補（自分自身のカテゴリは除く）。
  List<int> get _targetMajors {
    final res = <int>[];
    for (var i = 0; i < widget.config.majors.length; i++) {
      // 大カテゴリ削除時は自分自身を除外。小カテゴリ削除時は同じ大カテゴリもOK。
      if (widget.sourceSub == null &&
          _bare(widget.config.majors[i].displayName(i)) ==
              _bare(widget.sourceMajorDisplay)) {
        continue;
      }
      res.add(i);
    }
    return res;
  }

  Future<void> _reassign(List<Transaction> txns, int majorIdx, String sub) async {
    final majorDisplay = widget.config.majors[majorIdx].displayName(majorIdx);
    for (final t in txns) {
      await TransactionRepository.instance
          .update(t.copyWith(category: Category(major: majorDisplay, sub: sub)));
    }
    await _load();
  }

  /// 付け替え先（大→小）を選ぶダイアログ。戻り値 = (majorIndex, sub)。
  Future<(int, String)?> _pickTarget() async {
    int? mIdx = _targetMajorIndex ??
        (_targetMajors.isNotEmpty ? _targetMajors.first : null);
    String? sub;
    return showDialog<(int, String)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final subs =
            mIdx == null ? <String>[] : widget.config.majors[mIdx!].subs;
        sub ??= subs.isNotEmpty ? subs.first : null;
        return AlertDialog(
          title: const Text('付け替え先を選ぶ'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: mIdx,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '大カテゴリ'),
                  items: [
                    for (final i in _targetMajors)
                      DropdownMenuItem(
                          value: i,
                          child: Text(widget.config.majors[i].name,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setLocal(() {
                    mIdx = v;
                    sub = (v != null && widget.config.majors[v].subs.isNotEmpty)
                        ? widget.config.majors[v].subs.first
                        : null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sub,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '小カテゴリ'),
                  items: [
                    for (final s in subs)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setLocal(() => sub = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: (mIdx != null && sub != null)
                  ? () => Navigator.pop(ctx, (mIdx!, sub!))
                  : null,
              child: const Text('決定'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _bulkReassign() async {
    final picked = await _pickTarget();
    if (picked == null) return;
    setState(() => _targetMajorIndex = picked.$1);
    await _reassign(_linked, picked.$1, picked.$2);
  }

  Future<void> _reassignOne(Transaction t) async {
    final picked = await _pickTarget();
    if (picked == null) return;
    await _reassign([t], picked.$1, picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final linked = _linked;
    final label = widget.sourceSub == null
        ? _bare(widget.sourceMajorDisplay)
        : '${_bare(widget.sourceMajorDisplay)} › ${widget.sourceSub}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('削除前に付け替え',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: CenteredBody(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFEF3C7),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('「$label」に紐づく明細：${linked.length}件',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E))),
                        const SizedBox(height: 4),
                        const Text(
                            'すべて別カテゴリに移してから削除できます（0件になると削除ボタンが押せます）。',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF92400E))),
                      ],
                    ),
                  ),
                  if (linked.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _bulkReassign,
                          icon: const Icon(Icons.move_down, size: 18),
                          label: Text('この${linked.length}件をまとめて別カテゴリへ'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: linked.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: 40, color: Color(0xFF16A34A)),
                                const SizedBox(height: 8),
                                const Text('付け替え完了。削除できます。',
                                    style: TextStyle(
                                        color: Color(0xFF6B7280))),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFFDC2626)),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  icon: const Icon(Icons.delete, size: 18),
                                  label: const Text('このカテゴリを削除する'),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: linked.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final t = linked[i];
                              return ListTile(
                                title: Text(
                                    t.description.trim().isEmpty
                                        ? '(内容なし)'
                                        : t.description.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${t.date.month}/${t.date.day}  ${t.category.sub}  -${formatYen(t.amount)}',
                                    style: const TextStyle(fontSize: 12)),
                                trailing: OutlinedButton(
                                  onPressed: () => _reassignOne(t),
                                  child: const Text('変更'),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
