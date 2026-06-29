import 'dart:async';
import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../../data/app_mode.dart';
import '../../data/backup_repository.dart';
import '../../data/csv_picker.dart';
import '../../data/debug_log.dart';
import '../../data/settings_repository.dart';
import '../../data/store_category_classifier.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../screens/card_csv_import_screen.dart';
import '../../utils/formatters.dart';
import '../../utils/modal_input.dart';
import '../../utils/thousands_separator_input_formatter.dart';
import '../../widgets/brand_logo.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

// ═════════════════════════════════════════════════
// クレカ引落照合セクション + 棚卸しシート（共有）
//
// モバイル幅(v2_expenses)とリッチUI(rich_expenses)の両方から使う。
// ═════════════════════════════════════════════════

/// 照合の対象ウォレット（カード／銀行／現金／電子マネーを共通に扱う器）。
class ReconcileWallet {
  final String name;
  final String? iconUrl;
  final IconData fallbackIcon;

  /// 荒療治（CSV置換・初期化）はカードのみ。現金/PayPay/銀行は簡易（予定vs実際＋突合）。
  final bool isCard;

  /// 副題（例「引き落とし日：毎月27日」「銀行口座」「電子マネー」）。
  final String? subtitle;

  const ReconcileWallet({
    required this.name,
    this.iconUrl,
    this.fallbackIcon = Icons.account_balance_wallet_outlined,
    this.isCard = false,
    this.subtitle,
  });
}

/// 全ウォレット（クレジット・現金・PayPay・銀行）で「予定（記録した明細合計）vs
/// 実際（手入力）」を並べ、差分で棚卸しを促す。行タップで照合シートを開く。
class CreditCardBillingSection extends StatelessWidget {
  final List<core.RegisteredCreditCard> cards;
  final List<core.RegisteredBankAccount> bankAccounts;
  final List<core.Transaction> transactions;

  /// このウォレット払いの固定費（サブスク）も予定に含めるため受け取る。
  final List<core.Subscription> subscriptions;
  final String ym;

  /// 行タップ → 照合シートを開く。
  final void Function(ReconcileWallet wallet) onOpenReconcile;

  const CreditCardBillingSection({
    super.key,
    required this.cards,
    this.bankAccounts = const [],
    required this.transactions,
    this.subscriptions = const [],
    required this.ym,
    required this.onOpenReconcile,
  });

  /// 当月・当ウォレットの明細合計（予定金額）。取引＋このウォレット払いの固定費。
  int _planned(String name) {
    final parts = ym.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final txSum = transactions
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == name &&
            t.date.year == year &&
            t.date.month == month)
        .fold(0, (s, t) => s + t.amount);
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final subSum = subscriptions
        .where((s) => (s.paymentMethod ?? '') == name)
        .fold(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
    return txSum + subSum;
  }

  static IconData _iconForAccount(core.AccountType t) {
    switch (t) {
      case core.AccountType.cash:
        return Icons.payments_outlined;
      case core.AccountType.emoney:
        return Icons.contactless_outlined;
      case core.AccountType.bank:
        return Icons.account_balance_outlined;
    }
  }

  static String _labelForAccount(core.AccountType t) {
    switch (t) {
      case core.AccountType.cash:
        return '現金';
      case core.AccountType.emoney:
        return '電子マネー';
      case core.AccountType.bank:
        return '銀行口座';
    }
  }

