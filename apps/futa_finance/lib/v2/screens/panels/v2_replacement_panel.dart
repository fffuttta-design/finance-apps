import 'package:flutter/material.dart';

import '../../../data/replacement_repository.dart';
import '../../../data/transaction_repository.dart';

/// 変換マスタ管理パネル。
/// 読み取り（レシートOCR / Amazon取込）で出る読みにくい語を、
/// 「この語 → この語」に置き換える辞書を編集する。既存記録への一括適用も可能。
class V2ReplacementPanel extends StatefulWidget {
  const V2ReplacementPanel({super.key});

  @override
  State<V2ReplacementPanel> createState() => _V2ReplacementPanelState();
}

class _Row {
  final TextEditingController from;
  final TextEditingController to;
  _Row(String f, String t)
      : from = TextEditingController(text: f),
        to = TextEditingController(text: t);
  void dispose() {
    from.dispose();
    to.dispose();
  }
}

class _V2ReplacementPanelState extends State<V2ReplacementPanel> {
  final _rows = <_Row>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final rules = await ReplacementRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(rules.map((r) => _Row(r.from, r.to)));
      _loading = false;
    });
  }

  List<ReplacementRule> _collect() => _rows
      .map((r) => ReplacementRule(r.from.text.trim(), r.to.text.trim()))
      .where((r) => r.from.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    await ReplacementRepository.instance.save(_collect());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('変換マスタを保存しました')),
    );
  }

  /// 現在のモードの既存記録に、保存済みの変換ルールを一括適用する。
  Future<void> _applyToExisting() async {
    // まず最新ルールを保存しておく。
    await ReplacementRepository.instance.save(_collect());
    if (!mounted) return;
    final rules = ReplacementRepository.instance.cached;
    if (rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('適用するルールがありません')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('既存の記録に一括適用'),
        content: const Text(
            '現在のモードの記録の「取引内容」に、変換マスタを適用します。\n'
            'この操作は元に戻せません。実行しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('やめる')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('適用する')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final repo = TransactionRepository.instance;
    final all = await repo.loadAll();
    var changed = 0;
    for (final t in all) {
      final newDesc = ReplacementRepository.instance.apply(t.description);
      if (newDesc != t.description) {
        await repo.update(t.copyWith(description: newDesc));
        changed++;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$changed 件の記録を置き換えました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'レシートやAmazonの読み取りで出る読みにくい語を、登録する言葉に置き換えます。\n'
          '例: 「ｱﾏｿﾞﾝ」→「Amazon」、「ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ」→「セブンイレブン」',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 12),
        // ヘッダー
        const Row(
          children: [
            Expanded(
                child: Text('この語を',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF)))),
            SizedBox(width: 24),
            Expanded(
                child: Text('この言葉に',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF)))),
            SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < _rows.length; i++) _ruleRow(i),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _rows.add(_Row('', ''))),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('行を追加'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? '処理中…' : '保存する'),
        ),
        const Divider(height: 40),
        const Text('既存の記録にも反映',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
        const SizedBox(height: 4),
        const Text(
          'すでに登録済みの記録の「取引内容」にも、変換マスタをまとめて適用します（現在のモード）。',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _applyToExisting,
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('既存の記録に一括適用'),
        ),
      ],
    );
  }

  Widget _ruleRow(int i) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: r.from,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '例: ｱﾏｿﾞﾝ',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 16, color: Color(0xFF9CA3AF)),
          ),
          Expanded(
            child: TextField(
              controller: r.to,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '例: Amazon',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF9CA3AF)),
            onPressed: () => setState(() => _rows.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }
}
