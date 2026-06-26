import 'package:finance_core/finance_core.dart' as core;
import 'package:flutter/material.dart';

import '../data/app_mode.dart';
import '../data/backup_repository.dart';
import '../data/card_import_draft.dart';
import '../data/settings_repository.dart';
import '../data/store_category_classifier.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';

/// 初期化／CSV置き換えで「このカードの取引」とみなして削除対象にするか判定。
///
/// - 支払方法がそのカード名と一致 → 対象
/// - 支払方法が汎用クレジット表記（昔の手入力分。「クレカ」等）→ 対象
///   ※ 別の登録カード名（例「三井住友カード」）は完全一致しないので巻き込まない。
bool isCreditDeleteTarget(String paymentMethod, String cardName) {
  final pm = paymentMethod.trim();
  if (pm == cardName.trim()) return true;
  const generic = {
    'クレカ',
    'クレジットカード',
    'クレジット',
    'クレジット決済',
    'カード',
  };
  return generic.contains(pm);
}

/// クレカCSVの1行（取り込み元データ）。
class CardCsvLine {
  final DateTime? date;
  final String name;
  final int amount;
  const CardCsvLine(this.date, this.name, this.amount);
}

/// クレカCSVを「正」として取り込むプレビュー＆編集画面。
///
/// - 各行で **店名（取引内容）を編集** できる（Amazon.co.jp 等の丸めを直す）。
/// - **カテゴリを取り込み前にAIが提案**（変更可）。
/// - **下書き保存／復元／削除**（件数が多いので途中保存して後で続けられる）。
/// - 「取り込む」で CSV期間内のそのカードの既存取引を削除 → 編集後の内容で一括記帳。
///   実行前に自動バックアップ。
class CardCsvImportScreen extends StatefulWidget {
  final core.RegisteredCreditCard card;
  final String ym; // "YYYY-MM"
  final List<CardCsvLine> lines;

  const CardCsvImportScreen({
    super.key,
    required this.card,
    required this.ym,
    required this.lines,
  });

  @override
  State<CardCsvImportScreen> createState() => _CardCsvImportScreenState();
}

class _Row {
  DateTime? date;
  final TextEditingController nameCtrl;
  int amount;
  String? major;
  String sub;
  bool excluded;

  _Row({
    required this.date,
    required String name,
    required this.amount,
    this.major,
    this.sub = '',
    this.excluded = false,
  }) : nameCtrl = TextEditingController(text: name);

  void dispose() => nameCtrl.dispose();
}

class _CardCsvImportScreenState extends State<CardCsvImportScreen> {
  final _txRepo = TransactionRepository.instance;

  List<_Row> _rows = [];
  Map<String, List<String>> _catMenu = {}; // 大→小（AI/ドロップダウン用）
  List<String> _majors = [];

  bool _loading = true; // 初期ロード
  bool _proposing = false; // AI推定中
  bool _importing = false;

  int get _year => int.parse(widget.ym.split('-')[0]);
  int get _month => int.parse(widget.ym.split('-')[1]);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    // カテゴリ一覧（現モード・休眠除く）。
    try {
      final cfg = await SettingsRepository().loadCategories();
      final menu = <String, List<String>>{};
      final majors = <String>[];
      for (final m in cfg.majors) {
        if (m.inactive) continue;
        menu[m.name] = m.subs;
        majors.add(m.name);
      }
      _catMenu = menu;
      _majors = majors;
    } catch (_) {}

    _rows = [
      for (final l in widget.lines)
        _Row(date: l.date, name: l.name, amount: l.amount),
    ];
    if (!mounted) return;
    setState(() => _loading = false);

