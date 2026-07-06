import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/month_cursor.dart';
import '../../data/monthly_snapshot_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/tax_estimate_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/transaction_search_screen.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/month_nav_bar.dart';
import '../widgets/v2_card.dart';

/// 損益計算書（PL）の大カテゴリ分類。
enum _PLCategory {
  sales,
  cogs,
  sga,
  nonOpIncome,
  nonOpExpense,
  extraIncome,
  extraExpense,
  tax,
  other,
}

/// PL テーブルの行種別。
enum _RowKind {
  /// 通常データ行（売上高・売上原価など、大区分の合計）
  data,

  /// 内訳行（販管費の中の「役員報酬」など、インデント表示）
  detail,

  /// 小計行（粗利・営業利益など、黄色背景でハイライト）
  subtotal,

  /// 最終利益（当期純利益、強ハイライト）
  emphasize,
}

/// 販売管理費の標準的な勘定科目（順序固定）。
/// Transaction.category.major でこれに完全一致するものを各内訳として集計。
/// リストにない販管費カテゴリは「その他販管費」に集約する。
const List<String> _sgaItems = [
  '役員報酬',
  '給与',
  '雑給与',
  '賞与・退職金',
  '法定福利費',
  '福利厚生費',
  '広告宣伝費',
  '交際費',
  '会議費',
  '旅費交通費',
  '通信費',
  '消耗品費',
  '修繕費',
  '水道光熱費',
  '新聞図書費',
  '諸会費',
  '支払手数料',
  '賃借料',
  '保険料',
  '租税公課',
  '支払報酬',
  '減価償却費',
  '雑費',
];

/// 営業外収益の標準科目。
const List<String> _nonOpIncomeItems = [
  '受取利息',
  '受取配当金',
  '雑収入',
  '残高調整', // ウォレット残高の手調整（増）。本業の数字を汚さないよう営業外。
];

/// 営業外費用の標準科目。
const List<String> _nonOpExpenseItems = [
  '支払利息',
  '雑損失',
  '残高調整', // ウォレット残高の手調整（減）。営業外。
];

/// 取引の大分類は「0.役員報酬」のように番号プレフィックス付きで保存される一方、
/// 上の標準科目リストは番号なし。照合時に先頭の「N.」を取り除いて正規化する。
/// これで番号がズレても標準科目に正しく集計され、「○○（その他）」化を防ぐ。
String _bareMajor(String major) =>
    major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();

/// v2.1 集計タブ：会計風月次表（PL）。
class V2ReportScreen extends StatefulWidget {
  final Color accent;

  /// true のとき（新デザイン）、上部にダッシュボード帯（月別の収支推移）を出し、
  /// 余白を他タブと同じ密度に詰める。PL（詳細表）はそのまま下に残す。
  final bool richBand;
  const V2ReportScreen(
      {super.key, required this.accent, this.richBand = false});

  @override
  State<V2ReportScreen> createState() => _V2ReportScreenState();
}

