import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_mode.dart';
import '../data/backup_repository.dart';
import '../data/checklist_repository.dart';
import '../data/month_closing_repository.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../screens/pending_settlement_screen.dart';
import '../utils/formatters.dart';

/// 集計タブの「月末締め」ビュー。
/// - 月選択 (prev/next)
/// - チェックリスト表示と進捗
/// - 月の収支サマリ
/// - 全チェック後に「締め」ボタン → 確認ダイアログ → 締め記録
/// - 既に締めた月は ✓表示 + 再編集（締め解除）可
class MonthClosingView extends StatefulWidget {
  const MonthClosingView({super.key});

  @override
  State<MonthClosingView> createState() => _MonthClosingViewState();
}

class _MonthClosingViewState extends State<MonthClosingView>
    with ModeAwareMixin {
  @override
  void onModeChanged() => _load();

  final _txRepo = TransactionRepository.instance;
  final _checklistRepo = ChecklistRepository.instance;
  final _closingRepo = MonthClosingRepository.instance;
  final _settingsRepo = SettingsRepository();
  StreamSubscription<List<Transaction>>? _sub;

  List<Transaction> _transactions = [];
  ChecklistConfig _checklist = ChecklistConfig.empty();
  MonthClosingConfig _closings = MonthClosingConfig.empty();
  PaymentMethodsConfig _payments = PaymentMethodsConfig.empty();
  DateTime _focused = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await _txRepo.loadAll();
    final checklist = await _checklistRepo.load();
    final closings = await _closingRepo.load();
    final payments = await _settingsRepo.loadPayments();
    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _checklist = checklist;
      _closings = closings;
      _payments = payments;
      _loading = false;
    });
  }

  /// linkType に基づいて、登録済みの口座/カードから子要素を動的生成する。
  /// 静的 children を上書きする形で利用される。
  List<ChecklistItem> _resolveLinkedChildren(String linkType) {
    switch (linkType) {
      case 'bank_accounts':
        return _payments.bankAccounts
            .map((b) => ChecklistItem(
                  id: 'bank-${b.id}',
                  name: b.name,
                  url: b.iconUrl, // ロゴ取得など参照用（任意）
                  memo: b.memo,
                ))
            .toList();
      case 'credit_cards':
        return _payments.creditCards
            .map((c) => ChecklistItem(
                  id: 'card-${c.id}',
                  name: c.name,
                  url: c.iconUrl,
                  memo: c.memo,
                ))
            .toList();
    }
    return const [];
  }

  /// 表示用に「動的展開後」の項目リストを返す。
  /// linkType 付きの項目は children が動的差し替えされる。
  List<ChecklistItem> get _effectiveItems {
    return _checklist.items.map((item) {
      if (!item.isLinked) return item;
      final dynamicChildren = _resolveLinkedChildren(item.linkType!);
      return item.copyWith(children: dynamicChildren);
    }).toList();
  }

  /// 動的展開後の leaf ID 一覧（進捗計算用）。
  List<String> get _effectiveLeafIds {
    final ids = <String>[];
    for (final item in _effectiveItems) {
      if (item.hasChildren) {
        for (final c in item.children) {
          ids.add(c.id);
        }
      } else {
        ids.add(item.id);
      }
    }
    return ids;
  }

  void _prevMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month - 1));
  }

  void _nextMonth() {
    setState(() => _focused = DateTime(_focused.year, _focused.month + 1));
  }

  /// 現在月の closing オブジェクト（未存在ならデフォルト空）。
  MonthClosing get _currentClosing {
    final existing =
        _closings.forMonth(_focused.year, _focused.month);
    return existing ??
        MonthClosing(
            yearMonth:
                MonthClosing.monthKey(_focused.year, _focused.month));
  }

  List<Transaction> get _monthTxns => _transactions
      .where((t) =>
          t.date.year == _focused.year && t.date.month == _focused.month)
      .toList();

  Future<void> _toggleCheck(String itemId) async {
    final c = _currentClosing;
    if (c.isClosed) return; // 締め後は編集不可（再編集ボタンで解除）
    final list = [...c.checkedItemIds];
    if (list.contains(itemId)) {
      list.remove(itemId);
    } else {
      list.add(itemId);
    }
    final updated = c.copyWith(checkedItemIds: list);
    await _closingRepo.upsert(updated);
    final cfg = await _closingRepo.load();
    if (!mounted) return;
    setState(() => _closings = cfg);
  }

  Future<void> _close() async {
    final monthTxns = _monthTxns;
    final income = monthTxns
        .where((t) => t.type == TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFF1A237E)),
            const SizedBox(width: 8),
            Text('${_focused.year}年${_focused.month}月を締めますか？'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('全チェック項目を確認しました。締めると当月の収支が確定します。',
                style:
                    TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            _summaryRow('収入', formatYen(income, withSign: true),
                const Color(0xFF16A34A)),
            _summaryRow('支出', formatYen(-expense, withSign: true),
                const Color(0xFFDC2626)),
            _summaryRow('差引', formatYen(income - expense, withSign: true),
                income - expense >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                bold: true),
            const SizedBox(height: 8),
            const Text('※ 後から「再編集」で締めを解除できます',
                style:
                    TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('締める')),
        ],
      ),
    );
    if (ok != true) return;

    final closing = _currentClosing.copyWith(
      closedAt: DateTime.now(),
      closedTotalExpense: expense,
      closedTotalIncome: income,
    );
    await _closingRepo.upsert(closing);
    final cfg = await _closingRepo.load();
    if (!mounted) return;
    setState(() => _closings = cfg);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('月末締めを記録しました')),
    );

    // ★ 締め完了直後にバックアップ取得を提案（データ保護フェーズ2）
    // 月1回の運用フローと自然に統合され、確定データが消失するリスクを抑える。
    await _proposeBackupAfterClose();
  }

  /// 月末締め完了後の「バックアップ取得しますか？」提案ダイアログ。
  /// 「もう尋ねないで」を選んだら以降スキップ（モード別に記憶）。
  Future<void> _proposeBackupAfterClose() async {
    final prefs = await SharedPreferences.getInstance();
    final modePrefix = AppModeManager.instance.current.keyPrefix;
    final skipKey = 'futa.$modePrefix.skip_backup_proposal_after_close';
    if (prefs.getBool(skipKey) == true) return;
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cloud_upload, color: Color(0xFF16A34A)),
            const SizedBox(width: 8),
            const Text('月末締め完了'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('念のためバックアップを取りますか？',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(
              '締めた月の確定データを Google Drive などに保存しておくと、'
              '万一の事故からも復元できます（月1回の習慣化推奨）',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip_forever'),
            child: const Text('もう尋ねない'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, 'later'),
              child: const Text('後で')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'export'),
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('書き出す'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );

    if (action == 'skip_forever') {
      await prefs.setBool(skipKey, true);
    } else if (action == 'export') {
      await _exportBackupForClose();
    }
  }

  /// 月末締め後のバックアップ書き出し。settings_screen と同じく
  /// 一時ファイルに JSON 書き出し → 共有シートで Drive 等に送信。
  Future<void> _exportBackupForClose() async {
    try {
      final json = await BackupRepository.instance.exportAll();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final monthLabel =
          '${_focused.year}-${_focused.month.toString().padLeft(2, '0')}';
      final fileName =
          'futa-finance-close-$monthLabel-$stamp.json';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(json);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'FutaFinance $monthLabel 締めバックアップ',
          text: '$monthLabel の月末締めデータです。\n'
              '保存先推奨: マイドライブ/ツール開発/FutaFinance/backups/',
        ),
      );
      // 月末締めエクスポートも「手動バックアップ実施」扱いにして
      // 14日リマインダーをリセットする。
      await BackupRepository.instance.markManualBackupDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('書き出しに失敗しました: $e')),
      );
    }
  }

  Future<void> _reopen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('締めを解除して再編集'),
        content: const Text('再編集すると締め日時がリセットされます。よろしいですか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('解除する')),
        ],
      ),
    );
    if (ok != true) return;

    final c = _currentClosing.copyWith(clearClosedAt: true);
    await _closingRepo.upsert(c);
    final cfg = await _closingRepo.load();
    if (!mounted) return;
    setState(() => _closings = cfg);
  }

  Widget _summaryRow(String label, String value, Color color,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 16 : 13,
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _effectiveItems;
    final closing = _currentClosing;
    // leaf ベースで進捗カウント（親に子があれば親自身はカウント外）
    // 動的リンク（銀行/クレカ）の場合は登録口座から展開された子要素が対象。
    final leafIds = _effectiveLeafIds;
    final checkedCount =
        leafIds.where((id) => closing.isChecked(id)).length;
    final total = leafIds.length;
    final progress = total == 0 ? 0.0 : checkedCount / total;
    final allChecked = total > 0 && checkedCount == total;
    final isClosed = closing.isClosed;

    final monthTxns = _monthTxns;
    final income = monthTxns
        .where((t) => t.type == TransactionType.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = monthTxns
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _monthHeader(),
        const SizedBox(height: 12),
        if (isClosed) _closedBanner(closing),
        if (isClosed) const SizedBox(height: 12),
        _summaryCard(income, expense),
        const SizedBox(height: 12),
        _pendingSettlementCard(),
        const SizedBox(height: 12),
        _progressCard(checkedCount, total, progress, isClosed),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _emptyChecklist()
        else
          ...items.map((item) => _parentBlock(item, closing, isClosed)),
        const SizedBox(height: 16),
        if (!isClosed)
          FilledButton.icon(
            onPressed: allChecked ? _close : null,
            icon: const Icon(Icons.lock),
            label: Text(allChecked
                ? '${_focused.year}年${_focused.month}月を締める'
                : '全項目チェック後に締められます'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  allChecked ? const Color(0xFF1A237E) : null,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _reopen,
            icon: const Icon(Icons.lock_open, color: Color(0xFFEA580C)),
            label: const Text('締めを解除して再編集',
                style: TextStyle(color: Color(0xFFEA580C))),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFFEA580C)),
            ),
          ),
      ],
    );
  }

  Widget _monthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left, color: Color(0xFF1A237E)),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${_focused.year}年${_focused.month}月の締め',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
              ),
            ),
          ),
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right, color: Color(0xFF1A237E)),
          ),
        ],
      ),
    );
  }

  Widget _closedBanner(MonthClosing closing) {
    final closedAt = closing.closedAt!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF16A34A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('締め済み',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534))),
                Text(
                  '${closedAt.year}/${closedAt.month}/${closedAt.day} ${closedAt.hour.toString().padLeft(2, '0')}:${closedAt.minute.toString().padLeft(2, '0')} に記録',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF166534)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 入金締め処理カード。
  /// 「見込み売上」フラグの立った収入が残っている時に表示し、
  /// タップで PendingSettlementScreen に遷移する。
  Widget _pendingSettlementCard() {
    final pending = _transactions
        .where((t) =>
            t.type == TransactionType.income && t.isPending)
        .toList();
    final pendingTotal =
        pending.fold<int>(0, (s, t) => s + t.amount);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const PendingSettlementScreen()),
        );
        // 戻ってきたら再読み込み
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pending.isEmpty
              ? Colors.white
              : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: pending.isEmpty
                  ? const Color(0xFFE5E7EB)
                  : const Color(0xFFFCD34D)),
        ),
        child: Row(
          children: [
            Icon(
                pending.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.hourglass_top,
                size: 18,
                color: pending.isEmpty
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFD97706)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('入金締め処理',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  Text(
                      pending.isEmpty
                          ? '見込み売上はありません'
                          : '${pending.length} 件 / ${formatYen(pendingTotal)} を確定に切り替え',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(int income, int expense) {
    final net = income - expense;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _block(
                '収入', formatYen(income, withSign: true),
                const Color(0xFF16A34A)),
          ),
          Container(
              width: 1, height: 36, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: _block(
                '支出', formatYen(-expense, withSign: true),
                const Color(0xFFDC2626)),
          ),
          Container(
              width: 1, height: 36, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: _block(
                '差引', formatYen(net, withSign: true),
                net >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                bold: true),
          ),
        ],
      ),
    );
  }

  Widget _block(String label, String value, Color color,
      {bool bold = false}) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 15 : 12,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace')),
      ],
    );
  }

  Widget _progressCard(int checked, int total, double progress, bool isClosed) {
    return Container(
      padding: const EdgeInsets.all(12),
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
              const Icon(Icons.checklist,
                  size: 16, color: Color(0xFF1A237E)),
              const SizedBox(width: 6),
              const Text('チェックリスト進捗',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '$checked / $total',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFF3F4F6),
              valueColor: AlwaysStoppedAnimation<Color>(
                isClosed
                    ? const Color(0xFF16A34A)
                    : (progress >= 1.0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF1A237E)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 親項目のブロック。子があれば子を子行で並べ、親自身はヘッダー（チェック対象外）。
  /// 子がなければ親自体がチェック対象。
  Widget _parentBlock(
      ChecklistItem item, MonthClosing closing, bool isClosed) {
    if (!item.hasChildren) {
      // リーフ親（=従来通り単一のチェック行）
      return _checkRow(
        id: item.id,
        name: item.name,
        url: item.url,
        memo: item.memo,
        closing: closing,
        isClosed: isClosed,
        indent: false,
      );
    }

    // 親（複合）→ ヘッダー + 子チェック行
    final childIds = item.children.map((c) => c.id).toList();
    final checkedChildren =
        childIds.where((id) => closing.isChecked(id)).length;
    final allChildChecked = checkedChildren == childIds.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: allChildChecked
              ? const Color(0xFF16A34A)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        children: [
          // 親ヘッダー
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Icon(
                  allChildChecked
                      ? Icons.check_circle
                      : Icons.folder_outlined,
                  size: 20,
                  color: allChildChecked
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF1A237E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827))),
                      if (item.memo != null)
                        Text(item.memo!,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                Text(
                  '$checkedChildren / ${childIds.length}',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: allChildChecked
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF6B7280),
                      fontWeight: FontWeight.w600),
                ),
                if (item.url != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.open_in_new,
                        size: 18, color: Color(0xFF3B82F6)),
                    tooltip: '開く',
                    onPressed: () => _openUrl(item.url!),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 子チェック行
          ...item.children.map((c) => _checkRow(
                id: c.id,
                name: c.name,
                url: c.url,
                memo: c.memo,
                closing: closing,
                isClosed: isClosed,
                indent: true,
              )),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 単一チェック行（リーフ親 or 子）。
  Widget _checkRow({
    required String id,
    required String name,
    required String? url,
    required String? memo,
    required MonthClosing closing,
    required bool isClosed,
    required bool indent,
  }) {
    final checked = closing.isChecked(id);
    if (indent) {
      // 子行（親カードの内側 / 枠なし）
      return InkWell(
        onTap: isClosed ? null : () => _toggleCheck(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 8, 6),
          child: Row(
            children: [
              Icon(
                checked
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: checked
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFD1D5DB),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: checked
                                ? const Color(0xFF6B7280)
                                : const Color(0xFF111827),
                            decoration: checked
                                ? TextDecoration.lineThrough
                                : null)),
                    if (memo != null)
                      Text(memo,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              if (url != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_new,
                      size: 16, color: Color(0xFF3B82F6)),
                  tooltip: '開く',
                  onPressed: () => _openUrl(url),
                ),
            ],
          ),
        ),
      );
    }

    // リーフ親（=従来の単独カード行）
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: checked
              ? const Color(0xFF16A34A)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isClosed ? null : () => _toggleCheck(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                checked ? Icons.check_circle : Icons.radio_button_unchecked,
                color: checked
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFD1D5DB),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: checked
                                ? const Color(0xFF6B7280)
                                : const Color(0xFF111827),
                            decoration: checked
                                ? TextDecoration.lineThrough
                                : null)),
                    if (memo != null) ...[
                      const SizedBox(height: 2),
                      Text(memo,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF))),
                    ],
                  ],
                ),
              ),
              if (url != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_new,
                      size: 18, color: Color(0xFF3B82F6)),
                  tooltip: '開く',
                  onPressed: () => _openUrl(url),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyChecklist() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          children: [
            Icon(Icons.checklist_outlined,
                size: 36, color: Color(0xFFD97706)),
            SizedBox(height: 8),
            Text('チェックリストが未登録',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E))),
            SizedBox(height: 4),
            Text('設定 → 月末締めチェックリスト で項目を登録してください',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 11, color: Color(0xFF92400E))),
          ],
        ),
      );
}