  /// 表示するウォレット行。
  /// - 現金 / 電子マネー(PayPay等)：毎月照合するので**常に表示**。
  /// - カード / 銀行：当月に活動（予定>0）or 実際入力済みのときだけ表示（休眠中は隠す）。
  /// - 未登録でも当月その支払方法の取引があれば自動で出す。
  List<({ReconcileWallet wallet, int planned, int? actual})> get _rows {
    final out = <({ReconcileWallet wallet, int planned, int? actual})>[];
    final registered = <String>{};
    // 登録カード（活動 or 実際入力済みのみ）。
    for (final c in cards) {
      registered.add(c.name);
      final planned = _planned(c.name);
      final actual = c.monthlyActualBillings[ym];
      if (planned <= 0 && actual == null) continue;
      out.add((
        wallet: ReconcileWallet(
          name: c.name,
          iconUrl: c.iconUrl,
          fallbackIcon: Icons.credit_card,
          isCard: true,
          subtitle: 'クレジットカード',
        ),
        planned: planned,
        actual: actual,
      ));
    }
    // 登録口座/現金/電子マネー。現金・電子マネーは常に、銀行は活動時のみ表示。
    for (final b in bankAccounts) {
      registered.add(b.name);
      final planned = _planned(b.name);
      final actual = b.monthlyActualBillings[ym];
      final alwaysShow = b.accountType == core.AccountType.cash ||
          b.accountType == core.AccountType.emoney;
      if (!alwaysShow && planned <= 0 && actual == null) continue;
      out.add((
        wallet: ReconcileWallet(
          name: b.name,
          iconUrl: b.iconUrl,
          fallbackIcon: _iconForAccount(b.accountType),
          isCard: false,
          subtitle: _labelForAccount(b.accountType),
        ),
        planned: planned,
        actual: actual,
      ));
    }
    // 未登録でも当月に使われた支払方法（例「PayPay」「現金」を未登録で手入力）は自動表示。
    final parts = ym.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final adhoc = <String>{};
    for (final t in transactions) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.date.year != year || t.date.month != month) continue;
      final pm = t.paymentMethod.trim();
      if (pm.isEmpty || registered.contains(pm) || !adhoc.add(pm)) continue;
      out.add((
        wallet: ReconcileWallet(
          name: pm,
          fallbackIcon: Icons.account_balance_wallet_outlined,
          isCard: false,
          subtitle: '未登録の支払方法',
        ),
        planned: _planned(pm),
        actual: null,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: V2Spacing.sm),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: V2Spacing.sm),
              Text('ウォレット',
                  style: V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: V2Colors.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: V2Colors.divider),
                _BillingRow(
                  wallet: rows[i].wallet,
                  planned: rows[i].planned,
                  actual: rows[i].actual,
                  onOpenReconcile: onOpenReconcile,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// クレカ引落の棚卸しシートを開く。
///
/// [onSaveActual] 実際請求額の保存（null でクリア）。
/// [onEditTxn] / [onDeleteTxn] 明細の編集・削除。
/// [onAddAdjustment] 支出を追加（差額ぶん／明細コピペ突合の記録漏れ補完で使用）。
///   description/date を渡すと支出入力にプリフィルする。
Future<void> showCardReconcileSheet(
  BuildContext context, {
  required ReconcileWallet wallet,
  required int? initialActual,
  required String ym,
  required Future<void> Function(int? amount) onSaveActual,
  required Future<void> Function(core.Transaction t) onEditTxn,
  required Future<void> Function(core.Transaction t) onDeleteTxn,
  required Future<void> Function(int amount, {String? description, DateTime? date})
      onAddAdjustment,
}) async {
  await showInputSheet<bool>(
    context,
    _CardReconcileSheet(
      wallet: wallet,
      initialActual: initialActual,
      ym: ym,
      onSaveActual: onSaveActual,
      onEditTxn: onEditTxn,
      onDeleteTxn: onDeleteTxn,
      onAddAdjustment: onAddAdjustment,
    ),
  );
}

class _BillingRow extends StatelessWidget {
  final ReconcileWallet wallet;
  final int planned;
  final int? actual;

  /// 行タップ → 照合シートを開く。
  final void Function(ReconcileWallet wallet) onOpenReconcile;

  const _BillingRow({
    required this.wallet,
    required this.planned,
    required this.actual,
    required this.onOpenReconcile,
  });

  @override
  Widget build(BuildContext context) {
    // 予定（明細合計）だけを表示。実際額の照合は各ウォレットの詳細画面で行う。
    return InkWell(
      onTap: () => onOpenReconcile(wallet),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: V2Spacing.md),
        child: Row(
          children: [
            BrandLogo(
              iconUrl: wallet.iconUrl,
              fallbackIcon: wallet.fallbackIcon,
              size: 22,
              borderRadius: 3,
            ),
            const SizedBox(width: V2Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wallet.name,
                      style: V2Typography.body
                          .copyWith(fontWeight: FontWeight.w700)),
                  if (wallet.subtitle != null)
                    Text(wallet.subtitle!,
                        style: V2Typography.micro
                            .copyWith(color: V2Colors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            // 合計金額（このウォレットの当月明細合計）を右側に表示。
            Text(formatYen(planned),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: planned > 0
                        ? V2Colors.textPrimary
                        : V2Colors.textMuted,
                    fontFeatures: V2Typography.tabularNums)),
            const SizedBox(width: V2Spacing.sm),
            const Icon(Icons.chevron_right,
                size: 18, color: V2Colors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// クレカ引落の棚卸しシート
// ═════════════════════════════════════════════════

/// 1枚のクレカについて「予定（明細合計）vs 実際（手入力）」の差額を棚卸しする。
/// - そのカード払いの当月明細を一覧（タップで編集／削除）
/// - 実際請求額を入力
/// - 差額ぶんを「調整取引」としてその場で追加（記録漏れ補完）
class _CardReconcileSheet extends StatefulWidget {
  final ReconcileWallet wallet;

  /// 実際額の初期値（このウォレットのその月の手入力値）。
  final int? initialActual;
  final String ym;

  /// 実際請求額を保存（null でクリア）。
  final Future<void> Function(int? amount) onSaveActual;

  /// 明細行タップ → 取引を編集。
  final Future<void> Function(core.Transaction t) onEditTxn;

  /// 明細行 → 取引を削除。
  final Future<void> Function(core.Transaction t) onDeleteTxn;

  /// 支出を追加（差額ぶん／突合の記録漏れ補完）。description/date でプリフィル。
  final Future<void> Function(int amount, {String? description, DateTime? date})
      onAddAdjustment;

  const _CardReconcileSheet({
    required this.wallet,
    required this.initialActual,
    required this.ym,
    required this.onSaveActual,
    required this.onEditTxn,
    required this.onDeleteTxn,
    required this.onAddAdjustment,
  });

  @override
  State<_CardReconcileSheet> createState() => _CardReconcileSheetState();
}

class _CardReconcileSheetState extends State<_CardReconcileSheet> {
  final _txRepo = TransactionRepository.instance;
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _all = [];

  /// このカード払いの固定費（サブスク）。予定・突合に含める。
  List<core.Subscription> _subs = [];
  int? _actual;
  bool _loading = true;

  /// 貼り付けたカード明細（突合用）。空なら突合UIは出さない。
  List<_StmtLine> _pasted = [];

  /// 荒療治（CSVで置き換え）の実行中フラグ。
  bool _replacing = false;

  /// 記録漏れ行のインライン編集状態（明細行ごと：店名・科目）。
  final Map<_StmtLine, _LineEdit> _edits = {};

  /// カテゴリ候補（現モード・休眠除く）。
  List<String> _majors = [];
  Map<String, List<String>> _catMenu = {};

  /// AIが科目を推定中。
  bool _proposing = false;

  /// このカードの明細履歴（編集・初期化）を展開しているか。既定は隠す。
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _actual = widget.initialActual;
    _load();
    _loadCats();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _all = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final e in _edits.values) {
      e.dispose();
    }
    super.dispose();
  }

  /// カテゴリ候補を読み込む（ドロップダウン＋AI推定用）。
  Future<void> _loadCats() async {
    try {
      final cfg = await SettingsRepository().loadCategories();
      final menu = <String, List<String>>{};
      final majors = <String>[];
      for (final m in cfg.majors) {
        if (m.inactive) continue;
        menu[m.name] = m.subs;
        // 大カテゴリ名の重複はドロップダウンの assert を誘発するので一意化。
        if (!majors.contains(m.name)) majors.add(m.name);
      }
      if (!mounted) return;
      setState(() {
        _catMenu = menu;
        _majors = majors;
      });
    } catch (_) {}
  }

  /// CSV/貼り付け明細をセットし、行ごとの編集状態を作って科目をAI提案する。
  void _setPasted(List<_StmtLine> lines) {
    DebugLog.add('setPasted: ${lines.length}件で開始');
    for (final e in _edits.values) {
      e.dispose();
    }
    _edits.clear();
    for (final l in lines) {
      _edits[l] = _LineEdit(name: l.name);
    }
    setState(() => _pasted = lines);
    DebugLog.add('setPasted: setState完了（突合UIを表示へ）');
    _propose();
  }

  /// 過去の確定取引から「店名（完全一致）→ 最頻の会計科目」の学習マップを作る。
  /// 店名は store と description の両方をキーにする（取込分はstore、手入力分はdescに入る）。
  Map<String, ({String major, String sub})> _buildHistoryCategoryMap() {
    final counts = <String, Map<String, int>>{};
    for (final t in _all) {
      if (t.type != core.TransactionType.expense) continue;
      final major = t.category.major.trim();
      if (major.isEmpty || major == '未分類') continue;
      final catKey = '$major${t.category.sub.trim()}';
      final names = <String>{};
      final s = t.store?.trim() ?? '';
      final d = t.description.trim();
      if (s.isNotEmpty) names.add(s);
      if (d.isNotEmpty) names.add(d);
      for (final n in names) {
        (counts[n] ??= {})[catKey] = ((counts[n]![catKey]) ?? 0) + 1;
      }
    }
    final map = <String, ({String major, String sub})>{};
    counts.forEach((name, cc) {
      final best = cc.entries.reduce((a, b) => b.value > a.value ? b : a);
      final parts = best.key.split('');
      map[name] = (major: parts[0], sub: parts.length > 1 ? parts[1] : '');
    });
    return map;
  }

  /// 記録漏れ行の科目を提案する。
  /// ① 過去の確定データ（店名完全一致）から最頻科目を採用（無料・一瞬・Web版でも効く）
  /// ② 履歴に無い店だけ AI（Gemini）に聞く（キーがある時のみ）
  Future<void> _propose() async {
    if (_pasted.isEmpty) return;
    final lines = List<_StmtLine>.from(_pasted);
    final hist = _buildHistoryCategoryMap();
    final needAi = <int>[]; // 履歴に無くAIに聞く行のindex
    setState(() {
      _proposing = true;
      for (var i = 0; i < lines.length; i++) {
        final e = _edits[lines[i]];
        if (e == null) continue;
        final name = e.nameCtrl.text.trim();
        final h = hist[name];
        if (h != null) {
          e.major = h.major;
          e.sub = h.sub;
        } else {
          needAi.add(i);
        }
      }
    });
    DebugLog.add(
        'propose: 履歴一致=${lines.length - needAi.length}件 / AI対象=${needAi.length}件');

    if (needAi.isNotEmpty &&
        _catMenu.isNotEmpty &&
        StoreCategoryClassifier.available) {
      final names = [
        for (final i in needAi) _edits[lines[i]]?.nameCtrl.text ?? lines[i].name
      ];
      List<Map<String, String>?> cats;
      try {
        cats = await StoreCategoryClassifier.instance.classify(names, _catMenu);
      } catch (_) {
        cats = List<Map<String, String>?>.filled(names.length, null);
      }
      if (!mounted) return;
      setState(() {
        for (var k = 0; k < needAi.length && k < cats.length; k++) {
          final c = cats[k];
          final e = _edits[lines[needAi[k]]];
          if (c != null && e != null) {
            e.major = c['major'];
            e.sub = c['sub'] ?? '';
          }
        }
      });
      DebugLog.add('propose: AI提案完了');
    }
    if (!mounted) return;
    setState(() => _proposing = false);
  }

  /// 同バッチ内で、同じ店名（完全一致）の他の行にも科目を反映する。
  void _applySameNameCategory(_StmtLine src, String? major, String sub) {
    final name = _edits[src]?.nameCtrl.text.trim();
    if (name == null || name.isEmpty) return;
    for (final entry in _edits.entries) {
      if (identical(entry.key, src)) continue;
      if (entry.value.nameCtrl.text.trim() == name) {
        entry.value.major = major;
        entry.value.sub = sub;
      }
    }
  }

  /// 記録漏れ1件を、編集後の店名・科目で支出として追加する。
  Future<void> _addMissing(_StmtLine line) async {
    final e = _edits[line];
    final name = (e?.nameCtrl.text ?? line.name).trim();
    if (name.isEmpty) return;
    final minDate = AppModeManager.instance.current.minDate;
    final date = line.date ?? DateTime(_year, _month);
    if (date.isBefore(minDate)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${minDate.year}年${minDate.month}月より前は登録できません')));
      return;
    }
    final tx = core.Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: date,
      type: core.TransactionType.expense,
      category: core.Category(major: e?.major ?? '未分類', sub: e?.sub ?? ''),
      paymentMethod: widget.wallet.name,
      description: name,
      amount: line.amount,
      store: name,
    );
    await _txRepo.add(tx);
    await _load();
  }

  /// チェックの付いた記録漏れだけをまとめて追加する。
  Future<void> _addAllMissing(List<_StmtLine> missing) async {
    final targets =
        missing.where((l) => _edits[l]?.included ?? true).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('チェックが付いた行がありません')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('チェックした記録漏れを追加'),
        content: Text('編集後の店名・科目で ${targets.length}件を追加します。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('追加する')),
        ],
      ),
    );
    if (ok != true) return;
    for (final l in targets) {
      await _addMissing(l);
    }
  }

  /// 記録漏れ1行のインライン編集UI（店名編集＋科目ドロップダウン＋追加）。
  Widget _missingEditRow(_StmtLine line) {
    final e = _edits.putIfAbsent(line, () => _LineEdit(name: line.name));
    return Opacity(
      opacity: e.included ? 1 : 0.4,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, V2Spacing.md, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 取り込みチェック（既定ON）。外すと一括追加の対象から外れる。
              SizedBox(
                width: 30,
                child: Checkbox(
                  value: e.included,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() => e.included = v ?? true),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                    line.date != null
                        ? '${line.date!.month}/${line.date!.day}'
                        : '—',
                    style: V2Typography.micro
                        .copyWith(color: V2Colors.textSecondary)),
              ),
              // 店名（編集可）。1文字ごとの setState は全行再描画で激重になるため
              // しない（値は controller が保持し、追加時に読む）。
              Expanded(
                child: TextField(
                  controller: e.nameCtrl,
                  style: V2Typography.body,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatYen(line.amount),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: V2Colors.negative,
                      fontFeatures: V2Typography.tabularNums)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 60),
              // 大カテゴリ（AI提案・変更可）
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _majors.contains(e.major) ? e.major : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.auto_awesome, size: 15),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 30, minHeight: 0),
                    hintText: '大カテゴリ（未分類）',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                  items: [
                    for (final m in _majors)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => setState(() {
                    e.major = v;
                    e.sub = '';
                    _applySameNameCategory(line, v, '');
                  }),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 38),
                ),
                onPressed: () => _addMissing(line),
                child: const Text('追加', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          // 小カテゴリ（大カテゴリに小カテゴリがある時だけ表示）
          if (e.major != null && (_catMenu[e.major]?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 60),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        (_catMenu[e.major]?.contains(e.sub) ?? false) &&
                                e.sub.isNotEmpty
                            ? e.sub
                            : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.subdirectory_arrow_right,
                          size: 15, color: V2Colors.textMuted),
                      prefixIconConstraints:
                          BoxConstraints(minWidth: 30, minHeight: 0),
                      hintText: '小カテゴリ（任意）',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF111827)),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('（なし）')),
                      for (final s in _catMenu[e.major]!)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() {
                      e.sub = v ?? '';
                      _applySameNameCategory(line, e.major, e.sub);
                    }),
                  ),
                ),
                // 追加ボタンと幅を合わせるためのダミー余白。
                const SizedBox(width: 8),
                const SizedBox(width: 56),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    List<core.Subscription> subs = const [];
    try {
      subs = (await SubscriptionRepository.instance.load()).subscriptions;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _all = txns;
      _subs = subs;
      _loading = false;
    });
  }

  int get _year => int.parse(widget.ym.split('-')[0]);
  int get _month => int.parse(widget.ym.split('-')[1]);

  /// 当月・当カード払いの明細（新しい順）。明細表示と予定金額に使う。
  List<core.Transaction> get _cardTxns {
    return _all
        .where((t) =>
            t.type == core.TransactionType.expense &&
            t.paymentMethod == widget.wallet.name &&
            t.date.year == _year &&
            t.date.month == _month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// このカード払いの固定費（当月・金額>0）。予定と突合に含める。
  List<({String name, int amount})> get _cardSubs {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final out = <({String name, int amount})>[];
    for (final s in _subs) {
      if ((s.paymentMethod ?? '') != widget.wallet.name) continue;
      final amt = s.plAmountForMonth(widget.ym, curYm);
      if (amt > 0) {
        out.add((name: s.name.trim().isEmpty ? '固定費' : s.name, amount: amt));
      }
    }
    return out;
  }

  /// 初期化の削除対象（当月・このカード名＋汎用クレカ表記の支出）。
  /// 昔の手入力で支払方法を「クレカ」等にしていた分も拾う。
  List<core.Transaction> get _deleteTargetsThisMonth {
    return _all
        .where((t) =>
            t.type == core.TransactionType.expense &&
            isCreditDeleteTarget(t.paymentMethod, widget.wallet.name) &&
            t.date.year == _year &&
            t.date.month == _month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  int get _planned =>
      _cardTxns.fold(0, (s, t) => s + t.amount) +
      _cardSubs.fold(0, (s, x) => s + x.amount);

  /// 実際請求額を入力。
  Future<void> _inputActual() async {
    final ctrl = NoComposingUnderlineController(
        text: _actual != null && _actual! > 0 ? formatAmount(_actual!) : '');
    int? result;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.wallet.isCard
            ? '${widget.wallet.name}の実際請求額'
            : '${widget.wallet.name}の実際に使った額'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('予定（記録合計）: ${formatYen(_planned)}',
                style: const TextStyle(
                    fontSize: 12, color: V2Colors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [
                HalfWidthDigitsFormatter(),
                ThousandsSeparatorInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: widget.wallet.isCard
                    ? 'カード会社通知の請求額（円）'
                    : '実際に使った額（円）',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () {
                result = -1; // クリア
                Navigator.pop(context);
              },
              child: const Text('クリア')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                result = parseAmount(ctrl.text) ?? 0;
                Navigator.pop(context);
              },
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    final amount = result! <= 0 ? null : result;
    await widget.onSaveActual(amount);
    if (mounted) setState(() => _actual = amount);
  }

  /// カード明細をコピペ → 解析して突合用にセット。
  Future<void> _pasteStatement() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('カード明細を貼り付け'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  '【確実な方法】CSVファイルを開いて全選択(Ctrl+A)→コピー(Ctrl+C)→'
                  'ここに貼り付け(Ctrl+V)してください。CSVの中身そのままでOKです。\n'
                  '（カード会社サイトの明細をコピペしてもOK。1行＝1明細）',
                  style:
                      TextStyle(fontSize: 11, color: V2Colors.textSecondary)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 12,
                minLines: 6,
                decoration: const InputDecoration(
                  hintText: 'CSVの中身をそのまま貼り付け、または\n'
                      '2026/06/15  Amazon.co.jp  3,980 …',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('突合する')),
        ],
      ),
    );
    if (ok != true) return;
    DebugLog.add('貼り付け: 突合ボタン押下 文字数=${ctrl.text.length}');
    // まずCSV(カンマ区切り)として解析。だめなら自由文として金額拾い。
    var lines = _parseCardCsv(ctrl.text, _year);
    DebugLog.add('貼り付け: CSV解析=${lines.length}件');
    if (lines.isEmpty) {
      lines = _parseStatement(ctrl.text, _year);
      DebugLog.add('貼り付け: 自由文解析=${lines.length}件');
    }
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('金額を読み取れる明細が見つかりませんでした')));
      return;
    }
    _setPasted(lines);
  }

  /// カード明細CSVを選択 → Shift-JIS/UTF-8 を判定して解析 → 突合用にセット。
  Future<void> _importCsv() async {
    DebugLog.add('CSV読込: pickCsvFile()を呼び出し');
    final picked = await pickCsvFile();
    if (!mounted) return;
    if (picked == null) {
      DebugLog.add('CSV読込: picker結果=null（選択キャンセル/取得失敗）');
      return; // キャンセル or 取得失敗
    }
    final bytes = picked.bytes;
    DebugLog.add('CSV読込: ファイル取得 name=${picked.name} bytes=${bytes.length}');
    final content = _decodeCsvBytes(bytes);
    DebugLog.add('CSV読込: デコード完了 chars=${content.length}');
    final lines = _parseCardCsv(content, _year);
    DebugLog.add('CSV読込: 解析完了 ${lines.length}件');
    if (!mounted) return;
    if (lines.isEmpty) {
      // 何が読めなかったか分かるよう、デコード結果の先頭を見せる固定ダイアログ。
      final preview = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(4)
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('CSVを読み取れませんでした'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${picked.name}（${bytes.length}バイト）',
                    style: const TextStyle(
                        fontSize: 12, color: V2Colors.textSecondary)),
                const SizedBox(height: 8),
                const Text('読み取った先頭行（文字化けしていたらエンコーディングの問題です）:',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: const Color(0xFFF1F5F9),
                  child: Text(preview.isEmpty ? '(空)' : preview,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる')),
          ],
        ),
      );
      return;
    }
    _setPasted(lines);
  }

  /// CSV期間ラベル（"5/1〜5/31" など。日付不明なら "全期間"）。
  String _rangeLabel(DateTime? lo, DateTime? hi) {
    if (lo == null || hi == null) return '全期間';
    return '${lo.month}/${lo.day}〜${hi.month}/${hi.day}';
  }

  /// 【荒療治】CSV明細を「正」として取り込むプレビュー画面へ遷移する。
  /// プレビューで店名の編集・AIによる科目提案・下書き保存を行い、確定で
  /// CSV期間内の既存カード取引を削除→編集後の内容で一括記帳する。
  Future<void> _openCsvImport() async {
    final lines = [
      for (final l in _pasted) CardCsvLine(l.date, l.name, l.amount),
    ];
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CardCsvImportScreen(
          cardName: widget.wallet.name,
          ym: widget.ym,
          lines: lines,
        ),
      ),
    );
    if (done == true && mounted) {
      for (final e in _edits.values) {
        e.dispose();
      }
      _edits.clear();
      setState(() => _pasted = []);
      await _load();
    }
  }

  /// 【荒療治・CSV不要】この月・このカードの取引をまとめて初期化（削除）する。
  /// 「全部消してから明細を正として入れ直す」運用の最初の一歩。実行前に自動バックアップ。
  Future<void> _initializeMonth(List<core.Transaction> txns) async {
    if (txns.isEmpty) return;
    // 支払方法ごとの内訳（何が消えるかを明示）。
    final byMethod = <String, int>{};
    for (final t in txns) {
      byMethod[t.paymentMethod] = (byMethod[t.paymentMethod] ?? 0) + 1;
    }
    final breakdown = (byMethod.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '・${e.key}：${e.value}件')
        .join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$_month月のクレカ取引を初期化しますか？'),
        content: Text(
            '$_year年$_month月の次の取引 計${txns.length}件を削除します'
            '（このカード名＋昔の手入力「クレカ」等を含む）:\n\n'
            '$breakdown\n\n'
            'この操作は元に戻せません。実行直前に自動バックアップを取ります。\n'
            '削除後、正しい明細をCSV取り込みや手入力で入れ直してください。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: Text('${txns.length}件を削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _replacing = true);
    try {
      try {
        await BackupRepository.instance
            .savePreImportSnapshot(reason: 'pre-card-init');
      } catch (_) {}
      var deleted = 0;
      for (final t in txns) {
        try {
          await _txRepo.delete(t.id);
          deleted++;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _replacing = false);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('初期化完了：$deleted件を削除しました')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _replacing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('初期化に失敗しました: $e')));
    }
  }

  /// 明細コピペ／CSV → 突合UI（ボタン＋結果）。
  Widget _statementSection() {
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _importCsv,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(_pasted.isEmpty ? 'CSVを読み込んで突合' : 'CSVを読み込み直す'),
            ),
          ),
          const SizedBox(width: V2Spacing.sm),
          OutlinedButton.icon(
            onPressed: _pasteStatement,
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('貼り付け'),
          ),
        ],
      ),
    ];

    if (_pasted.isNotEmpty) {
      DebugLog.add('突合UI: 構築開始（_pasted=${_pasted.length}件）');
      // 突合対象 = このカード払いの取引のうち「貼り付け明細がカバーする期間」のもの。
      // （請求月と利用月はズレるため、表示中の月では絞らない。明細の日付範囲±2日で照合）
      DateTime? minD, maxD;
      for (final l in _pasted) {
        if (l.date == null) continue;
        if (minD == null || l.date!.isBefore(minD)) minD = l.date;
        if (maxD == null || l.date!.isAfter(maxD)) maxD = l.date;
      }
      final lo = minD?.subtract(const Duration(days: 2));
      final hi = maxD?.add(const Duration(days: 2));
      final pool = _all.where((t) {
        if (t.type != core.TransactionType.expense) return false;
        if (t.paymentMethod != widget.wallet.name) return false;
        if (lo != null && t.date.isBefore(lo)) return false;
        if (hi != null && t.date.isAfter(hi)) return false;
        return true;
      }).toList();

      // 金額で突合（記録1件は1回まで）。
      final used = <int>{};
      // このカード払いの固定費（サブスク）の金額。CSVに同額があれば「記録済み」
      // として吸収し、二重計上（記録漏れ誤検出）を防ぐ。
      final subAmounts = _cardSubs.map((x) => x.amount).toList();
      final subUsed = <int>{};
      final missing = <_StmtLine>[]; // 明細にあり・記録なし＝記録漏れ
      int matchedCount = 0;
      for (final line in _pasted) {
        int found = -1;
        for (int i = 0; i < pool.length; i++) {
          if (used.contains(i)) continue;
          if (pool[i].amount == line.amount) {
            found = i;
            break;
          }
        }
        if (found >= 0) {
          used.add(found);
          matchedCount++;
          continue;
        }
        // 取引で一致しなければ、このカードの固定費（サブスク）と金額照合。
        int subFound = -1;
        for (int i = 0; i < subAmounts.length; i++) {
          if (subUsed.contains(i)) continue;
          if (subAmounts[i] == line.amount) {
            subFound = i;
            break;
          }
        }
        if (subFound >= 0) {
          subUsed.add(subFound);
          matchedCount++;
        } else {
          missing.add(line);
        }
      }
      final extra = <core.Transaction>[]; // 記録あり・明細なし＝要確認
      for (int i = 0; i < pool.length; i++) {
        if (!used.contains(i)) extra.add(pool[i]);
      }
      final pastedTotal = _pasted.fold<int>(0, (s, l) => s + l.amount);
      final missingTotal = missing.fold<int>(0, (s, l) => s + l.amount);

      children.add(const SizedBox(height: V2Spacing.md));
      // サマリー
      children.add(Container(
        padding: const EdgeInsets.all(V2Spacing.md),
        decoration: BoxDecoration(
          color: V2Colors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: V2Colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('貼り付け ${_pasted.length}件 / ${formatYen(pastedTotal)}',
                style: V2Typography.caption
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _chip('一致 $matchedCount件', V2Colors.positive),
              _chip('記録漏れ ${missing.length}件', V2Colors.negative),
              _chip('要確認 ${extra.length}件', V2Colors.warning),
            ]),
          ],
        ),
      ));

      // ── 荒療治: この明細でカード取引を丸ごと置き換える（カードのみ） ──
      // 棚卸しのコストが高すぎる時の最終手段。CSV期間の既存カード取引を削除し、
      // CSVの各行を新規取引として取り込む（科目は店名からAI推定）。
      if (widget.wallet.isCard) {
        children.add(const SizedBox(height: V2Spacing.sm));
        children.add(Container(
          padding: const EdgeInsets.all(V2Spacing.sm),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFDBA74)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('荒療治：この明細を正として置き換える',
                  style: V2Typography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9A3412))),
              const SizedBox(height: 2),
              Text(
                  'CSVの期間内（${_rangeLabel(lo, hi)}）の「${widget.wallet.name}」既存取引を削除し、'
                  'CSV ${_pasted.length}件を新規取り込み（科目は店名からAI推定）。実行前に自動バックアップ。',
                  style: V2Typography.caption
                      .copyWith(color: const Color(0xFF9A3412), fontSize: 11)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openCsvImport(),
                  icon: const Icon(Icons.sync_problem, size: 18),
                  label: Text(
                      'CSVで置き換える（プレビュー・既存${pool.length}件を削除）'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C)),
                ),
              ),
            ],
          ),
        ));
      }

      // 記録漏れ（明細にあるが記録に無い）→ その場で店名・科目を直して追加
      if (missing.isNotEmpty) {
        children.add(const SizedBox(height: V2Spacing.sm));
        children.add(Row(children: [
          const Icon(Icons.error_outline,
              size: 16, color: V2Colors.negative),
          const SizedBox(width: 6),
          Expanded(
            child: Text('記録漏れ（明細にあるが未記録）合計 ${formatYen(missingTotal)}',
                style: V2Typography.caption.copyWith(
                    color: V2Colors.negative, fontWeight: FontWeight.w700)),
          ),
          if (_proposing)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _propose,
              icon: const Icon(Icons.auto_awesome, size: 15),
              label: const Text('AIで科目提案', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
        ]));
        children.add(Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 4),
          child: Text('チェックを入れた行だけ取り込みます。店名・科目を直して「追加」。過去の確定データ＋AIが科目を提案（同じ店名は連動）。',
              style: V2Typography.micro.copyWith(color: V2Colors.textMuted)),
        ));
        // 全選択/全解除
        final checkedNow =
            missing.where((l) => _edits[l]?.included ?? true).length;
        children.add(Padding(
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: Row(
            children: [
              Text('取り込み対象 $checkedNow / ${missing.length}',
                  style: V2Typography.micro
                      .copyWith(color: V2Colors.textSecondary)),
              const Spacer(),
              TextButton(
                  onPressed: () => setState(() {
                        for (final l in missing) {
                          _edits[l]?.included = true;
                        }
                      }),
                  child: const Text('全選択', style: TextStyle(fontSize: 11))),
              TextButton(
                  onPressed: () => setState(() {
                        for (final l in missing) {
                          _edits[l]?.included = false;
                        }
                      }),
                  child: const Text('全解除', style: TextStyle(fontSize: 11))),
            ],
          ),
        ));
        children.add(const SizedBox(height: 6));
        children.add(Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < missing.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: V2Colors.divider),
                _missingEditRow(missing[i]),
              ],
            ],
          ),
        ));
        // 記録漏れをまとめて追加
        children.add(const SizedBox(height: 8));
        children.add(SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _addAllMissing(missing),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: Text('チェックした $checkedNow件を追加'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
          ),
        ));
      }

      // 要確認（記録にあるが明細に無い）→ 二重計上等の確認
      if (extra.isNotEmpty) {
        children.add(const SizedBox(height: V2Spacing.sm));
        children.add(Row(children: [
          const Icon(Icons.help_outline, size: 16, color: V2Colors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text('要確認（記録にあるが明細に無い）',
                style: V2Typography.caption.copyWith(
                    color: const Color(0xFF92400E),
                    fontWeight: FontWeight.w700)),
          ),
        ]));
        children.add(const SizedBox(height: 6));
        children.add(Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFCD34D)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < extra.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: V2Colors.divider),
                _ReconcileTxnRow(
                  txn: extra[i],
                  onEdit: () => widget.onEditTxn(extra[i]),
                  onDelete: () => widget.onDeleteTxn(extra[i]),
                ),
              ],
            ],
          ),
        ));
      }
      DebugLog.add('突合UI: 構築完了（記録漏れ${missing.length}件/一致$matchedCount件）');
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final txns = _cardTxns;
    final delTargets = _deleteTargetsThisMonth;
    final planned = _planned;
    final actual = _actual;
    final diff = actual != null ? actual - planned : null;

    Color diffColor;
    String diffLabel;
    if (diff == null) {
      diffColor = V2Colors.textMuted;
      diffLabel = '実際額 未入力';
    } else if (diff == 0) {
      diffColor = V2Colors.positive;
      diffLabel = '一致';
    } else if (diff > 0) {
      diffColor = V2Colors.negative;
      diffLabel = '+${formatYen(diff)}';
    } else {
      diffColor = V2Colors.warning;
      diffLabel = formatYen(diff);
    }

    return Scaffold(
      backgroundColor: V2Colors.surface,
      appBar: AppBar(
        backgroundColor: V2Colors.surface,
        elevation: 0,
        title: Text(
            widget.wallet.isCard ? 'クレカ棚卸し（$_month月）' : '棚卸し（$_month月）',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(V2Spacing.lg),
              children: [
                Row(
                  children: [
                    BrandLogo(
                      iconUrl: widget.wallet.iconUrl,
                      fallbackIcon: widget.wallet.fallbackIcon,
                      size: 24,
                      borderRadius: 4,
                    ),
                    const SizedBox(width: V2Spacing.sm),
                    Expanded(
                        child:
                            Text(widget.wallet.name, style: V2Typography.h2)),
                  ],
                ),
                const SizedBox(height: V2Spacing.md),
                _SummaryBox(
                  planned: planned,
                  actual: actual,
                  diff: diff,
                  diffColor: diffColor,
                  diffLabel: diffLabel,
                  onInputActual: _inputActual,
                  isCard: widget.wallet.isCard,
                ),
                const SizedBox(height: V2Spacing.lg),
                if (diff != null && diff > 0)
                  _AdjustmentPrompt(
                    amount: diff,
                    onAdd: () => widget.onAddAdjustment(diff),
                  )
                else if (diff != null && diff < 0)
                  Container(
                    padding: const EdgeInsets.all(V2Spacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: V2Colors.warning, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 20, color: V2Colors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.wallet.isCard ? '明細合計' : '記録合計'}が実際より ${formatYen(-diff)} 多いです。'
                            '二重計上や取消済みの可能性があります。'
                            '下の履歴から余分な記録を削除・修正してください。',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (diff == 0)
                  Container(
                    padding: const EdgeInsets.all(V2Spacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: V2Colors.positive, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 20, color: V2Colors.positive),
                        const SizedBox(width: 8),
                        Text(
                            '${widget.wallet.isCard ? '明細合計と実際請求' : '記録合計と実際'}が一致しています。',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: V2Colors.positive)),
                      ],
                    ),
                  ),
                const SizedBox(height: V2Spacing.lg),
                // 明細コピペ → 突合（記録漏れを炙り出す）
                Text('明細コピペで突合', style: V2Typography.h2),
                const SizedBox(height: V2Spacing.sm),
                _statementSection(),
                const SizedBox(height: V2Spacing.lg),
                // 履歴（既存明細の確認・編集・初期化）は既定で隠し、ボタンで開く。
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showHistory = !_showHistory),
                  icon: Icon(
                      _showHistory ? Icons.expand_less : Icons.history,
                      size: 18),
                  label: Text(_showHistory
                      ? '履歴を閉じる'
                      : '履歴を編集する（${txns.length}件）'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: V2Colors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
                if (_showHistory) ...[
                const SizedBox(height: V2Spacing.sm),
                Row(
                  children: [
                    Text('このカードの$_month月明細', style: V2Typography.h2),
                    const Spacer(),
                    Text('${txns.length}件 / ${formatYen(planned)}',
                        style: V2Typography.caption
                            .copyWith(color: V2Colors.textSecondary)),
                  ],
                ),
                // 荒療治：この月のクレカ取引（このカード名＋汎用クレカ表記）を初期化。
                // CSV無しでも使える独立ボタン。カードのみ・対象があるときだけ表示。
                if (widget.wallet.isCard && delTargets.isNotEmpty) ...[
                  const SizedBox(height: V2Spacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _replacing ? null : () => _initializeMonth(delTargets),
                      icon: _replacing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(_replacing
                          ? '初期化中…'
                          : '$_month月のクレカ取引を初期化（${delTargets.length}件を削除）'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: V2Spacing.sm),
                if (txns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('明細なし',
                          style: V2Typography.caption
                              .copyWith(color: V2Colors.textMuted)),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: V2Colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: V2Colors.border),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < txns.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1, color: V2Colors.divider),
                          _ReconcileTxnRow(
                            txn: txns[i],
                            onEdit: () => widget.onEditTxn(txns[i]),
                            onDelete: () => widget.onDeleteTxn(txns[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                // このカード払いの固定費（サブスク）。予定に含めているので明示。
                if (_cardSubs.isNotEmpty) ...[
                  const SizedBox(height: V2Spacing.md),
                  Row(children: [
                    const Icon(Icons.repeat,
                        size: 15, color: V2Colors.textSecondary),
                    const SizedBox(width: 6),
                    Text('このカード払いの固定費（予定に含む）',
                        style: V2Typography.caption
                            .copyWith(color: V2Colors.textSecondary)),
                  ]),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: V2Colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: V2Colors.border),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < _cardSubs.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1, color: V2Colors.divider),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: V2Spacing.md, vertical: 10),
                            child: Row(
                              children: [
                                const Icon(Icons.subscriptions_outlined,
                                    size: 16, color: V2Colors.textMuted),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_cardSubs[i].name,
                                      style: V2Typography.body,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Text('-${formatYen(_cardSubs[i].amount)}',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: V2Colors.negative,
                                        fontFeatures:
                                            V2Typography.tabularNums)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                ], // _showHistory
                const SizedBox(height: V2Spacing.xl),
              ],
            ),
    );
  }
}

/// 予定 / 実際 / 差額のサマリーボックス。
class _SummaryBox extends StatelessWidget {
  final int planned;
  final int? actual;
  final int? diff;
  final Color diffColor;
  final String diffLabel;
  final VoidCallback onInputActual;
  final bool isCard;

  const _SummaryBox({
    required this.planned,
    required this.actual,
    required this.diff,
    required this.diffColor,
    required this.diffLabel,
    required this.onInputActual,
    required this.isCard,
  });

  @override
  Widget build(BuildContext context) {
    final hasActual = actual != null && actual! > 0;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isCard ? '予定（明細合計）' : '予定（記録合計）',
                          style: V2Typography.micro
                              .copyWith(color: V2Colors.textMuted)),
                      const SizedBox(height: 4),
                      Text(formatYen(planned),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: planned > 0
                                  ? V2Colors.textPrimary
                                  : V2Colors.textMuted,
                              fontFeatures: V2Typography.tabularNums)),
                    ],
                  ),
                ),
                const VerticalDivider(width: V2Spacing.lg),
                Expanded(
                  child: GestureDetector(
                    onTap: onInputActual,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(isCard ? '実際（カード通知）' : '実際',
                              style: V2Typography.micro
                                  .copyWith(color: V2Colors.textMuted)),
                          const SizedBox(width: 3),
                          const Icon(Icons.edit,
                              size: 12, color: V2Colors.textMuted),
                        ]),
                        const SizedBox(height: 4),
                        Text(hasActual ? formatYen(actual!) : '入力する',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: hasActual
                                    ? const Color(0xFFDC2626)
                                    : V2Colors.textMuted,
                                fontFeatures: V2Typography.tabularNums)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.md),
          const Divider(height: 1, color: V2Colors.divider),
          const SizedBox(height: V2Spacing.md),
          Row(
            children: [
              Text('差額',
                  style: V2Typography.body
                      .copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: diffColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: diffColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(diffLabel,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: diffColor,
                        fontFeatures: V2Typography.tabularNums)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 差額ぶんを調整取引で埋めるプロンプト。
class _AdjustmentPrompt extends StatelessWidget {
  final int amount;
  final VoidCallback onAdd;

  const _AdjustmentPrompt({required this.amount, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDC2626), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded,
                  size: 20, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '実際が予定より ${formatYen(amount)} 多いです。'
                  '記録漏れの支出がある可能性があります。',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text('差額 ${formatYen(amount)} を支出として記録'),
          ),
        ],
      ),
    );
  }
}

