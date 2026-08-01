import 'package:flutter/material.dart';

import '../data/household_service.dart';
import '../theme/app_theme.dart';

/// 変換マスタ：レシート読み取りの表記ゆれ（この語→この語）辞書を編集。
class ReplacementsScreen extends StatefulWidget {
  const ReplacementsScreen({super.key});

  @override
  State<ReplacementsScreen> createState() => _ReplacementsScreenState();
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

class _ReplacementsScreenState extends State<ReplacementsScreen> {
  final _rows = <_Row>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final r in HouseholdService.instance.replacements) {
      _rows.add(_Row(r['from'] ?? '', r['to'] ?? ''));
    }
    if (_rows.isEmpty) _rows.add(_Row('', ''));
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final rules = _rows
        .map((r) => {'from': r.from.text.trim(), 'to': r.to.text.trim()})
        .where((r) => r['from']!.isNotEmpty)
        .toList();
    await HouseholdService.instance.setReplacements(rules);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('変換マスタを保存しました')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('変換マスタ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'レシート読み取りで出る読みにくい語を、登録する言葉に置き換えます。\n'
              '例: 「ｱﾏｿﾞﾝ」→「Amazon」、「ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ」→「セブンイレブン」',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _rows.length; i++) _ruleRow(i),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _rows.add(_Row('', ''))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('行を追加'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
              child: Text(_saving ? '保存中…' : '保存する'),
            ),
          ],
        ),
      ),
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
                  isDense: true, hintText: 'ｱﾏｿﾞﾝ', border: OutlineInputBorder()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child:
                Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.textSub),
          ),
          Expanded(
            child: TextField(
              controller: r.to,
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Amazon', border: OutlineInputBorder()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.textSub),
            onPressed: () => setState(() => _rows.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }
}
