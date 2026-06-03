import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/backup_repository.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../widgets/centered_body.dart';

/// 過去取引の「大分類（会計科目）」を一括で付け替えるツール。
///
/// 旧カテゴリ名（例: "0.固定費(定額)" "研修費"）を、現在の会計科目（大カテゴリ）へ
/// まとめて置き換える。経費取引が対象。実行前に自動スナップショットを取得する。
class CategoryRemapScreen extends StatefulWidget {
  const CategoryRemapScreen({super.key});

  @override
  State<CategoryRemapScreen> createState() => _CategoryRemapScreenState();
}

class _Group {
  final String major; // 取引に入っている生の major 文字列
  final int count;
  final int total;
  _Group(this.major, this.count, this.total);
}

class _CategoryRemapScreenState extends State<CategoryRemapScreen> {
  List<core.Transaction>? _txns;
  core.CategoryConfig? _config;

  /// 旧 major → 付替先の「大カテゴリ名（番号なし）」。null は「変更しない」。
  final Map<String, String?> _mapping = {};

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 先頭の「N.」を除いた素の名前。
  String _bare(String major) =>
      major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();

  Future<void> _load() async {
    final txns = await TransactionRepository.instance.loadAll();
    final config = await SettingsRepository().loadCategories();
    if (!mounted) return;
    // 経費取引の major 別に集計。
    final byMajor = <String, _Group>{};
    for (final t in txns) {
      if (t.type != core.TransactionType.expense) continue;
      final m = t.category.major.trim();
      if (m.isEmpty) continue;
      final g = byMajor[m];
      if (g == null) {
        byMajor[m] = _Group(m, 1, t.amount);
      } else {
        byMajor[m] = _Group(m, g.count + 1, g.total + t.amount);
      }
    }
    // 既定の付替先: 素の名前が現行科目に一致すればプリセット。
    final majorNames = config.majors.map((e) => e.name).toSet();
    for (final m in byMajor.keys) {
      final bare = _bare(m);
      _mapping[m] = majorNames.contains(bare) ? bare : null;
    }
    setState(() {
      _txns = txns;
      _config = config;
      _groups = byMajor.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));
    });
  }

  List<_Group> _groups = [];

  int get _changeCount {
    final txns = _txns;
    if (txns == null) return 0;
    int n = 0;
    for (final t in txns) {
      if (t.type != core.TransactionType.expense) continue;
      final target = _mapping[t.category.major.trim()];
      if (target == null) continue;
      // 既に同じ大カテゴリなら変更不要。
      if (_bare(t.category.major) == target) continue;
      n++;
    }
    return n;
  }

  Future<void> _apply() async {
    final txns = _txns;
    final config = _config;
    if (txns == null || config == null) return;

    final indexOf = <String, int>{};
    for (var i = 0; i < config.majors.length; i++) {
      indexOf[config.majors[i].name] = i;
    }

    final changed = _changeCount;
    if (changed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('付け替え対象がありません')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('一括付替の確認'),
        content: Text(
          '$changed 件の経費取引の会計科目を付け替えます。\n'
          '実行前に自動バックアップ（スナップショット）を取得します。\n\n'
          'よろしいですか？',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('実行')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      // 安全のため自動スナップショット（Android のみ・失敗は無視）。
      try {
        await BackupRepository.instance
            .savePreImportSnapshot(reason: 'pre-remap');
      } catch (_) {}

      final newList = <core.Transaction>[];
      for (final t in txns) {
        final target = (t.type == core.TransactionType.expense)
            ? _mapping[t.category.major.trim()]
            : null;
        if (target == null || _bare(t.category.major) == target) {
          newList.add(t);
          continue;
        }
        final idx = indexOf[target];
        final newMajor = idx == null ? target : '$idx.$target';
        newList.add(t.copyWith(
          category: core.Category(major: newMajor, sub: t.category.sub),
        ));
      }
      await TransactionRepository.instance.replaceAll(newList);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$changed 件の科目を付け替えました')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('付替に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('取引の科目を一括付替',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      body: CenteredBody(
        child: config == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '旧カテゴリ名（例: 固定費(定額)・研修費）を、現在の会計科目へまとめて置き換えます。'
                            '経費取引が対象。「変更しない」の項目はそのままです。実行前に自動バックアップを取得します。',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF92400E)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final g in _groups) _groupRow(g, config),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _apply,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.swap_horiz, size: 18),
                          label: Text(_busy
                              ? '処理中...'
                              : 'この内容で付け替える（$_changeCount 件）'),
                          style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _groupRow(_Group g, core.CategoryConfig config) {
    final target = _mapping[g.major];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(g.major,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Text('${g.count}件 / ${formatYen(g.total)}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: target,
                  hint: const Text('変更しない'),
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— 変更しない —')),
                    ...config.majors.map((m) => DropdownMenuItem<String?>(
                          value: m.name,
                          child: Text(
                              '${m.section != null && m.section!.isNotEmpty ? '［${m.section}］' : ''}${m.name}',
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setState(() => _mapping[g.major] = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
