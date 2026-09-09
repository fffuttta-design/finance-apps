import 'package:flutter/material.dart';

import '../data/income_history_repository.dart';
import '../data/income_history_seed.dart';
import '../data/income_year.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../widgets/centered_body.dart';

/// 年収の記録（生涯の年収・税・社会保険）。
///
/// 「いつ・いくら稼いで、いくら税金と社会保険で持っていかれて、いくら残ったか」を
/// 1年＝1行で残す台帳。確定申告書・源泉徴収票・マイナポータル（住民税の課税情報）・
/// ねんきんネット（標準報酬月額）から拾った実額を入れておく。
class IncomeHistoryScreen extends StatefulWidget {
  const IncomeHistoryScreen({super.key});

  @override
  State<IncomeHistoryScreen> createState() => _IncomeHistoryScreenState();
}

class _IncomeHistoryScreenState extends State<IncomeHistoryScreen> {
  static const _bg = Color(0xFFF8FAFC);
  static const _ink = Color(0xFF111827);
  static const _sub = Color(0xFF6B7280);
  static const _line = Color(0xFFE5E7EB);

  static const _cNet = Color(0xFF10B981); // 手取り
  static const _cTax = Color(0xFFEF4444); // 税
  static const _cIns = Color(0xFF3B82F6); // 社会保険

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('年収の記録',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        actions: [
          IconButton(
            tooltip: '年を追加',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(null),
          ),
        ],
      ),
      body: CenteredBody(
        maxWidth: 1180,
        fill: true,
        child: AnimatedBuilder(
          animation: IncomeHistoryRepository.instance,
          builder: (context, _) => FutureBuilder<IncomeHistoryConfig>(
            future: IncomeHistoryRepository.instance.load(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cfg = snap.data!;
              if (cfg.years.isEmpty) return _empty();
              return _body(cfg);
            },
          ),
        ),
      ),
    );
  }

  // ── 空のとき ──────────────────────────────
  Widget _empty() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 28),
        children: [
          const Icon(Icons.timeline, size: 44, color: _sub),
          const SizedBox(height: 12),
          const Text('年収の記録はまだありません',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 8),
          const Text(
            '確定申告書・源泉徴収票・マイナポータル・ねんきんネットから拾った\n'
            '2017年（22歳）〜2026年（31歳）の実績をまとめて入れられます。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _sub, height: 1.6),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _loadSeed,
              icon: const Icon(Icons.download_outlined),
              label: const Text('調査した実績を読み込む（2017〜2026）'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('自分で1年ずつ入力する'),
            ),
          ),
        ],
      );

  Future<void> _loadSeed() async {
    final cfg = await IncomeHistoryRepository.instance.load();
    final existing = {for (final y in cfg.years) y.year: y};
    final merged = [...cfg.years];
    for (final s in buildIncomeHistorySeed()) {
      if (existing.containsKey(s.year)) continue; // 既にある年は触らない
      merged.add(s);
    }
    await IncomeHistoryRepository.instance
        .save(IncomeHistoryConfig(years: merged));
    if (mounted) setState(() {});
  }

  // ── 本体 ────────────────────────────────
  Widget _body(IncomeHistoryConfig cfg) {
    final rows = cfg.sortedDesc;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _summary(cfg),
        const SizedBox(height: 14),
        _chart(cfg),
        const SizedBox(height: 14),
        _table(rows),
        const SizedBox(height: 14),
        _legendNote(),
      ],
    );
  }

  // ── サマリー ──────────────────────────────
  Widget _summary(IncomeHistoryConfig cfg) {
    final gross = cfg.lifetimeGross;
    final rate = gross == 0 ? 0.0 : cfg.lifetimeBurden / gross;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('これまでの合計（${cfg.years.length}年ぶん）',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _sub)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 26,
            runSpacing: 14,
            children: [
              _kpi('稼いだ合計（額面）', cfg.lifetimeGross, _ink),
              _kpi('税金', cfg.lifetimeTax, _cTax),
              _kpi('社会保険', cfg.lifetimeInsurance, _cIns),
              _kpi('残った合計（概算）', cfg.lifetimeNet, _cNet),
              _kpi2('持っていかれた率',
                  '${(rate * 100).toStringAsFixed(1)}%', _sub),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, int value, Color color) =>
      _kpi2(label, formatYen(value), color);

  Widget _kpi2(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: _sub)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      );

  // ── グラフ（積み上げ棒） ──────────────────────
  Widget _chart(IncomeHistoryConfig cfg) {
    final rows = cfg.sortedAsc;
    final maxGross = rows.fold<int>(
        1, (m, y) => y.grossIncome > m ? y.grossIncome : m);
    const barH = 190.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('年収の推移',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _ink)),
              const Spacer(),
              _chip('手取り', _cNet),
              const SizedBox(width: 8),
              _chip('税金', _cTax),
              const SizedBox(width: 8),
              _chip('社会保険', _cIns),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final y in rows) _bar(y, maxGross, barH),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: _sub)),
        ],
      );

  Widget _bar(IncomeYear y, int maxGross, double barH) {
    double h(int v) =>
        maxGross == 0 ? 0 : (v / maxGross) * barH;
    final net = y.netIncome < 0 ? 0 : y.netIncome;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            y.grossIncome == 0
                ? '—'
                : '${(y.grossIncome / 10000).round()}万',
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 44,
            height: barH,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _seg(h(y.insuranceTotal), _cIns, top: true),
                _seg(h(y.taxTotal), _cTax),
                _seg(h(net), _cNet, bottom: true),
                if (y.grossIncome == 0)
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: _line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('${y.year}',
              style: const TextStyle(fontSize: 10, color: _sub)),
          Text(y.age == null ? '' : '${y.age}歳',
              style: const TextStyle(fontSize: 9, color: _sub)),
        ],
      ),
    );
  }

  Widget _seg(double h, Color color,
      {bool top = false, bool bottom = false}) {
    if (h <= 0.5) return const SizedBox.shrink();
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(top ? 4 : 0),
          bottom: Radius.circular(bottom ? 4 : 0),
        ),
      ),
    );
  }

  // ── テーブル ──────────────────────────────
  Widget _table(List<IncomeYear> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 60,
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF3F4F6)),
          columns: const [
            DataColumn(label: _H('年')),
            DataColumn(label: _H('立場')),
            DataColumn(label: _H('額面'), numeric: true),
            DataColumn(label: _H('所得'), numeric: true),
            DataColumn(label: _H('所得税'), numeric: true),
            DataColumn(label: _H('住民税'), numeric: true),
            DataColumn(label: _H('事業税'), numeric: true),
            DataColumn(label: _H('厚生年金'), numeric: true),
            DataColumn(label: _H('国民年金'), numeric: true),
            DataColumn(label: _H('健康保険'), numeric: true),
            DataColumn(label: _H('国保'), numeric: true),
            DataColumn(label: _H('負担計'), numeric: true),
            DataColumn(label: _H('手取り'), numeric: true),
            DataColumn(label: _H('負担率'), numeric: true),
          ],
          rows: [
            for (final y in rows)
              DataRow(
                onSelectChanged: (_) => _edit(y),
                cells: [
                  DataCell(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${y.year}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(y.age == null ? '' : '${y.age}歳',
                          style: const TextStyle(
                              fontSize: 10, color: _sub)),
                    ],
                  )),
                  DataCell(SizedBox(
                    width: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${y.status.emoji} ${y.status.label}',
                            style: const TextStyle(fontSize: 12)),
                        if ((y.employer ?? '').isNotEmpty)
                          Text(y.employer!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: _sub)),
                      ],
                    ),
                  )),
                  _num(y.grossIncome, bold: true),
                  _num(y.totalIncome),
                  _num(y.incomeTax, color: _cTax),
                  _num(y.residentTax, color: _cTax),
                  _num(y.businessTax, color: _cTax),
                  _num(y.pension, color: _cIns),
                  _num(y.nationalPension, color: _cIns),
                  _num(y.healthInsurance, color: _cIns),
                  _num(y.nationalHealthInsurance, color: _cIns),
                  _num(y.burdenTotal, bold: true),
                  _num(y.netIncome, color: _cNet, bold: true),
                  DataCell(Text(
                    y.grossIncome == 0
                        ? '—'
                        : '${(y.burdenRate * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12, color: _sub),
                  )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  DataCell _num(int v, {Color? color, bool bold = false}) => DataCell(Text(
        v == 0 ? '—' : formatYen(v),
        style: TextStyle(
          fontSize: 12,
          color: v == 0 ? _line : (color ?? _ink),
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ));

  Widget _legendNote() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '「額面」は給与＋事業の売上、「手取り」は額面から税金と社会保険を引いた概算です'
                '（事業の経費は引いていません）。住民税は、その年に稼いだ所得に対して'
                '翌年度に課された金額を、稼いだ年の行に入れています。'
                '行をタップすると中身を直せます。',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF1E3A8A), height: 1.6),
              ),
            ),
          ],
        ),
      );

  // ── 編集ダイアログ ────────────────────────
  Future<void> _edit(IncomeYear? src) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _IncomeYearDialog(src: src),
    );
    if (result == null) return;
    if (result.delete) {
      await IncomeHistoryRepository.instance.remove(src!.id);
    } else {
      await IncomeHistoryRepository.instance.upsert(result.item!);
    }
    if (mounted) setState(() {});
  }
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151)));
}