/// 棚卸しシート内の明細行（タップで編集 / ゴミ箱で削除）。
class _ReconcileTxnRow extends StatelessWidget {
  final core.Transaction txn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReconcileTxnRow({
    required this.txn,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cat = txn.category.sub.isNotEmpty
        ? '${txn.category.major} ＞ ${txn.category.sub}'
        : txn.category.major;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.md, vertical: V2Spacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text('${txn.date.month}/${txn.date.day}',
                  style: V2Typography.micro
                      .copyWith(color: V2Colors.textSecondary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      txn.description.isEmpty
                          ? txn.category.major
                          : txn.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(cat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            Text('-${formatYen(txn.amount)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: V2Colors.negative,
                    fontFeatures: V2Typography.tabularNums)),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: V2Colors.textMuted,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 明細コピペの解析・突合
// ═════════════════════════════════════════════════

/// 貼り付けたカード明細の1行（日付・店名・金額）。
class _StmtLine {
  final DateTime? date;
  final String name;
  final int amount;
  const _StmtLine(this.date, this.name, this.amount);
}

/// 記録漏れ行のインライン編集状態（編集後の店名・会計科目・取り込みチェック）。
class _LineEdit {
  final TextEditingController nameCtrl;
  String? major;
  String sub = '';
  bool included = true; // 取り込み対象（既定ON）
  _LineEdit({required String name})
      : nameCtrl = TextEditingController(text: name);
  void dispose() => nameCtrl.dispose();
}

/// カード明細テキストを行ごとに解析する。
/// 各行から金額（末尾の数字／¥付き）と日付・店名を推定。金額が取れない行は無視。
List<_StmtLine> _parseStatement(String text, int year) {
  // 末尾の金額（¥/\/￥ や 円 を許容、3桁区切りカンマ可）。
  final amountRe = RegExp(r'[¥\\￥]?\s*([0-9][0-9,]*)\s*円?\s*$');
  // 日付（YYYY/MM/DD / MM/DD / YYYY年MM月DD日 等）。
  final dateRe =
      RegExp(r'(\d{1,4})\s*[/\-.年]\s*(\d{1,2})(?:\s*[/\-.月]\s*(\d{1,2}))?');
  // 合計・残高など明細でない行を除外。
  final skipRe = RegExp(
      r'(合計|小計|お支払|支払金額|請求(額|金額)|ご利用可能|利用可能|繰越|残高|キャッシング|手数料合計|お引き落とし|前回|今回)');

  final out = <_StmtLine>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (skipRe.hasMatch(line)) continue;
    final am = amountRe.firstMatch(line);
    if (am == null) continue;
    final amt = int.tryParse(am.group(1)!.replaceAll(',', '')) ?? 0;
    if (amt <= 0) continue;

    DateTime? date;
    final dm = dateRe.firstMatch(line);
    if (dm != null) {
      final g1 = int.parse(dm.group(1)!);
      final g2 = int.parse(dm.group(2)!);
      if (dm.group(3) != null) {
        // YYYY/MM/DD（2桁年は2000年代へ）
        final y = g1 < 100 ? 2000 + g1 : g1;
        date = DateTime(y, g2, int.parse(dm.group(3)!));
      } else {
        // MM/DD（年は明細の対象年）
        date = DateTime(year, g1, g2);
      }
    }

    var name = line;
    if (dm != null) name = name.replaceFirst(dm.group(0)!, ' ');
    name = name.replaceFirst(am.group(0)!, ' ').trim();
    // 余分な区切り文字を整理
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    out.add(_StmtLine(date, name.isEmpty ? '明細' : name, amt));
  }
  return out;
}

// ── カード明細CSVの解析 ──

/// 金額セルか判定し、正なら金額を返す。「¥ / \ / ￥ ＋ 数字(カンマ可)」のセルだけを
/// 金額とみなす。これで「2026年6月」のような期間列を金額と誤検出しない。
int? _yenAmount(String cell) {
  final c = cell.trim();
  if (c.isEmpty) return null;
  final f = c[0];
  if (f != '\\' && f != '¥' && f != '￥') return null;
  final rest = c.substring(1).replaceAll(',', '');
  if (rest.isEmpty || !RegExp(r'^\d+$').hasMatch(rest)) return null;
  final v = int.tryParse(rest);
  return (v != null && v > 0) ? v : null;
}

/// カード明細CSVを解析して明細行リストにする。
///
/// **ヘッダー行に依存しない**（Shift-JISデコーダが前文/ヘッダーを落としても拾えるよう、
/// 「1列目が日付の行」を明細とみなす）。
/// 対応様式: ① Orico「ご利用明細」(日付列＋「¥/\付き金額」列) ② 三井住友等(日付/店名/金額)
List<_StmtLine> _parseCardCsv(String content, int year) {
  final rows =
      const LineSplitter().convert(content).map(_splitCsvLine).toList();

  // ── 主方式: 1列目が日付の行を拾い、金額は「¥/\/￥付きの最初の正値」を採用 ──
  // （前文・ヘッダー行は日付にならないので自然に除外される）
  final out = <_StmtLine>[];
  for (final c in rows) {
    if (c.isEmpty) continue;
    final date = _parseAnyDate(c[0], year);
    if (date == null) continue;
    int amt = 0;
    for (int j = 1; j < c.length; j++) {
      final v = _yenAmount(c[j]);
      if (v != null) {
        amt = v;
        break;
      }
    }
    if (amt <= 0) continue;
    final name = c.length > 1 ? c[1].trim() : '';
    out.add(_StmtLine(date, name.isEmpty ? '明細' : name, amt));
  }
  if (out.isNotEmpty) return out;

  // ── フォールバック: 1列目=日付 / 2列目=店名 / 3列目=金額（¥記号なしの様式） ──
  final out2 = <_StmtLine>[];
  for (final c in rows) {
    if (c.length < 3) continue;
    final date = _parseAnyDate(c[0], year);
    if (date == null) continue;
    final amt = _yen(c[2]);
    if (amt <= 0) continue;
    final name = c[1].trim();
    out2.add(_StmtLine(date, name.isEmpty ? '明細' : name, amt));
  }
  return out2;
}

/// CSVバイト列を文字列にデコードする。
/// UTF-8 として「文字化け（U+FFFD）なく」読めればそれを採用。読めなければ
/// Shift-JIS（カード明細の大半）→ 最後の保険で Latin-1 の順で試す。
String _decodeCsvBytes(List<int> bytes) {
  // UTF-8（厳密）。例外なく＆置換文字を含まなければ採用。
  try {
    final u = utf8.decode(bytes);
    if (!u.contains('�')) return u;
  } catch (_) {}
  // Shift-JIS（cp932相当）。日本のカード明細はほぼこれ。
  try {
    final s = shiftJis.decode(bytes);
    if (s.trim().isNotEmpty) return s;
  } catch (_) {}
  return latin1.decode(bytes, allowInvalid: true);
}

/// CSVの1行をダブルクオート対応で分割。
List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQ = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQ && i + 1 < line.length && line[i + 1] == '"') {
        sb.write('"');
        i++;
      } else {
        inQ = !inQ;
      }
    } else if (ch == ',' && !inQ) {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out;
}

/// 金額セルから数字だけ抜いて整数化（¥ \ ￥ , 円 " 等を除去）。
int _yen(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// 日付セルを解析（yyyy/mm/dd・yyyy-mm-dd・yyyy年m月d日・mm/dd）。
DateTime? _parseAnyDate(String s, int year) {
  final t = s.trim();
  var m = RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{1,2})[/\-](\d{1,2})$').firstMatch(t);
  if (m != null) {
    return DateTime(year, int.parse(m[1]!), int.parse(m[2]!));
  }
  return null;
}
