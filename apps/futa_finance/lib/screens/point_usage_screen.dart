import 'package:flutter/material.dart';

import '../data/point_usage_repository.dart';
import '../utils/formatters.dart';

/// 「ポイント利用」の一覧。**何にポイントを使ったか**だけを見る画面。
///
/// 🔴 ここに出る金額は **収支・残高・PL に一切入っていない**（本人方針 2026-09-11）。
/// ポイントは資産として持っていない（買い物で勝手に貯まるもの）ので、使っても資産は動かない。
/// 金額は「**その時いくらの価値の物を手に入れたか**」を示すだけの参考値。
///
/// 記録は二村秘書Botが自動で入れる（Amazon注文メールのカード下4桁が
/// 4154=Vポイント / 2121=ファミペイ のとき）。**本人が手で登録することはない。**
class PointUsageScreen extends StatefulWidget {
  const PointUsageScreen({super.key});

  @override
  State<PointUsageScreen> createState() => _PointUsageScreenState();
}

class _PointUsageScreenState extends State<PointUsageScreen> {
  List<PointUsage>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await PointUsageRepository.instance.fetchAll();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// ポイントの種類ごとの合計（相当額）。
  Map<String, int> _totalsByType(List<PointUsage> list) {
    final m = <String, int>{};
    for (final u in list) {
      final k = u.pointType.isEmpty ? 'その他' : u.pointType;
      m[k] = (m[k] ?? 0) + u.amount;
    }
    return m;
  }

  String _monthKey(DateTime d) =>
      '${d.year}年${d.month.toString().padLeft(2, '0')}月';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text('読み込みに失敗しました\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('再読み込み')),
            ],
          ),
        ),
      );
    }
    final items = _items ?? const <PointUsage>[];
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'ポイントで買ったものはまだありません。\n\n'
            'Vポイント・ファミペイで支払うと、二村秘書Botが自動でここに記録します。\n'
            '（手で登録する必要はありません）',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // 月ごとにまとめる（新しい順）。
    final groups = <String, List<PointUsage>>{};
    for (final u in items) {
      groups.putIfAbsent(_monthKey(u.date), () => []).add(u);
    }
    final totals = _totalsByType(items);
    final grand = items.fold<int>(0, (a, u) => a + u.amount);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ポイントで手に入れた価値（累計）',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(formatYen(grand),
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final e in totals.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key)),
                          Text(formatYen(e.value)),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                  Text(
                    '※ この金額は収支・残高・業績には含まれていません。'
                    'ポイントは資産として持っていないため、使っても資産は動きません。'
                    'ここは「何にポイントを使ったか」の記録です。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Row(
                children: [
                  Text(g.key,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(formatYen(
                      g.value.fold<int>(0, (a, u) => a + u.amount))),
                ],
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final u in g.value)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.confirmation_number_outlined),
                      title: Text(u.description.isEmpty
                          ? (u.store ?? '（品目不明）')
                          : u.description),
                      subtitle: Text([
                        '${u.date.month}/${u.date.day}',
                        if ((u.store ?? '').isNotEmpty) u.store!,
                        if (u.pointType.isNotEmpty) u.pointType,
                      ].join('　')),
                      trailing: Text(formatYen(u.amount),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