    // 下書きがあれば復元するか確認。なければAIで科目提案。
    final hasDraft =
        await CardImportDraftRepository.instance.exists(widget.card.name, widget.ym);
    if (!mounted) return;
    if (hasDraft) {
      final restore = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('下書きが見つかりました'),
          content: const Text('前回の編集途中の下書きがあります。復元しますか？\n'
              '（復元しない場合は今回のCSVから新しく始めます）'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('使わない')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('下書きを復元')),
          ],
        ),
      );
      if (restore == true) {
        await _restoreDraft();
        return;
      }
    }
    await _propose();
  }

  /// 店名からカテゴリをAIで一括提案。
  Future<void> _propose() async {
    if (_rows.isEmpty || _catMenu.isEmpty) return;
    setState(() => _proposing = true);
    final names = _rows.map((r) => r.nameCtrl.text).toList();
    List<Map<String, String>?> cats;
    try {
      cats = await StoreCategoryClassifier.instance.classify(names, _catMenu);
    } catch (_) {
      cats = List<Map<String, String>?>.filled(names.length, null);
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _rows.length && i < cats.length; i++) {
        final c = cats[i];
        if (c != null) {
          _rows[i].major = c['major'];
          _rows[i].sub = c['sub'] ?? '';
        }
      }
      _proposing = false;
    });
  }

  Future<void> _saveDraft() async {
    final draft = CardImportDraft(
      card: widget.card.name,
      ym: widget.ym,
      rows: [
        for (final r in _rows)
          CardImportDraftRow(
            dateIso: r.date?.toIso8601String().split('T').first,
            name: r.nameCtrl.text,
            amount: r.amount,
            major: r.major ?? '',
            sub: r.sub,
            excluded: r.excluded,
          ),
      ],
      savedAtIso: '', // 端末側で stamp しない（Date.now 不使用方針に倣い空）
    );
    await CardImportDraftRepository.instance.save(draft);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下書きを保存しました')));
  }

  Future<void> _restoreDraft() async {
    final d = await CardImportDraftRepository.instance
        .load(widget.card.name, widget.ym);
    if (d == null) return;
    for (final r in _rows) {
      r.dispose();
    }
    if (!mounted) return;
    setState(() {
      _rows = [
        for (final row in d.rows)
          _Row(
            date: row.dateIso == null ? null : DateTime.tryParse(row.dateIso!),
            name: row.name,
            amount: row.amount,
            major: row.major.isEmpty ? null : row.major,
            sub: row.sub,
            excluded: row.excluded,
          ),
      ];
    });
  }

  Future<void> _deleteDraft() async {
    await CardImportDraftRepository.instance
        .delete(widget.card.name, widget.ym);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下書きを削除しました')));
  }

  int get _validCount => _rows
      .where((r) => !r.excluded && r.amount > 0 && r.nameCtrl.text.trim().isNotEmpty)
      .length;
  int get _total => _rows
      .where((r) => !r.excluded && r.amount > 0)
      .fold(0, (s, r) => s + r.amount);

  Future<void> _import() async {
    final valid = _rows
        .where((r) =>
            !r.excluded && r.amount > 0 && r.nameCtrl.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) return;

    // CSV（採用行）の日付範囲を出す（±2日で既存取引を拾う）。
    DateTime? minD, maxD;
    for (final r in valid) {
      final d = r.date;
      if (d == null) continue;
      if (minD == null || d.isBefore(minD)) minD = d;
      if (maxD == null || d.isAfter(maxD)) maxD = d;
    }
    final lo = minD?.subtract(const Duration(days: 2));
    final hi = maxD?.add(const Duration(days: 2));

    final all = await _txRepo.loadAll();
    final existing = all.where((t) {
      if (t.type != core.TransactionType.expense) return false;
      // このカード名＋汎用クレカ表記（昔の手入力）も置換対象にする。
      if (!isCreditDeleteTarget(t.paymentMethod, widget.card.name)) return false;
      if (lo != null && t.date.isBefore(lo)) return false;
      if (hi != null && t.date.isAfter(hi)) return false;
      return true;
    }).toList();

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('この内容で取り込みますか？'),
        content: Text(
            '「${widget.card.name}」のCSV期間内の既存取引 ${existing.length}件を削除し、'
            '編集後の ${valid.length}件を新規に取り込みます。\n\n'
            'この操作は元に戻せません。実行直前に自動バックアップを取ります。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
            child: const Text('取り込む'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _importing = true);
    try {
      try {
        await BackupRepository.instance
            .savePreImportSnapshot(reason: 'pre-card-csv-import');
      } catch (_) {}

      var deleted = 0;
      for (final t in existing) {
        try {
          await _txRepo.delete(t.id);
          deleted++;
        } catch (_) {}
      }

      final minDate = AppModeManager.instance.current.minDate;
      final ymFirst = DateTime(_year, _month);
      final baseId = DateTime.now().microsecondsSinceEpoch;
      var added = 0, skipped = 0;
      for (var i = 0; i < valid.length; i++) {
        final r = valid[i];
        final date = r.date ?? ymFirst;
        if (date.isBefore(minDate)) {
          skipped++;
          continue;
        }
        final name = r.nameCtrl.text.trim();
        final tx = core.Transaction(
          id: '$baseId-$i',
          date: date,
          type: core.TransactionType.expense,
          category: core.Category(major: r.major ?? '未分類', sub: r.sub),
          paymentMethod: widget.card.name,
          description: name,
          amount: r.amount,
          store: name,
        );
        try {
          await _txRepo.add(tx);
          added++;
        } catch (_) {}
      }

      // 取り込んだら下書きは不要。
      await CardImportDraftRepository.instance
          .delete(widget.card.name, widget.ym);

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('取り込み完了：$deleted件を削除・$added件を取り込みました'
              '${skipped > 0 ? '（カットオフ前の$skipped件はスキップ）' : ''}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('取り込みに失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CSV取り込み（$_month月・${widget.card.name}）',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          IconButton(
            tooltip: 'AIで科目を再提案',
            onPressed: _proposing ? null : _propose,
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF1A237E)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    children: [
                      // サマリー＋下書き操作
                      Container(
                        color: const Color(0xFFF8FAFC),
                        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _proposing
                                    ? 'AIが科目を推定中…'
                                    : '取り込み $_validCount件 / 合計 ${formatYen(_total)}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A237E)),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _saveDraft,
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: const Text('下書き保存',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              tooltip: '下書きを削除',
                              visualDensity: VisualDensity.compact,
                              onPressed: _deleteDraft,
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                      ),
                      if (_proposing) const LinearProgressIndicator(minHeight: 2),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) => _rowCard(_rows[i]),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: (_validCount == 0 ||
                                      _importing ||
                                      _proposing)
                                  ? null
                                  : _import,
                              icon: _importing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.download_done, size: 18),
                              label: Text(_importing
                                  ? '取り込み中…'
                                  : '$_validCount件を取り込む（置き換え）'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEA580C),
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
              ),
            ),
    );
  }

  Widget _rowCard(_Row r) {
    return Opacity(
      opacity: r.excluded ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  r.date == null
                      ? '日付なし'
                      : '${r.date!.month}/${r.date!.day}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF6B7280)),
                ),
                const Spacer(),
                Text('-${formatYen(r.amount)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: Color(0xFFDC2626))),
                Tooltip(
                  message: r.excluded ? '取り込みに含める' : '取り込みから除外',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(r.excluded
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline),
                    onPressed: () => setState(() => r.excluded = !r.excluded),
                  ),
                ),
              ],
            ),
            // 店名（編集可）
            TextField(
              controller: r.nameCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '取引内容（店名）',
                labelStyle: TextStyle(fontSize: 12),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              ),
            ),
            const SizedBox(height: 8),
            // カテゴリ（AI提案・変更可）
            DropdownButtonFormField<String>(
              initialValue: _majors.contains(r.major) ? r.major : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '会計科目（AI提案）',
                labelStyle: TextStyle(fontSize: 12),
                prefixIcon: Icon(Icons.auto_awesome, size: 16),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              ),
              hint: const Text('未分類', style: TextStyle(fontSize: 13)),
              style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
              items: [
                for (final m in _majors)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() {
                r.major = v;
                r.sub = ''; // 大カテゴリを変えたら小はクリア
              }),
            ),
          ],
        ),
      ),
    );
  }
}
