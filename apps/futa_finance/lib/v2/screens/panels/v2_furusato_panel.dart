import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart';

import '../../../data/app_mode.dart';
import '../../../data/furusato.dart';
import '../../../data/furusato_repository.dart';
import '../../../data/transaction_repository.dart';
import '../../../utils/formatters.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/v2_card.dart';

/// ふるさと納税管理パネル。
///
/// 設計の肝は「寄付そのもののデータを持たないこと」。
/// 金額・日付は既存の支出記録（Transaction）が正本で、このパネルは
/// 設定したカテゴリに一致する支出を拾って集計するだけ。追加で持つのは
/// 自治体名・証明書の状態・ワンストップ申請の有無の3つだけにしてある。
/// （別テーブルを作ると記帳と数字がズレる日が必ず来るため）
class V2FurusatoPanel extends StatefulWidget {
  const V2FurusatoPanel({super.key});

  @override
  State<V2FurusatoPanel> createState() => _V2FurusatoPanelState();
}

class _V2FurusatoPanelState extends State<V2FurusatoPanel>
    with ModeAwareMixin {
  // リポジトリは static instance をその都度参照する。
  // ログイン/ログアウトで Local⇄Firestore に差し替わるため、
  // フィールドに掴むと古い実装を持ち続けてしまう。
  FurusatoConfig? _config;
  List<Transaction> _all = const [];
  late int _year = DateTime.now().year;
  bool _loading = true;

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cfg = await FurusatoRepository.instance.load();
    final txs = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _all = txs;
      _loading = false;
    });
  }

  Future<void> _saveConfig(FurusatoConfig next) async {
    setState(() => _config = next);
    await FurusatoRepository.instance.save(next);
  }

  /// 設定したカテゴリに一致する、その年の寄付（支出）を新しい順に。
  List<Transaction> get _donations {
    final cfg = _config;
    if (cfg == null) return const [];
    final list = _all
        .where((t) =>
            t.type == TransactionType.expense &&
            t.date.year == _year &&
            t.category.major == cfg.categoryMajor &&
            t.category.sub == cfg.categorySub)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  int get _used => _donations.fold(0, (s, t) => s + t.amount);

  /// 寄付先の自治体数（ワンストップの5自治体判定に使う）。
  /// 自治体名が未入力の行は数えられないので、その件数も返す。
  ({int known, int unknown}) get _municipalityCount {
    final cfg = _config;
    if (cfg == null) return (known: 0, unknown: 0);
    final names = <String>{};
    var unknown = 0;
    for (final t in _donations) {
      final m = cfg.entryOf(t.id).municipality.trim();
      if (m.isEmpty) {
        unknown++;
      } else {
        names.add(m);
      }
    }
    return (known: names.length, unknown: unknown);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    if (_loading || cfg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final y = cfg.yearOf(_year);
    final donations = _donations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: V2Spacing.lg),
        _yearNav(),
        const SizedBox(height: V2Spacing.lg),
        _quotaCard(y),
        const SizedBox(height: V2Spacing.lg),
        ..._alerts(y, donations),
        _limitCalculator(cfg, y),
        const SizedBox(height: V2Spacing.lg),
        _donationList(cfg, donations),
        const SizedBox(height: V2Spacing.lg),
        _categoryNote(cfg),
      ],
    );
  }

  // ── ヘッダー ───────────────────────────────
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(
            V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: V2Colors.warningSoft,
                borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.volunteer_activism_outlined,
                  size: 20, color: V2Colors.warning),
            ),
            const SizedBox(width: V2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ふるさと納税管理', style: V2Typography.h1),
                  const SizedBox(height: V2Spacing.xs),
                  Text(
                    '枠の残りと、控除に必要な証明書の回収状況を管理します。'
                    '寄付の金額・日付は支出の記録がそのまま元になります。',
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── 年の切替 ───────────────────────────────
  Widget _yearNav() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _year--),
            tooltip: '前の年',
          ),
          Text('$_year年', style: V2Typography.h2),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _year++),
            tooltip: '次の年',
          ),
        ],
      );

  // ── 枠メーター ─────────────────────────────
  Widget _quotaCard(FurusatoYearConfig y) {
    final used = _used;
    final limit = y.limitAmount;
    final remain = limit - used;
    final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final over = limit > 0 && used > limit;
    final muni = _municipalityCount;

    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('控除上限額', style: V2Typography.caption),
              const Spacer(),
              InkWell(
                onTap: () => _editLimit(y),
                child: Row(
                  children: [
                    Text(
                      limit > 0 ? formatYen(limit) : '未設定',
                      style: V2Typography.h2.copyWith(
                        color: limit > 0
                            ? V2Colors.textPrimary
                            : V2Colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: V2Spacing.xs),
                    const Icon(Icons.edit_outlined,
                        size: 14, color: V2Colors.textMuted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: V2Colors.divider,
              valueColor: AlwaysStoppedAnimation(
                over
                    ? V2Colors.negative
                    : ratio > 0.85
                        ? V2Colors.warning
                        : V2Colors.positive,
              ),
            ),
          ),
          const SizedBox(height: V2Spacing.md),
          Row(
            children: [
              _kpi('使用済', formatYen(used), V2Colors.textPrimary),
              const SizedBox(width: V2Spacing.xl),
              _kpi(
                over ? '超過' : '残り',
                formatYen(remain.abs()),
                over ? V2Colors.negative : V2Colors.positive,
              ),
              const SizedBox(width: V2Spacing.xl),
              _kpi('件数', '${_donations.length}件', V2Colors.textBody),
            ],
          ),
          if (y.useOnestop) ...[
            const Divider(height: V2Spacing.xl),
            Row(
              children: [
                Icon(
                  muni.known >= FurusatoConfig.onestopMunicipalityLimit
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 16,
                  color: muni.known >= FurusatoConfig.onestopMunicipalityLimit
                      ? V2Colors.negative
                      : V2Colors.positive,
                ),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Text(
                    'ワンストップ対象の自治体　'
                    '${muni.known} / ${FurusatoConfig.onestopMunicipalityLimit}'
                    '${muni.unknown > 0 ? '（自治体名が未入力の寄付が${muni.unknown}件）' : ''}',
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: V2Typography.micro),
          const SizedBox(height: 2),
          Text(value, style: V2Typography.bodyStrong.copyWith(color: color)),
        ],
      );

  // ── アラート ───────────────────────────────
  /// 時期と状態に応じて出す注意。年中出しっぱなしにはしない。
  List<Widget> _alerts(FurusatoYearConfig y, List<Transaction> donations) {
    final cfg = _config!;
    final now = DateTime.now();
    final items = <({IconData icon, Color color, String text})>[];

    final used = _used;
    final limit = y.limitAmount;

    // 年間合計が損益分岐点を下回っている（＝自己負担2,000円のほうが大きい）。
    if (used > 0 && used < FurusatoLimit.breakEvenDonation) {
      items.add((
        icon: Icons.info_outline,
        color: V2Colors.info,
        text: '年間の寄付が${formatYen(used)}です。'
            '返礼品は寄付額の3割までなので、'
            '年間合計が${formatYen(FurusatoLimit.breakEvenDonation)}を超えないと'
            '自己負担2,000円のほうが大きくなります。',
      ));
    }

    // 枠オーバー。
    if (limit > 0 && used > limit) {
      items.add((
        icon: Icons.error_outline,
        color: V2Colors.negative,
        text: '上限を${formatYen(used - limit)}超えています。'
            '超過分は控除されず自己負担になります。',
      ));
    }

    // 年末：枠が余っている。
    if (now.year == _year && now.month == 12 && limit > 0 && used < limit) {
      final left = DateTime(_year, 12, 31).difference(now).inDays + 1;
      items.add((
        icon: Icons.schedule,
        color: V2Colors.warning,
        text: '今年はあと$left日。枠が${formatYen(limit - used)}余っています。'
            'クレジットカードは12/31の決済完了分までが今年扱いです。',
      ));
    }

    // 年明け：ワンストップの申請期限。
    if (y.useOnestop) {
      final deadline = FurusatoConfig.onestopDeadlineFor(_year);
      final notApplied = donations
          .where((t) => !cfg.entryOf(t.id).onestopApplied)
          .length;
      final days = deadline.difference(now).inDays;
      if (notApplied > 0 && days >= 0 && days <= 40) {
        items.add((
          icon: Icons.assignment_late_outlined,
          color: V2Colors.negative,
          text: 'ワンストップ特例の申請期限（${deadline.month}/${deadline.day}必着）まで'
              'あと$days日。未申請が$notApplied件あります。',
        ));
      }
    }

    // 確定申告期：証明書が未着。
    final missing =
        donations.where((t) => !cfg.entryOf(t.id).certificate.isReady).length;
    if (missing > 0 && now.year == _year + 1 && now.month <= 3) {
      items.add((
        icon: Icons.description_outlined,
        color: V2Colors.negative,
        text: '受領証明書が未着の寄付が$missing件あります。'
            'そろわないとその分の控除が受けられません。',
      ));
    }

    if (items.isEmpty) return const [];
    return [
      for (final it in items) ...[
        V2Card(
          background: it.color.withValues(alpha: 0.06),
          borderColor: it.color.withValues(alpha: 0.35),
          padding: const EdgeInsets.all(V2Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(it.icon, size: 18, color: it.color),
              const SizedBox(width: V2Spacing.sm),
              Expanded(
                child: Text(it.text,
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textBody)),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.md),
      ],
    ];
  }

  // ── 限度額の計算機 ─────────────────────────
  Widget _limitCalculator(FurusatoConfig cfg, FurusatoYearConfig y) {
    final res = FurusatoLimit.estimate(
      salaryIncome: y.salaryIncome,
      socialInsurance: y.socialInsurance,
      otherDeduction: y.otherDeduction,
    );
    return V2Card(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding:
            const EdgeInsets.symmetric(horizontal: V2Spacing.lg),
        childrenPadding: const EdgeInsets.fromLTRB(
            V2Spacing.lg, 0, V2Spacing.lg, V2Spacing.lg),
        leading: const Icon(Icons.calculate_outlined,
            size: 20, color: V2Colors.badgePurple),
        title: Text('控除上限額の計算', style: V2Typography.bodyStrong),
        subtitle: Text(
          res.limit > 0
              ? '概算 ${formatYen(res.limit)}'
              : '給与収入と社会保険料を入れると概算できます',
          style: V2Typography.caption.copyWith(color: V2Colors.textSecondary),
        ),
        children: [
          _numField('給与収入（年額）', y.salaryIncome,
              hint: '役員報酬の年額。月60万なら7200000',
              onChanged: (v) =>
                  _saveConfig(cfg.upsertYear(y.copyWith(salaryIncome: v)))),
          _numField('社会保険料（年額）', y.socialInsurance,
              hint: '健康保険＋厚生年金の本人負担分の年額',
              onChanged: (v) => _saveConfig(
                  cfg.upsertYear(y.copyWith(socialInsurance: v)))),
          _numField('その他の所得控除（年額）', y.otherDeduction,
              hint: '生命保険料控除・配偶者控除など。無ければ0',
              onChanged: (v) => _saveConfig(
                  cfg.upsertYear(y.copyWith(otherDeduction: v)))),
          const SizedBox(height: V2Spacing.md),
          if (res.limit > 0) ...[
            _calcRow('住民税所得割額', formatYen(res.residentTaxBase)),
            _calcRow('所得税率',
                '${(res.incomeTaxRate * 100).toStringAsFixed(0)}%'),
            _calcRow('控除上限額（概算）', formatYen(res.limit), strong: true),
            const SizedBox(height: V2Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('この額を上限に設定'),
                onPressed: () => _saveConfig(
                    cfg.upsertYear(y.copyWith(limitAmount: res.limit))),
              ),
            ),
            Text(
              'あくまで概算です。大きな金額を寄付する前には、'
              'ポータルの詳細シミュレーターとも突き合わせてください。'
              '上限を超えた分は控除されず、返礼品を定価で買ったのと同じになります。',
              style: V2Typography.micro
                  .copyWith(color: V2Colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label,
                style: V2Typography.caption
                    .copyWith(color: V2Colors.textSecondary)),
            const Spacer(),
            Text(value,
                style: strong
                    ? V2Typography.bodyStrong
                    : V2Typography.caption),
          ],
        ),
      );

  Widget _numField(String label, int value,
          {required ValueChanged<int> onChanged, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: V2Spacing.sm),
        child: TextFormField(
          initialValue: value == 0 ? '' : '$value',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (s) => onChanged(int.tryParse(s) ?? 0),
        ),
      );

  // ── 寄付一覧 ───────────────────────────────
  Widget _donationList(FurusatoConfig cfg, List<Transaction> donations) {
    if (donations.isEmpty) {
      return V2Card(
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined,
                size: 32, color: V2Colors.textMuted),
            const SizedBox(height: V2Spacing.sm),
            Text('$_year年の寄付はまだありません',
                style: V2Typography.body
                    .copyWith(color: V2Colors.textSecondary)),
            const SizedBox(height: V2Spacing.xs),
            Text(
              '支出を「${cfg.categoryMajor} ＞ ${cfg.categorySub}」で記録すると'
              'ここに出ます。',
              textAlign: TextAlign.center,
              style: V2Typography.micro
                  .copyWith(color: V2Colors.textMuted),
            ),
          ],
        ),
      );
    }

    return V2Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(V2Spacing.lg, V2Spacing.lg,
                V2Spacing.lg, V2Spacing.sm),
            child: Row(
              children: [
                Text('寄付の一覧', style: V2Typography.bodyStrong),
                const SizedBox(width: V2Spacing.sm),
                Text('行をタップで編集',
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textMuted)),
              ],
            ),
          ),
          for (final t in donations) _donationRow(cfg, t),
        ],
      ),
    );
  }

  Widget _donationRow(FurusatoConfig cfg, Transaction t) {
    final e = cfg.entryOf(t.id);
    final ok = e.certificate.isReady;
    return InkWell(
      onTap: () => _editEntry(cfg, t, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: V2Spacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text('${t.date.month}/${t.date.day}',
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.municipality.isEmpty ? '（自治体 未入力）' : e.municipality,
                    style: V2Typography.body.copyWith(
                      color: e.municipality.isEmpty
                          ? V2Colors.textMuted
                          : V2Colors.textPrimary,
                    ),
                  ),
                  Text(
                    [
                      if (t.description.isNotEmpty) t.description,
                      if (e.portal.isNotEmpty) e.portal,
                    ].join(' ・ '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            _badge(
              e.certificate.label,
              ok ? V2Colors.positive : V2Colors.negative,
              ok ? V2Colors.positiveSoft : V2Colors.negativeSoft,
            ),
            const SizedBox(width: V2Spacing.xs),
            if (cfg.yearOf(_year).useOnestop)
              _badge(
                e.onestopApplied ? 'ワンストップ済' : 'ワンストップ未',
                e.onestopApplied ? V2Colors.info : V2Colors.textMuted,
                e.onestopApplied ? V2Colors.infoSoft : V2Colors.hover,
              ),
            const SizedBox(width: V2Spacing.md),
            Text(formatYen(t.amount), style: V2Typography.numericCell),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
        ),
        child: Text(text,
            style: V2Typography.micro
                .copyWith(color: fg, fontWeight: FontWeight.w600)),
      );

  Widget _categoryNote(FurusatoConfig cfg) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: V2Spacing.sm),
        child: Text(
          '集計対象カテゴリ：${cfg.categoryMajor} ＞ ${cfg.categorySub}\n'
          'ふるさと納税は消費ではなく税金の前払いなので、'
          '「非消費」に設定した専用カテゴリで記録すると家計の集計が汚れません。'
          '法人の口座・カードで払うと役員貸付になるので、個人のカードで払ってください。',
          style: V2Typography.micro.copyWith(color: V2Colors.textMuted),
        ),
      );

  // ── 編集 ───────────────────────────────────
  Future<void> _editLimit(FurusatoYearConfig y) async {
    final cfg = _config!;
    final ctrl = TextEditingController(
        text: y.limitAmount == 0 ? '' : '${y.limitAmount}');
    var useOnestop = y.useOnestop;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('$_year年の設定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '控除上限額（円）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: V2Spacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: useOnestop,
                onChanged: (v) => setLocal(() => useOnestop = v),
                title: const Text('ワンストップ特例を使う'),
                subtitle: const Text('5自治体までの見張りと申請期限の通知を出します'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _saveConfig(cfg.upsertYear(y.copyWith(
      limitAmount: int.tryParse(ctrl.text) ?? 0,
      useOnestop: useOnestop,
    )));
  }

  Future<void> _editEntry(
      FurusatoConfig cfg, Transaction t, FurusatoEntry e) async {
    final muni = TextEditingController(text: e.municipality);
    final portal = TextEditingController(text: e.portal);
    var cert = e.certificate;
    var onestop = e.onestopApplied;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${t.date.month}/${t.date.day}　'
              '${formatYen(t.amount)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: muni,
                  decoration: const InputDecoration(
                    labelText: '自治体',
                    hintText: '例：神奈川県川崎市',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
                TextField(
                  controller: portal,
                  decoration: const InputDecoration(
                    labelText: 'ポータル',
                    hintText: '例：さとふる',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: V2Spacing.lg),
                Text('受領証明書', style: V2Typography.caption),
                const SizedBox(height: V2Spacing.xs),
                SegmentedButton<FurusatoCertificate>(
                  segments: [
                    for (final c in FurusatoCertificate.values)
                      ButtonSegment(value: c, label: Text(c.label)),
                  ],
                  selected: {cert},
                  onSelectionChanged: (s) =>
                      setLocal(() => cert = s.first),
                ),
                const SizedBox(height: V2Spacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: onestop,
                  onChanged: (v) => setLocal(() => onestop = v),
                  title: const Text('ワンストップ特例を申請した'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _saveConfig(cfg.upsertEntry(e.copyWith(
      municipality: muni.text.trim(),
      portal: portal.text.trim(),
      certificate: cert,
      onestopApplied: onestop,
    )));
  }
}