class _EditResult {
  const _EditResult({this.item, this.delete = false});
  final IncomeYear? item;
  final bool delete;
}

/// 1年ぶんの入力ダイアログ。
class _IncomeYearDialog extends StatefulWidget {
  const _IncomeYearDialog({this.src});
  final IncomeYear? src;

  @override
  State<_IncomeYearDialog> createState() => _IncomeYearDialogState();
}

class _IncomeYearDialogState extends State<_IncomeYearDialog> {
  late final Map<String, TextEditingController> _c;
  late WorkStatus _status;

  static const _moneyFields = <String, String>{
    'salary': '給与収入（役員報酬も）',
    'business': '事業収入（売上）',
    'otherIncome': 'その他の収入',
    'totalIncome': '合計所得金額',
    'incomeTax': '所得税（復興税込み）',
    'residentTax': '住民税',
    'businessTax': '個人事業税',
    'pension': '厚生年金（本人負担）',
    'nationalPension': '国民年金',
    'healthInsurance': '健康保険',
    'nationalHealthInsurance': '国民健康保険',
    'employmentInsurance': '雇用保険',
    'otherInsurance': 'その他の保険料',
  };

  @override
  void initState() {
    super.initState();
    final s = widget.src;
    _status = s?.status ?? WorkStatus.employee;
    String yen(int v) => v == 0 ? '' : v.toString();
    _c = {
      'year': TextEditingController(
          text: (s?.year ?? DateTime.now().year).toString()),
      'age': TextEditingController(text: s?.age?.toString() ?? ''),
      'employer': TextEditingController(text: s?.employer ?? ''),
      'note': TextEditingController(text: s?.note ?? ''),
      'source': TextEditingController(text: s?.source ?? ''),
      'salary': TextEditingController(text: yen(s?.salary ?? 0)),
      'business': TextEditingController(text: yen(s?.business ?? 0)),
      'otherIncome': TextEditingController(text: yen(s?.otherIncome ?? 0)),
      'totalIncome': TextEditingController(text: yen(s?.totalIncome ?? 0)),
      'incomeTax': TextEditingController(text: yen(s?.incomeTax ?? 0)),
      'residentTax': TextEditingController(text: yen(s?.residentTax ?? 0)),
      'businessTax': TextEditingController(text: yen(s?.businessTax ?? 0)),
      'pension': TextEditingController(text: yen(s?.pension ?? 0)),
      'nationalPension':
          TextEditingController(text: yen(s?.nationalPension ?? 0)),
      'healthInsurance':
          TextEditingController(text: yen(s?.healthInsurance ?? 0)),
      'nationalHealthInsurance':
          TextEditingController(text: yen(s?.nationalHealthInsurance ?? 0)),
      'employmentInsurance':
          TextEditingController(text: yen(s?.employmentInsurance ?? 0)),
      'otherInsurance':
          TextEditingController(text: yen(s?.otherInsurance ?? 0)),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(String key) {
    final raw = _c[key]!.text.replaceAll(',', '').trim();
    return int.tryParse(raw) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.src == null;
    return AlertDialog(
      title: Text(isNew ? '年を追加' : '${widget.src!.year}年の記録'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _c['year'],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '年（西暦）', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _c['age'],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '年齢', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<WorkStatus>(
                initialValue: _status,
                isDense: true,
                decoration: const InputDecoration(labelText: '立場'),
                items: [
                  for (final s in WorkStatus.values)
                    DropdownMenuItem(
                        value: s, child: Text('${s.emoji} ${s.label}')),
                ],
                onChanged: (v) =>
                    setState(() => _status = v ?? WorkStatus.other),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _c['employer'],
                decoration: const InputDecoration(
                    labelText: '勤務先・屋号', isDense: true),
              ),
              const SizedBox(height: 16),
              for (final e in _moneyFields.entries) ...[
                TextField(
                  controller: _c[e.key],
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: InputDecoration(
                      labelText: e.value,
                      isDense: true,
                      prefixText: '¥ '),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 6),
              TextField(
                controller: _c['source'],
                decoration: const InputDecoration(
                    labelText: '出典（源泉徴収票・確定申告書 など）',
                    isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _c['note'],
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'メモ', isDense: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!isNew)
          TextButton(
            onPressed: () => Navigator.pop(
                context, const _EditResult(delete: true)),
            child: const Text('削除',
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            final year = int.tryParse(_c['year']!.text.trim());
            if (year == null) return;
            final item = IncomeYear(
              id: widget.src?.id ??
                  'iy-${DateTime.now().millisecondsSinceEpoch}',
              year: year,
              age: int.tryParse(_c['age']!.text.trim()),
              status: _status,
              employer: _c['employer']!.text.trim().isEmpty
                  ? null
                  : _c['employer']!.text.trim(),
              salary: _int('salary'),
              business: _int('business'),
              otherIncome: _int('otherIncome'),
              totalIncome: _int('totalIncome'),
              incomeTax: _int('incomeTax'),
              residentTax: _int('residentTax'),
              businessTax: _int('businessTax'),
              healthInsurance: _int('healthInsurance'),
              pension: _int('pension'),
              nationalPension: _int('nationalPension'),
              nationalHealthInsurance: _int('nationalHealthInsurance'),
              employmentInsurance: _int('employmentInsurance'),
              otherInsurance: _int('otherInsurance'),
              note: _c['note']!.text.trim().isEmpty
                  ? null
                  : _c['note']!.text.trim(),
              source: _c['source']!.text.trim().isEmpty
                  ? null
                  : _c['source']!.text.trim(),
            );
            Navigator.pop(context, _EditResult(item: item));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
