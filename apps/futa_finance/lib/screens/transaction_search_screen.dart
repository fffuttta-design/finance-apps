import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/store_master_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../widgets/centered_body.dart';
import 'transaction_detail_screen.dart';

/// 番号プレフィックス（"7."）を外した素の名前。
String _bareName(String s) =>
    s.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();

/// 集計タブの「明細を検索・一括編集」。
/// キーワード/期間/種別/カテゴリ/支払方法/検収 で絞り込み、
/// 選んだ明細に「カテゴリ」「支払方法」をまとめて適用できる。
class TransactionSearchScreen extends StatefulWidget {
  const TransactionSearchScreen({super.key});

  @override
  State<TransactionSearchScreen> createState() =>
      _TransactionSearchScreenState();
}

class _TransactionSearchScreenState extends State<TransactionSearchScreen> {
  final _settings = SettingsRepository();
  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];
  // 支払方法フィルタの特別値：「未登録の支払方法だけ」を表示する。
  static const _unregSentinel = '__unregistered__';

  bool _loading = true;
  bool _busy = false;
  List<core.Transaction> _all = [];
  core.CategoryConfig? _categories;
  core.PaymentMethodsConfig? _payments;

  // 絞り込み条件。
  final _kwCtrl = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  core.TransactionType? _type; // null=すべて
  String? _majorFilter; // null=すべて（素の名前で照合）
  String? _paymentFilter; // null=すべて
  bool? _reviewedFilter; // null=すべて / true=済 / false=未
  bool? _fixedFilter; // null=すべて / true=固定費のみ / false=固定費以外

  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kwCtrl.dispose();
    super.dispose();
  }

  List<String> _storeMaster = const [];

  Future<void> _load() async {
    final c = await _settings.loadCategories();
    final p = await _settings.loadPayments();
    final stores = await StoreMasterRepository.instance.load();
    List<core.Transaction> all = const [];
    try {
      all = await TransactionRepository.instance.loadAll();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _categories = c;
      _payments = p;
      _storeMaster = stores;
      _all = all;
      _loading = false;
    });
  }

  Set<String> get _registeredNames => <String>{
        ...?_payments?.bankAccounts.map((b) => b.name),
        ...?_payments?.creditCards.map((c) => c.name),
      };

  List<String> get _paymentNames {
    final reg = _registeredNames;
    final ordered = <String>[...reg];
    // 取引に出てくる「未登録の支払方法」（例:クレカ）も候補に含める。
    // これで検索→選択→支払方法を一括変更、で正しいカードに付け替えて掃除できる。
    for (final t in _all) {
      final pm = t.paymentMethod.trim();
      if (pm.isNotEmpty && !reg.contains(pm) && !ordered.contains(pm)) {
        ordered.add(pm);
      }
    }
    return ordered;
  }

  List<core.Transaction> get _filtered {
    final kw = _kwCtrl.text.trim().toLowerCase();
    final majorBare = _majorFilter == null ? null : _bareName(_majorFilter!);
    return _all.where((t) {
      if (_type != null && t.type != _type) return false;
      if (_from != null && t.date.isBefore(_from!)) return false;
      if (_to != null &&
          t.date.isAfter(DateTime(_to!.year, _to!.month, _to!.day, 23, 59))) {
        return false;
      }
      if (majorBare != null && _bareName(t.category.major) != majorBare) {
        return false;
      }
      if (_paymentFilter == _unregSentinel) {
        // 未登録のみ：登録済みの支払方法（口座/カード）に無いものだけ残す。
        final pm = t.paymentMethod.trim();
        if (pm.isEmpty || _registeredNames.contains(pm)) return false;
      } else if (_paymentFilter != null &&
          t.paymentMethod != _paymentFilter) {
        return false;
      }
      if (_reviewedFilter != null && t.reviewed != _reviewedFilter) {
        return false;
      }
      if (_fixedFilter != null && t.isFixed != _fixedFilter) {
        return false;
      }
      if (kw.isNotEmpty) {
        final hay = [
          t.description,
          t.store ?? '',
          t.memo ?? '',
          t.category.major,
          t.category.sub,
        ].join(' ').toLowerCase();
        if (!hay.contains(kw)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Color _accent(core.Transaction t) {
    switch (t.type) {
      case core.TransactionType.income:
        return const Color(0xFF059669);
      case core.TransactionType.transfer:
        return const Color(0xFF6B7280);
      case core.TransactionType.expense:
        return const Color(0xFFDC2626);
    }
  }

  String _signed(core.Transaction t) {
    final y = formatYen(t.amount);
    switch (t.type) {
      case core.TransactionType.income:
        return '+$y';
      case core.TransactionType.transfer:
        return y;
      case core.TransactionType.expense:
        return '-$y';
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final base = (isFrom ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = DateTime(picked.year, picked.month, picked.day);
      } else {
        _to = DateTime(picked.year, picked.month, picked.day);
      }
    });
  }

  /// 選択中の明細にまとめて update を適用する。
  Future<void> _applyToSelected(
      core.Transaction Function(core.Transaction) transform,
      String doneMsg) async {
    final targets =
        _filtered.where((t) => _selected.contains(t.id)).toList();
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    var ok = 0;
    for (final t in targets) {
      try {
        await TransactionRepository.instance.update(transform(t));
        ok++;
      } catch (_) {}
    }
    // メモリ側も反映（再読込せずとも一覧を更新）。
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$ok件を$doneMsg')));
  }

  /// 選択中の明細のタイトル（取引内容 description）をまとめて変更する。
  Future<void> _bulkChangeTitle() async {
    final ctrl = TextEditingController();
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('${_selected.length}件のタイトルを変更'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '新しいタイトル（取引内容）',
              hintText: '例）電車代',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(dctx, ctrl.text.trim());
              },
              child: const Text('変更する')),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    await _applyToSelected(
        (t) => t.copyWith(description: newTitle), 'タイトルを「$newTitle」に変更');
  }

  Future<void> _bulkChangeCategory() async {
    final cfg = _categories;
    if (cfg == null) return;
    final majorNames = List.generate(
        cfg.majors.length, (i) => cfg.majors[i].displayName(i));
    String? major = majorNames.isNotEmpty ? majorNames.first : null;
    String? sub;
    List<String> subsOf(String? m) {
      if (m == null) return const [];
      final idx = majorNames.indexOf(m);
      return idx >= 0 ? cfg.majors[idx].subs : const [];
    }

    sub = subsOf(major).isNotEmpty ? subsOf(major).first : null;
    final result = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('${_selected.length}件のカテゴリを変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: major,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: '大カテゴリ', border: OutlineInputBorder()),
                items: [
                  for (final m in majorNames)
                    DropdownMenuItem(value: m, child: Text(_bareName(m))),
                ],
                onChanged: (v) => setLocal(() {
                  major = v;
                  final s = subsOf(v);
                  sub = s.isNotEmpty ? s.first : null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: sub,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: '小カテゴリ', border: OutlineInputBorder()),
                items: [
                  for (final s in subsOf(major))
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setLocal(() => sub = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('この内容で更新')),
          ],
        ),
      ),
    );
    if (result != true || major == null) return;
    final m = major!;
    final s = sub ?? '';
    await _applyToSelected(
      (t) => t.copyWith(category: core.Category(major: m, sub: s)),
      'カテゴリ「${_bareName(m)}${s.isEmpty ? '' : ' › $s'}」に変更しました',
    );
  }

  Future<void> _bulkChangePayment() async {
    final names = _paymentNames;
    if (names.isEmpty) return;
    String? sel = names.first;
    final result = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('${_selected.length}件の支払方法を変更'),
          content: DropdownButtonFormField<String>(
            initialValue: sel,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: '支払方法', border: OutlineInputBorder()),
            items: [
              for (final n in names)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (v) => setLocal(() => sel = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('この内容で更新')),
          ],
        ),
      ),
    );
    if (result != true || sel == null) return;
    final pm = sel!;
    await _applyToSelected(
      (t) => t.copyWith(paymentMethod: pm),
      '支払方法「$pm」に変更しました',
    );
  }

  Future<void> _bulkChangeStore() async {
    // 場所マスタから選ぶ（表記ゆれ防止）＋手入力もできる。
    final ctrl = TextEditingController();
    final options = [..._storeMaster];
    final result = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('${_selected.length}件の場所を変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                    labelText: '場所', border: OutlineInputBorder()),
              ),
              if (options.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('マスタから選ぶ',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in options)
                          ActionChip(
                            label: Text(s),
                            onPressed: () =>
                                setLocal(() => ctrl.text = s),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('この内容で更新')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final store = ctrl.text.trim();
    if (store.isEmpty) return;
    await StoreMasterRepository.instance.add(store);
    await _applyToSelected(
      (t) => t.copyWith(store: store),
      '場所「$store」に変更しました',
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _loading ? <core.Transaction>[] : _filtered;
    final selInResults =
        results.where((t) => _selected.contains(t.id)).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('明細を検索・一括編集')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredBody(
              maxWidth: 760,
              child: Column(
                children: [
                  _filterBar(results.length),
                  const Divider(height: 1),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(
                            child: Text('条件に合う明細がありません',
                                style: TextStyle(color: Color(0xFF9CA3AF))))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            itemCount: results.length,
                            itemBuilder: (_, i) => _row(results[i]),
                          ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: (selInResults > 0)
          ? _actionBar(selInResults)
          : null,
    );
  }

  Widget _filterBar(int count) {
    final majorNames = _categories == null
        ? <String>[]
        : List.generate(_categories!.majors.length,
            (i) => _categories!.majors[i].displayName(i));
    String fmtDate(DateTime? d) =>
        d == null ? '指定なし' : '${d.year}/${d.month}/${d.day}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _kwCtrl,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: '内容・店舗・メモで検索',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 種別
              _dropChip<core.TransactionType?>(
                label: '種別',
                value: _type,
                items: const [
                  (null, 'すべて'),
                  (core.TransactionType.expense, '支出'),
                  (core.TransactionType.income, '収入'),
                  (core.TransactionType.transfer, '振替'),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
              // 大カテゴリ
              _dropChip<String?>(
                label: 'カテゴリ',
                value: _majorFilter,
                items: [
                  (null, 'すべて'),
                  for (final m in majorNames) (m, _bareName(m)),
                ],
                onChanged: (v) => setState(() => _majorFilter = v),
              ),
              // 支払方法
              _dropChip<String?>(
                label: '支払方法',
                value: _paymentFilter,
                items: [
                  (null, 'すべて'),
                  (_unregSentinel, '⚠ 未登録のみ'),
                  for (final n in _paymentNames) (n, n),
                ],
                onChanged: (v) => setState(() => _paymentFilter = v),
              ),
              // 検収
              _dropChip<bool?>(
                label: '検収',
                value: _reviewedFilter,
                items: const [
                  (null, 'すべて'),
                  (true, '済'),
                  (false, '未'),
                ],
                onChanged: (v) => setState(() => _reviewedFilter = v),
              ),
              // 固定費フラグ
              _dropChip<bool?>(
                label: '固定費',
                value: _fixedFilter,
                items: const [
                  (null, 'すべて'),
                  (true, '固定費のみ'),
                  (false, '固定費以外'),
                ],
                onChanged: (v) => setState(() => _fixedFilter = v),
              ),
              // 期間
              OutlinedButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.calendar_today, size: 15),
                label: Text('開始 ${fmtDate(_from)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.calendar_today, size: 15),
                label: Text('終了 ${fmtDate(_to)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              if (_from != null || _to != null || _type != null ||
                  _majorFilter != null || _paymentFilter != null ||
                  _reviewedFilter != null || _fixedFilter != null ||
                  _kwCtrl.text.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _kwCtrl.clear();
                    _from = null;
                    _to = null;
                    _type = null;
                    _majorFilter = null;
                    _paymentFilter = null;
                    _reviewedFilter = null;
                    _fixedFilter = null;
                  }),
                  child: const Text('条件クリア'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$count件',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280))),
              const Spacer(),
              if (count > 0)
                TextButton(
                  onPressed: () => setState(() {
                    final ids = _filtered.map((t) => t.id).toSet();
                    final allSel = ids.every(_selected.contains);
                    if (allSel) {
                      _selected.removeAll(ids);
                    } else {
                      _selected.addAll(ids);
                    }
                  }),
                  child: Text(
                    _filtered.every((t) => _selected.contains(t.id))
                        ? '全解除'
                        : '全選択',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropChip<T>({
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          DropdownButton<T>(
            value: value,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF111827)),
            items: [
              for (final it in items)
                DropdownMenuItem(value: it.$1, child: Text(it.$2)),
            ],
            onChanged: (v) => onChanged(v as T),
          ),
        ],
      ),
    );
  }

  Widget _row(core.Transaction t) {
    final wd = _wd[(t.date.weekday - 1) % 7];
    final selected = _selected.contains(t.id);
    final majorBare = _bareName(t.category.major);
    final cat = t.category.sub.isNotEmpty ? '$majorBare › ${t.category.sub}' : majorBare;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEEF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected
                ? const Color(0xFF6366F1)
                : const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(t.id);
              } else {
                _selected.remove(t.id);
              }
            }),
          ),
          Expanded(
            child: InkWell(
              onTap: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          TransactionDetailScreen(transaction: t)),
                );
                if (changed == true) await _load();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('${t.date.month}/${t.date.day}（$wd）',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.description.trim().isEmpty ? cat : t.description,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                        [
                          cat,
                          if ((t.store ?? '').trim().isNotEmpty)
                            '📍${t.store!.trim()}',
                          t.paymentMethod.isEmpty ? '—' : t.paymentMethod,
                        ].join(' ・ '),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 6),
            child: Text(_signed(t),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _accent(t))),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(int selCount) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$selCount件 選択中',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _bulkChangeTitle,
                  icon: const Icon(Icons.title, size: 16),
                  label: const Text('タイトル変更'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _bulkChangeCategory,
                  icon: const Icon(Icons.sell_outlined, size: 16),
                  label: const Text('カテゴリ変更'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _bulkChangeStore,
                  icon: const Icon(Icons.place_outlined, size: 16),
                  label: const Text('場所変更'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _bulkChangePayment,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.credit_card, size: 16),
                  label: const Text('支払方法変更'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