class _V2ReportScreenState extends State<V2ReportScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];
  // 会計科目(plMajor)を割り当てたサブスク（固定費/変動費）を PL に合算する。
  List<core.Subscription> _subs = [];
  // 家庭用の「貯金（月初残高）の推移」で使う月初残高スナップショット。
  core.MonthlySnapshotConfig _snapshots = core.MonthlySnapshotConfig.empty();
  // 家庭用グラフの表示年（暦年）。
  int _personalYear = DateTime.now().year;
  bool _loading = true;

  /// 表示モード。false=詳細（フルPL月次表）/ true=簡易（サマリー＋簡易月次表）。
  /// 既定は簡易（軽くて見やすい）。
  bool _simple = true;

  /// 個人の「支出の内訳」を、カテゴリ別(false)か場所別(true)で見るか。
  bool _breakdownByStore = false;

  /// 決算期の期首月。当社は 10月〜翌9月 が事業年度。
  final int _fyStartMonth = 10;
  late int _fyYear = _calcFyYear();

  /// 表示期間。false=当月（単月PL）/ true=1年（年度12ヶ月表）。デフォルトは当月。
  bool _yearView = false;

  /// 当月モードで表示する月（タブ横断で共有＝切替で今月にリセットしない）。
  late DateTime _selMonth = MonthCursor.instance.month;

  /// 表示対象の月リスト（当月=1件、1年=12件）。集計・表はこれを基準に並べる。
  List<DateTime> get _displayMonths => _yearView ? _fyMonths : [_selMonth];

  int _calcFyYear() {
    final now = DateTime.now();
    return now.month >= _fyStartMonth ? now.year : now.year - 1;
  }

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
    // 法人税の概算設定が変わったら再描画。
    TaxEstimateRepository.instance.addListener(_onTaxSettingChanged);
    MonthCursor.instance.addListener(_onMonthCursor);
  }

  void _onTaxSettingChanged() {
    if (mounted) setState(() {});
  }

  /// 他タブで月が変わったら追従。
  void _onMonthCursor() {
    final m = MonthCursor.instance.month;
    if (!mounted) return;
    if (m.year != _selMonth.year || m.month != _selMonth.month) {
      setState(() => _selMonth = DateTime(m.year, m.month));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    TaxEstimateRepository.instance.removeListener(_onTaxSettingChanged);
    MonthCursor.instance.removeListener(_onMonthCursor);
    super.dispose();
  }

  Future<void> _load() async {
    await TaxEstimateRepository.instance.ensureLoaded();
    final txns = await _txRepo.loadAll();
    final subs =
        (await SubscriptionRepository.instance.load()).subscriptions;
    final snaps = await MonthlySnapshotRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _subs = subs;
      _snapshots = snaps;
      _loading = false;
    });
  }

  /// 大カテゴリ分類。
  /// 法人税等の判定は major の完全一致のみ（租税公課は販管費）。
  _PLCategory _classify(core.Transaction t) {
    final major = _bareMajor(t.category.major);
    if (t.type == core.TransactionType.income) {
      if (major.contains('特別')) return _PLCategory.extraIncome;
      if (_nonOpIncomeItems.contains(major) ||
          major.contains('営業外')) {
        return _PLCategory.nonOpIncome;
      }
      return _PLCategory.sales;
    }
    if (t.type == core.TransactionType.expense) {
      // 法人税等は完全一致のみ（"租税公課" は販管費に残す）
      if (major == '法人税等' ||
          major == '法人税' ||
          major == '住民税' ||
          major == '事業税' ||
          major == '所得税') {
        return _PLCategory.tax;
      }
      if (major.contains('特別')) return _PLCategory.extraExpense;
      if (_nonOpExpenseItems.contains(major) ||
          major.contains('営業外')) {
        return _PLCategory.nonOpExpense;
      }
      if (major.contains('原価') ||
          major.contains('仕入') ||
          major.contains('外注')) {
        return _PLCategory.cogs;
      }
      return _PLCategory.sga;
    }
    return _PLCategory.other;
  }

  /// 科目名（経費）→ PL大カテゴリ。サブスクの plMajor 分類に使う。
  /// _classify の expense ブランチと同じ規則。
  _PLCategory _classifyExpenseMajor(String rawMajor) {
    final major = _bareMajor(rawMajor);
    if (major == '法人税等' ||
        major == '法人税' ||
        major == '住民税' ||
        major == '事業税' ||
        major == '所得税') {
      return _PLCategory.tax;
    }
    if (major.contains('特別')) return _PLCategory.extraExpense;
    if (_nonOpExpenseItems.contains(major) || major.contains('営業外')) {
      return _PLCategory.nonOpExpense;
    }
    if (major.contains('原価') ||
        major.contains('仕入') ||
        major.contains('外注')) {
      return _PLCategory.cogs;
    }
    return _PLCategory.sga;
  }

  /// 当月の "YYYY-MM"（PL計上の上限月）。
  String get _currentYm {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  /// サブスク（plMajor 指定あり）の、指定科目の月次合算（12ヶ月）。
  List<int> _subsMonthlyForMajor(String major) {
    final months = _displayMonths;
    final res = List<int>.filled(months.length, 0);
    final cur = _currentYm;
    for (final s in _subs) {
      final pm = s.plMajor;
      if (pm == null || _bareMajor(pm) != major) continue;
      for (int i = 0; i < months.length; i++) {
        final m = months[i];
        final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        res[i] += s.plAmountForMonth(ym, cur);
      }
    }
    return res;
  }

  /// サブスク（plMajor 指定あり）の、指定大カテゴリの月次合算（12ヶ月）。
  List<int> _subsMonthlyForCategory(_PLCategory c) {
    final months = _displayMonths;
    final res = List<int>.filled(months.length, 0);
    final cur = _currentYm;
    for (final s in _subs) {
      final pm = s.plMajor;
      if (pm == null || _classifyExpenseMajor(pm) != c) continue;
      for (int i = 0; i < months.length; i++) {
        final m = months[i];
        final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        res[i] += s.plAmountForMonth(ym, cur);
      }
    }
    return res;
  }

  /// 事業年度の各月（12 件）
  List<DateTime> get _fyMonths => List.generate(12, (i) {
        final m = _fyStartMonth + i;
        final y = _fyYear + (m > 12 ? 1 : 0);
        final mm = m > 12 ? m - 12 : m;
        return DateTime(y, mm);
      });

  /// 指定大カテゴリの月次集計
  List<int> _monthlyForCategory(_PLCategory c) {
    final months = _displayMonths;
    final result = List<int>.filled(months.length, 0);
    for (final t in _transactions) {
      if (_classify(t) != c) continue;
      final idx = months.indexWhere(
          (m) => m.year == t.date.year && m.month == t.date.month);
      if (idx < 0) continue;
      result[idx] += t.effectiveAmount;
    }
    // サブスク（会計科目を紐付けたもの）を合算。
    final subs = _subsMonthlyForCategory(c);
    for (int i = 0; i < months.length; i++) {
      result[i] += subs[i];
    }
    return result;
  }

  /// 指定大カテゴリ × 指定 major の月次集計
  List<int> _monthlyForItem(_PLCategory c, String major) {
    final months = _displayMonths;
    final result = List<int>.filled(months.length, 0);
    for (final t in _transactions) {
      if (_classify(t) != c) continue;
      if (_bareMajor(t.category.major) != major) continue;
      final idx = months.indexWhere(
          (m) => m.year == t.date.year && m.month == t.date.month);
      if (idx < 0) continue;
      result[idx] += t.effectiveAmount;
    }
    // この科目に紐付くサブスクを合算（同じ大カテゴリのときのみ）。
    if (_classifyExpenseMajor(major) == c) {
      final subs = _subsMonthlyForMajor(major);
      for (int i = 0; i < months.length; i++) {
        result[i] += subs[i];
      }
    }
    return result;
  }

  /// 指定大カテゴリの「リストに無い」内訳の major リスト（出現順）
  List<String> _unlistedMajors(
      _PLCategory c, List<String> knownItems) {
    final seen = <String>{};
    final list = <String>[];
    for (final t in _transactions) {
      if (_classify(t) != c) continue;
      final major = _bareMajor(t.category.major);
      if (major.isEmpty) continue;
      if (knownItems.contains(major)) continue;
      if (seen.add(major)) list.add(major);
    }
    // 標準科目リストに無い科目を持つサブスクも内訳行として出す。
    for (final s in _subs) {
      final pm = s.plMajor;
      if (pm == null) continue;
      if (_classifyExpenseMajor(pm) != c) continue;
      final major = _bareMajor(pm);
      if (major.isEmpty) continue;
      if (knownItems.contains(major)) continue;
      if (seen.add(major)) list.add(major);
    }
    return list;
  }

  void _shiftYear(int delta) {
    setState(() => _fyYear += delta);
  }

  void _shiftMonth(int delta) {
    setState(() =>
        _selMonth = DateTime(_selMonth.year, _selMonth.month + delta));
    MonthCursor.instance.month = _selMonth; // タブ横断で共有
  }

  /// 「明細を検索・一括編集」への入口（集計タブ上部）。
  Widget _searchEntry() {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.md),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TransactionSearchScreen()),
          ),
          icon: const Icon(Icons.manage_search, size: 18),
          label: const Text('明細を検索・一括編集'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // 家庭用は PL/BS ではなく「貯金の推移」「月別収支」を見せる。
    if (AppModeManager.instance.current != AppMode.business) {
      return _personalReport();
    }

    final months = _displayMonths;
    // 期末（期首の前月）。期首が1月のときだけ同年内で完結する。
    final fyEndMonth = _fyStartMonth == 1 ? 12 : _fyStartMonth - 1;
    final fyEndYear = _fyStartMonth == 1 ? _fyYear : _fyYear + 1;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          vertical: widget.richBand ? V2Spacing.lg : V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchEntry(),
          // 期間(当月/1年) + 詳細/簡易 切替 + 月/年ナビ
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.md),
            child: Wrap(
              spacing: V2Spacing.md,
              runSpacing: V2Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 当月 / 1年
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('当月'),
                        icon: Icon(Icons.today, size: 16)),
                    ButtonSegment(
                        value: true,
                        label: Text('1年'),
                        icon: Icon(Icons.calendar_month, size: 16)),
                  ],
                  selected: {_yearView},
                  onSelectionChanged: (s) =>
                      setState(() => _yearView = s.first),
                ),
                // 簡易 / 詳細（簡易を左・既定）
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: true,
                        label: Text('簡易'),
                        icon: Icon(Icons.summarize, size: 16)),
                    ButtonSegment(
                        value: false,
                        label: Text('詳細'),
                        icon: Icon(Icons.table_rows, size: 16)),
                  ],
                  selected: {_simple},
                  onSelectionChanged: (s) =>
                      setState(() => _simple = s.first),
                ),
                // ナビ（当月=月送り / 1年=年度送り）
                if (_yearView)
                  MonthNavBar(
                    label:
                        '$_fyYear 年度（$_fyStartMonth月〜$fyEndYear年$fyEndMonth月）',
                    onPrev: () => _shiftYear(-1),
                    onNext: () => _shiftYear(1),
                  )
                else
                  MonthNavBar(
                    label: '${_selMonth.year}年${_selMonth.month}月',
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                  ),
              ],
            ),
          ),
          if (_simple) ...[
            _simpleSummaryCard(),
            const SizedBox(height: V2Spacing.lg),
            _simpleTableCard(months),
          ] else ...[
            _detailedTableCard(months),
            const SizedBox(height: V2Spacing.lg),
            _categoryNoteCard(),
          ],
        ],
      ),
    );
  }

  // ── 家庭用：貯金の推移＋月別収支（暦年・棒グラフ）──────────────
  Widget _personalReport() {
    final year = _personalYear;
    final nets = <int>[];
    final balances = <int?>[];
    final labels = <String>[];
    var yearNet = 0;
    var hasAnyTx = false;
    for (int m = 1; m <= 12; m++) {
      var inc = 0, exp = 0;
      for (final t in _transactions) {
        if (t.date.year != year || t.date.month != m) continue;
        hasAnyTx = true;
        if (t.type == core.TransactionType.income) {
          inc += t.amount;
        } else if (t.type == core.TransactionType.expense) {
          exp += t.effectiveAmount;
        }
      }
      final net = inc - exp;
      nets.add(net);
      yearNet += net;
      balances.add(_snapshots.forMonth(year, m)?.initialBalance);
      labels.add('$m');
    }
    final hasAnyBalance = balances.any((b) => b != null);

    // 支出の内訳（その年・大カテゴリ別・実質コスト）。円グラフ用。
    final byMajor = <String, int>{};
    for (final t in _transactions) {
      if (t.date.year != year) continue;
      if (t.type != core.TransactionType.expense) continue;
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.effectiveAmount;
    }
    final catEntries = byMajor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final catTotal = byMajor.values.fold<int>(0, (s, v) => s + v);

    // 支出の内訳（場所別・実質コスト）。カテゴリ別と切替表示する。
    final byStore = <String, int>{};
    for (final t in _transactions) {
      if (t.date.year != year) continue;
      if (t.type != core.TransactionType.expense) continue;
      final store =
          (t.store ?? '').trim().isEmpty ? '（場所なし）' : t.store!.trim();
      byStore[store] = (byStore[store] ?? 0) + t.effectiveAmount;
    }
    final storeEntries = byStore.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final storeTotal = byStore.values.fold<int>(0, (s, v) => s + v);

    // 内訳カードで表示する側（カテゴリ or 場所）。
    final bkEntries = _breakdownByStore ? storeEntries : catEntries;
    final bkTotal = _breakdownByStore ? storeTotal : catTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchEntry(),
          // 年ナビ（暦年）
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _personalYear--),
                  tooltip: '前の年',
                ),
                Text('$year年',
                    style: V2Typography.h2
                        .copyWith(color: V2Colors.textPrimary)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _personalYear++),
                  tooltip: '次の年',
                ),
              ],
            ),
          ),
          _chartCard(
            title: '月別の収支（収入 − 支出）',
            trailing: '年間 ${formatYen(yearNet, withSign: true)}',
            trailingColor:
                yearNet >= 0 ? V2Colors.positive : V2Colors.negative,
            empty: !hasAnyTx,
            emptyText: '$year年の記録がまだありません',
            child: _MiniBarChart(values: nets, labels: labels, signed: true),
          ),
          const SizedBox(height: V2Spacing.lg),
          _chartCard(
            title: _breakdownByStore ? '支出の内訳（場所別）' : '支出の内訳（カテゴリ別）',
            trailing: '年間 ${formatYen(bkTotal)}',
            empty: bkTotal <= 0,
            emptyText: '$year年の支出がまだありません',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // カテゴリ別／場所別の切替。
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          label: Text('カテゴリ別'),
                          icon: Icon(Icons.category_outlined, size: 16)),
                      ButtonSegment(
                          value: true,
                          label: Text('場所別'),
                          icon: Icon(Icons.place_outlined, size: 16)),
                    ],
                    selected: {_breakdownByStore},
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(
                          V2Typography.caption),
                    ),
                    onSelectionChanged: (s) =>
                        setState(() => _breakdownByStore = s.first),
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
                _PieBreakdown(entries: bkEntries, total: bkTotal),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.lg),
          _chartCard(
            title: '貯金（月初残高）の推移',
            empty: !hasAnyBalance,
            emptyText: '月初残高がまだ記録されていません'
                '（ホームの総資産カードで月初残高を入れると推移が出ます）',
            child: _MiniBarChart(
                values: balances, labels: labels, signed: false),
          ),
          const SizedBox(height: V2Spacing.lg),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required bool empty,
    required String emptyText,
    required Widget child,
    String? trailing,
    Color? trailingColor,
  }) {
    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: V2Typography.h2
                        .copyWith(color: V2Colors.textPrimary)),
              ),
              if (trailing != null)
                Text(trailing,
                    style: V2Typography.bodyStrong.copyWith(
                        color: trailingColor ?? V2Colors.textPrimary,
                        fontFeatures: V2Typography.tabularNums)),
            ],
          ),
          const SizedBox(height: V2Spacing.md),
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(emptyText,
                  textAlign: TextAlign.center,
                  style: V2Typography.caption
                      .copyWith(color: V2Colors.textSecondary)),
            )
          else
            child,
        ],
      ),
    );
  }

  // ── 詳細：フル PL 月次表 ──
  Widget _detailedTableCard(List<DateTime> months) {
    return V2Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.sm),
            child: Row(
              children: [
                Icon(Icons.table_chart_outlined,
                    size: 18, color: widget.accent),
                const SizedBox(width: V2Spacing.sm),
                Text('会計風 月次表（PL）', style: V2Typography.h2),
                const SizedBox(width: V2Spacing.sm),
                Text('← 横スクロール →',
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textMuted)),
              ],
            ),
          ),
          _PLTable(
              months: months,
              rows: _buildRows(),
              totalLabel: _yearView ? '年度累計' : '合計'),
          const SizedBox(height: V2Spacing.md),
          _taxEstimateCard(),
        ],
      ),
    );
  }

  /// 法人税等を概算で計上する設定カード（業績タブ内）。
  Widget _taxEstimateCard() {
    final t = TaxEstimateRepository.instance;
    const rates = [20, 25, 30, 35, 40];
    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('法人税等を概算で計上',
                    style: V2Typography.bodyStrong
                        .copyWith(color: V2Colors.textPrimary)),
              ),
              Switch(
                value: t.enabled,
                activeThumbColor: V2Colors.accent,
                onChanged: (v) => t.setEnabled(v),
              ),
            ],
          ),
          if (t.enabled) ...[
            const SizedBox(height: V2Spacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('実効税率', style: V2Typography.caption),
                ...rates.map((p) => ChoiceChip(
                      label: Text('$p%'),
                      selected: t.ratePercent == p,
                      onSelected: (_) => t.setRatePercent(p),
                      visualDensity: VisualDensity.compact,
                    )),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '税引前利益（黒字の分）に税率をかけた見込みです。'
              '確定申告の数字ではありません。赤字の期は0。',
              style:
                  V2Typography.micro.copyWith(color: V2Colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryNoteCard() {
    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PL カテゴリ判定',
              style: V2Typography.bodyStrong
                  .copyWith(color: V2Colors.textPrimary)),
          const SizedBox(height: V2Spacing.sm),
          Text(
            '・通常 income → 売上高\n'
            '・「原価」「仕入」を含む expense → 売上原価\n'
            '・「営業外」or 受取利息/受取配当金/雑収入 → 営業外収益\n'
            '・「営業外」or 支払利息/雑損失 → 営業外費用\n'
            '・「特別」を含む → 特別利益 / 損失\n'
            '・法人税 / 住民税 / 事業税 / 所得税（完全一致） → 法人税等\n'
            '・上記以外の expense → 販売管理費（内訳は標準勘定科目で表示）',
            style: V2Typography.caption,
          ),
        ],
      ),
    );
  }

  // ── 簡易：サマリー（売上/原価/粗利/販管費/営業利益＋各率） ──
  Widget _simpleSummaryCard() {
    final sales =
        _monthlyForCategory(_PLCategory.sales).fold<int>(0, (s, v) => s + v);
    final cogs =
        _monthlyForCategory(_PLCategory.cogs).fold<int>(0, (s, v) => s + v);
    final sga =
        _monthlyForCategory(_PLCategory.sga).fold<int>(0, (s, v) => s + v);
    final gross = sales - cogs;
    final oper = gross - sga;
    double pct(int part) => sales == 0 ? 0 : part / sales * 100;

    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_yearView ? '年度サマリー' : '当月サマリー',
              style: V2Typography.caption),
          const SizedBox(height: V2Spacing.sm),
          _summaryRow('売上', sales, V2Colors.positive),
          _summaryRow('原価', -cogs, V2Colors.negative),
          _summaryRow('粗利（売上 − 原価）', gross, V2Colors.positive,
              strong: true),
          _summaryRow('販管費', -sga, V2Colors.negative),
          const Divider(),
          _summaryRow('営業利益（粗利 − 販管費）', oper,
              oper >= 0 ? V2Colors.positive : V2Colors.negative,
              strong: true, big: true),
          const SizedBox(height: V2Spacing.md),
          Row(
            children: [
              Expanded(
                  child: _ratioBadge('原価率', pct(cogs),
                      const Color(0xFFDC2626))),
              const SizedBox(width: V2Spacing.sm),
              Expanded(
                  child: _ratioBadge('粗利率', pct(gross),
                      const Color(0xFF16A34A))),
              const SizedBox(width: V2Spacing.sm),
              Expanded(
                  child: _ratioBadge('営業利益率', pct(oper),
                      const Color(0xFF1A237E))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, int amount, Color color,
      {bool strong = false, bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: strong
                  ? V2Typography.bodyStrong
                      .copyWith(color: V2Colors.textPrimary)
                  : V2Typography.body),
          Text(formatYen(amount, withSign: true),
              style: TextStyle(
                  fontSize: big ? 22 : 15,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }

  Widget _ratioBadge(String label, double pct, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label,
              style: V2Typography.micro.copyWith(color: color)),
          const SizedBox(height: 2),
          Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: V2Typography.tabularNums)),
        ],
      ),
    );
  }

  // ── 簡易：会計風 月次表（横スクロール・売上/原価/粗利/販管費/営業利益のみ） ──
  Widget _simpleTableCard(List<DateTime> months) {
    final sales = _monthlyForCategory(_PLCategory.sales);
    final cogs = _monthlyForCategory(_PLCategory.cogs);
    final sga = _monthlyForCategory(_PLCategory.sga);
    final gross = _diff(sales, cogs);
    final oper = _diff(gross, sga);
    final rows = <_PLRow>[
      _PLRow(label: '売上', monthly: sales, kind: _RowKind.data),
      _PLRow(label: '原価', monthly: cogs, kind: _RowKind.data),
      _PLRow(label: '粗利', monthly: gross, kind: _RowKind.subtotal),
      _PLRow(label: '販管費', monthly: sga, kind: _RowKind.data),
      _PLRow(label: '営業利益', monthly: oper, kind: _RowKind.emphasize),
    ];
    return V2Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                V2Spacing.lg, V2Spacing.md, V2Spacing.lg, V2Spacing.sm),
            child: Row(
              children: [
                Icon(Icons.table_chart_outlined,
                    size: 18, color: widget.accent),
                const SizedBox(width: V2Spacing.sm),
                Text('会計風 月次表（簡易）', style: V2Typography.h2),
                const SizedBox(width: V2Spacing.sm),
                Text('← 横スクロール →',
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textMuted)),
              ],
            ),
          ),
          _PLTable(
              months: months,
              rows: rows,
              totalLabel: _yearView ? '年度累計' : '合計'),
        ],
      ),
    );
  }

  /// PL テーブルの行リストを構築
  List<_PLRow> _buildRows() {
    final salesMonthly = _monthlyForCategory(_PLCategory.sales);
    final cogsMonthly = _monthlyForCategory(_PLCategory.cogs);
    final sgaMonthly = _monthlyForCategory(_PLCategory.sga);
    final nonOpIncomeMonthly =
        _monthlyForCategory(_PLCategory.nonOpIncome);
    final nonOpExpenseMonthly =
        _monthlyForCategory(_PLCategory.nonOpExpense);
    final extraIncomeMonthly =
        _monthlyForCategory(_PLCategory.extraIncome);
    final extraExpenseMonthly =
        _monthlyForCategory(_PLCategory.extraExpense);
    final taxMonthly = _monthlyForCategory(_PLCategory.tax);

    final gross = _diff(salesMonthly, cogsMonthly);
    final oper = _diff(gross, sgaMonthly);
    final ord = _addSub(oper, nonOpIncomeMonthly, nonOpExpenseMonthly);
    final preTax =
        _addSub(ord, extraIncomeMonthly, extraExpenseMonthly);
    // 法人税等: 概算ONなら税引前利益(黒字分)に実効税率をかけた見込み額、
    // OFFなら実際に記帳された税額(_PLCategory.tax)を使う。
    final taxEst = TaxEstimateRepository.instance;
    final effectiveTax =
        taxEst.enabled ? taxEst.estimateFor(preTax) : taxMonthly;
    final net = _diff(preTax, effectiveTax);

    final unlistedSga = _unlistedMajors(_PLCategory.sga, _sgaItems);
    final unlistedNonOpIn =
        _unlistedMajors(_PLCategory.nonOpIncome, _nonOpIncomeItems);
    final unlistedNonOpEx =
        _unlistedMajors(_PLCategory.nonOpExpense, _nonOpExpenseItems);

    final rows = <_PLRow>[];

    // ── 売上（科目＝収入源別に内訳表示） ──
    rows.add(_PLRow(
        label: '売上高', monthly: salesMonthly, kind: _RowKind.data));
    // 売上の内訳（収入源＝売上科目ごと）。出現順。
    for (final m in _unlistedMajors(_PLCategory.sales, const [])) {
      rows.add(_PLRow(
        label: m,
        monthly: _monthlyForItem(_PLCategory.sales, m),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '売上原価', monthly: cogsMonthly, kind: _RowKind.data));
    rows.add(_PLRow(
        label: '売上総利益', monthly: gross, kind: _RowKind.subtotal));

    // ── 販管費（内訳付き） ──
    for (final item in _sgaItems) {
      rows.add(_PLRow(
        label: item,
        monthly: _monthlyForItem(_PLCategory.sga, item),
        kind: _RowKind.detail,
      ));
    }
    for (final item in unlistedSga) {
      rows.add(_PLRow(
        label: '$item（その他）',
        monthly: _monthlyForItem(_PLCategory.sga, item),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '販管費 合計', monthly: sgaMonthly, kind: _RowKind.data));
    rows.add(_PLRow(
        label: '営業利益', monthly: oper, kind: _RowKind.subtotal));

    // ── 営業外収益 ──
    for (final item in _nonOpIncomeItems) {
      rows.add(_PLRow(
        label: item,
        monthly: _monthlyForItem(_PLCategory.nonOpIncome, item),
        kind: _RowKind.detail,
      ));
    }
    for (final item in unlistedNonOpIn) {
      rows.add(_PLRow(
        label: '$item（その他）',
        monthly: _monthlyForItem(_PLCategory.nonOpIncome, item),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '営業外収益 合計',
        monthly: nonOpIncomeMonthly,
        kind: _RowKind.data));

    // ── 営業外費用 ──
    for (final item in _nonOpExpenseItems) {
      rows.add(_PLRow(
        label: item,
        monthly: _monthlyForItem(_PLCategory.nonOpExpense, item),
        kind: _RowKind.detail,
      ));
    }
    for (final item in unlistedNonOpEx) {
      rows.add(_PLRow(
        label: '$item（その他）',
        monthly: _monthlyForItem(_PLCategory.nonOpExpense, item),
        kind: _RowKind.detail,
      ));
    }
    rows.add(_PLRow(
        label: '営業外費用 合計',
        monthly: nonOpExpenseMonthly,
        kind: _RowKind.data));

    rows.add(_PLRow(
        label: '経常利益', monthly: ord, kind: _RowKind.subtotal));

    // ── 特別利益 / 損失 ──
    rows.add(_PLRow(
        label: '特別利益',
        monthly: extraIncomeMonthly,
        kind: _RowKind.data));
    rows.add(_PLRow(
        label: '特別損失',
        monthly: extraExpenseMonthly,
        kind: _RowKind.data));

    rows.add(_PLRow(
        label: '税引前当期純利益',
        monthly: preTax,
        kind: _RowKind.subtotal));

    // ── 法人税等 ──
    rows.add(_PLRow(
        label: taxEst.enabled ? '法人税等（概算${taxEst.ratePercent}%）' : '法人税等',
        monthly: effectiveTax,
        kind: _RowKind.data));

    rows.add(_PLRow(
        label: '当期純利益', monthly: net, kind: _RowKind.emphasize));

    return rows;
  }

  /// 配列同士の差分（同じ index 同士）。表示月数に追従（当月=1 / 1年=12）。
  List<int> _diff(List<int> a, List<int> b) =>
      List.generate(a.length, (i) => a[i] - b[i]);

  /// a + b - c（表示月数に追従）
  List<int> _addSub(List<int> a, List<int> b, List<int> c) =>
      List.generate(a.length, (i) => a[i] + b[i] - c[i]);
}

class _PLRow {
  final String label;
  final List<int> monthly;
  final _RowKind kind;
  const _PLRow({
    required this.label,
    required this.monthly,
    required this.kind,
  });

  int get total => monthly.fold<int>(0, (s, v) => s + v);
}

// ═════════════════════════════════════════════════
// テーブル本体（横スクロール）
// ═════════════════════════════════════════════════

/// 月／年度を前後に送るナビ（◀ ラベル ▶）。
class _PLTable extends StatelessWidget {
  final List<DateTime> months;
  final List<_PLRow> rows;
  final String totalLabel;
  const _PLTable(
      {required this.months,
      required this.rows,
      this.totalLabel = '年度累計'});

  static const labelColWidth = 160.0;
  static const monthColWidth = 90.0;
  static const totalColWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: V2Colors.border, width: 1)),
        ),
        child: Column(
          children: [
            _HeaderRow(months: months, totalLabel: totalLabel),
            for (final r in rows) _BodyRow(row: r),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<DateTime> months;
  final String totalLabel;
  const _HeaderRow({required this.months, this.totalLabel = '年度累計'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surfaceMuted,
      child: Row(
        children: [
          SizedBox(
            width: _PLTable.labelColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.md, vertical: 8),
              child:
                  Text('項目', style: V2Typography.tableHeader),
            ),
          ),
          for (final m in months)
            SizedBox(
              width: _PLTable.monthColWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.sm, vertical: 8),
                child: Text(
                  '${m.month}月',
                  style: V2Typography.tableHeader,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          SizedBox(
            width: _PLTable.totalColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.sm, vertical: 8),
              child: Text(
                totalLabel,
                style: V2Typography.tableHeader.copyWith(
                    color: V2Colors.textPrimary,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  final _PLRow row;
  const _BodyRow({required this.row});

  Color _colorFor(int v) {
    if (v == 0) return V2Colors.textMuted;
    return v > 0 ? V2Colors.positive : V2Colors.negative;
  }

  @override
  Widget build(BuildContext context) {
    final isSubtotal = row.kind == _RowKind.subtotal;
    final isEmphasize = row.kind == _RowKind.emphasize;
    final isDetail = row.kind == _RowKind.detail;
    final highlightBg = isSubtotal
        ? const Color(0xFFFFFBEB)
        : (isEmphasize ? const Color(0xFFFEF9C3) : null);

    final labelStyle = isDetail
        ? V2Typography.caption.copyWith(
            color: V2Colors.textSecondary)
        : (isSubtotal || isEmphasize)
            ? V2Typography.bodyStrong.copyWith(
                color: V2Colors.textPrimary,
                fontWeight: isEmphasize
                    ? FontWeight.w800
                    : FontWeight.w700)
            : V2Typography.body;

    Color valueColor(int v) {
      if (isDetail) {
        return v == 0
            ? V2Colors.textMuted
            : V2Colors.textSecondary;
      }
      if (isSubtotal || isEmphasize) return _colorFor(v);
      return v == 0 ? V2Colors.textMuted : V2Colors.textPrimary;
    }

    final cellPadding = isDetail
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 8);

    return Container(
      decoration: BoxDecoration(
        color: highlightBg,
        border: Border(
            top: BorderSide(
                color: isSubtotal || isEmphasize
                    ? V2Colors.border
                    : V2Colors.divider,
                width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _PLTable.labelColWidth,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  isDetail ? 28 : 12,
                  cellPadding.vertical / 2,
                  12,
                  cellPadding.vertical / 2),
              child: Text(row.label, style: labelStyle),
            ),
          ),
          for (final v in row.monthly)
            SizedBox(
              width: _PLTable.monthColWidth,
              child: Padding(
                padding: cellPadding,
                child: Text(
                  v == 0 ? '0' : formatYen(v),
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                      color: valueColor(v),
                      fontSize: isDetail ? 11 : 13,
                      fontWeight: (isSubtotal || isEmphasize)
                          ? FontWeight.w700
                          : (isDetail
                              ? FontWeight.w500
                              : FontWeight.w600)),
                ),
              ),
            ),
          SizedBox(
            width: _PLTable.totalColWidth,
            child: Padding(
              padding: cellPadding,
              child: Text(
                row.total == 0 ? '0' : formatYen(row.total),
                textAlign: TextAlign.right,
                style: V2Typography.numericCell.copyWith(
                    color: valueColor(row.total),
                    fontSize: isEmphasize
                        ? 14
                        : (isDetail ? 11 : 13),
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 家庭用レポートの簡易棒グラフ（依存ライブラリ無し・自前描画）。
/// signed=true: 中央基線で +緑/−赤。signed=false: 下基線で上のみ（藍）。
class _MiniBarChart extends StatelessWidget {
  final List<int?> values;
  final List<String> labels;
  final bool signed;
  const _MiniBarChart({
    required this.values,
    required this.labels,
    this.signed = true,
  });

  @override
  Widget build(BuildContext context) {
    final nonNull = values.whereType<int>().toList();
    final maxAbs = nonNull.isEmpty
        ? 1
        : nonNull
            .map((v) => v.abs())
            .fold<int>(1, (a, b) => a > b ? a : b);
    const h = 150.0;
    return Column(
      children: [
        SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < values.length; i++)
                Expanded(child: _bar(values[i], maxAbs)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Text(l,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF9CA3AF))),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bar(int? v, int maxAbs) {
    if (v == null) return const SizedBox();
    final frac = (v.abs() / maxAbs).clamp(0.0, 1.0);
    if (!signed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: frac == 0 ? 0.01 : frac,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ),
        ),
      );
    }
    final color =
        v < 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: v > 0
                  ? FractionallySizedBox(
                      heightFactor: frac,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: v < 0
                  ? FractionallySizedBox(
                      heightFactor: frac,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(3)),
                        ),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 家庭用レポートの支出内訳（ドーナツ円グラフ＋凡例）。依存ライブラリ無し・自前描画。
class _PieBreakdown extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  const _PieBreakdown({required this.entries, required this.total});

  static const _palette = [
    Color(0xFF6366F1),
    Color(0xFFEC4899),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    // 上位8＋その他にまとめる。
    final top = entries.take(8).toList();
    final restSum = entries.skip(8).fold<int>(0, (s, e) => s + e.value);
    final segs = <(String, int)>[for (final e in top) (e.key, e.value)];
    if (restSum > 0) segs.add(('その他', restSum));

    final donut = SizedBox(
      width: 150,
      height: 150,
      child: CustomPaint(
        painter: _DonutPainter(
            segs.map((s) => s.$2).toList(growable: false), _palette),
      ),
    );
    Widget legend() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < segs.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _palette[i % _palette.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(segs[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text('${(segs[i].$2 * 100 / total).round()}%',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                    const SizedBox(width: 10),
                    Text(formatYen(segs[i].$2),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        );

    return LayoutBuilder(builder: (ctx, cons) {
      final wide = cons.maxWidth >= 420;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            donut,
            const SizedBox(width: 20),
            Expanded(child: legend()),
          ],
        );
      }
      return Column(children: [donut, const SizedBox(height: 14), legend()]);
    });
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> values;
  final List<Color> palette;
  _DonutPainter(this.values, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (s, v) => s + v);
    if (total <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final stroke = radius * 0.42;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    var start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = palette[i % palette.length];
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values;
}
