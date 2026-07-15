import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/app_mode.dart';
import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/modal_input.dart';
import '../widgets/centered_body.dart';
import 'account_detail_screen.dart';
import 'expense_input_screen.dart';
import 'income_input_screen.dart';
import 'receipt_viewer_screen.dart';
import 'transfer_input_screen.dart';

/// 取引の詳細画面（フル画面）。
/// 明細をタップ → ここで内容を確認 → 「編集」「削除」を選べる。
/// 編集保存 or 削除したら Navigator.pop(context, true) を返し、一覧側で再読込する。
class TransactionDetailScreen extends StatefulWidget {
  final core.Transaction transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _busy = false;

  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];

  // 画面内で領収書の保管状態を更新できるよう、可変で保持する。
  late core.Transaction _cur = widget.transaction;
  core.Transaction get _t => _cur;

  // 登録済み銀行口座（起動時に読み込み）。銀行取引なら通帳スタイルの
  // 「銀行明細」レイアウトに切り替えるための突合に使う。
  List<core.RegisteredBankAccount> _banks = const [];
  bool _banksLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final cfg = await SettingsRepository.instance.loadPayments();
      if (!mounted) return;
      setState(() {
        _banks = cfg.bankAccounts;
        _banksLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _banksLoaded = true);
    }
  }

  /// 名前が「登録済みの銀行口座」に一致すればその口座を返す（現金/電子は除外）。
  core.RegisteredBankAccount? _bankByName(String? n) {
    if (n == null || n.trim().isEmpty) return null;
    for (final b in _banks) {
      if (b.accountType == core.AccountType.bank && b.name == n) return b;
    }
    return null;
  }

  /// この取引が「開くべき通帳」の銀行口座。null＝銀行明細でない（汎用画面）。
  /// 振替は from を優先（無ければ to）で通帳を開く。
  core.RegisteredBankAccount? get _bankAccount {
    final t = _t;
    if (t.type == core.TransactionType.transfer) {
      return _bankByName(t.transferFromAccount) ??
          _bankByName(t.transferToAccount);
    }
    return _bankByName(t.paymentMethod);
  }

  /// 種別バッジの文言（入金/出金/振替）。手数料も「出金」に含める。
  String get _typeLabel {
    switch (_t.type) {
      case core.TransactionType.income:
        return '入金';
      case core.TransactionType.transfer:
        return '振替';
      case core.TransactionType.expense:
        return '出金';
    }
  }

  /// 口座名（登録があれば下4桁を併記）。
  String _acctLabel(String? name) {
    final nm = (name ?? '').trim();
    if (nm.isEmpty) return '—';
    final b = _bankByName(nm);
    final l4 = b?.last4;
    return (l4 != null && l4.trim().isNotEmpty) ? '$nm（••••$l4）' : nm;
  }

  /// 紙のレシートで保管済み（現物を税理士へ）フラグの切替。
  /// receiptSaved（対応済みチェック）＝紙でもドライブでも共通、種類は receiptType に記録。
  Future<void> _setPaperKept(bool v) async {
    // 編集/削除ボタンを無効化(_busy)しない＝チェック切替で削除ボタンが点滅しない。
    final updated =
        _cur.copyWith(receiptSaved: v, receiptType: v ? 'paper' : null);
    setState(() => _cur = updated); // まず即反映
    try {
      await TransactionRepository.instance.update(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存に失敗しました: $e')));
      }
    }
  }

  /// 明細/領収書のURLをあとから貼る（携帯の利用明細ページ・Driveのリンク等）。
  /// 貼れたら receiptSaved（対応済みチェック）も自動でON＝紙フラグと同じ扱いにする。
  Future<void> _attachReceiptUrl() async {
    final ctrl = TextEditingController(text: _cur.receiptUrl ?? '');
    final word = _cur.type == core.TransactionType.income ? '請求書' : '領収書';
    final url = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('$wordのURLを貼る'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://…（利用明細ページ・Drive のリンク等）',
          ),
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: const Text('貼る'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || url.isEmpty) return;
    // URLが付いた＝証憑あり。チェックもONにする（紙フラグと同じ「対応済み」）。
    final updated =
        _cur.copyWith(receiptUrl: url, receiptSaved: true, receiptType: 'drive');
    setState(() => _cur = updated);
    try {
      await TransactionRepository.instance.update(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
      }
    }
  }

  Color get _accent {
    switch (_t.type) {
      case core.TransactionType.income:
        return const Color(0xFF059669);
      case core.TransactionType.transfer:
        return const Color(0xFF6B7280);
      case core.TransactionType.expense:
        return const Color(0xFFDC2626);
    }
  }

  String get _signedAmount {
    final y = formatYen(_t.amount);
    switch (_t.type) {
      case core.TransactionType.income:
        return '+$y';
      case core.TransactionType.transfer:
        return y;
      case core.TransactionType.expense:
        return '-$y';
    }
  }

  Future<void> _edit() async {
    bool? changed;
    if (_t.type == core.TransactionType.transfer) {
      // 振替は専用エディタで編集（汎用の支出エディタは振替を扱えない）。
      changed = await showTransferInputModal(context, editing: _t);
    } else if (_t.type == core.TransactionType.expense) {
      changed =
          await showInputSheet<bool>(context, ExpenseInputScreen(editing: _t));
    } else {
      // 収入
      changed =
          await showInputSheet<bool>(context, IncomeInputScreen(editing: _t));
    }
    if (changed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('この明細を削除しますか？'),
        content: Text(
            '「${_t.description.isEmpty ? _t.category.major : _t.description}」'
            ' / $_signedAmount\nこの操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await TransactionRepository.instance.delete(_t.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 口座一覧の読み込み前は判定できないので、ちらつき防止でローディング表示。
    if (!_banksLoaded) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(title: const Text('明細')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // 登録銀行口座に紐づく取引は「銀行明細」専用レイアウト（通帳スタイル）。
    final bankAcc = _bankAccount;
    if (bankAcc != null) return _buildBankScaffold(bankAcc);

    final t = _t;
    // 領収書・請求書の保管は「事業」だけ必要（税務のため）。
    // 個人モードでは領収書セクションを丸ごと出さない。
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;
    final hasReceipt = t.receiptUrl != null && t.receiptUrl!.trim().isNotEmpty;
    // 立替精算：金額(amount)は満額のまま、実質負担 = amount - 立替回収額。
    final reimbursed = t.reimbursed ?? 0;
    final hasReimbursed =
        t.type == core.TransactionType.expense && reimbursed > 0;
    // 制作原価(外注費/売上原価)や売上(収入)は「請求書」、それ以外は「領収書」と表記。
    final isInvoice = t.type == core.TransactionType.income ||
        ['外注費', '売上原価', '制作原価'].any((k) => t.category.major.contains(k));
    final receiptWord = isInvoice ? '請求書' : '領収書';
    // 表示用に先頭の自動番号（"4." など）を取り除く。
    final majorBare =
        t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
    final cat = t.category.sub.isNotEmpty
        ? '$majorBare › ${t.category.sub}'
        : majorBare;
    final wd = _wd[(t.date.weekday - 1) % 7];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('明細')),
      // Web/PC で横いっぱいに広がりすぎないよう中央寄せ＋最大幅。スマホは全幅。
      body: CenteredBody(
        maxWidth: 560,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // 金額カード
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Text(
                  t.description.isEmpty ? cat : t.description,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  _signedAmount,
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: _accent),
                ),
                if (hasReimbursed) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F6EF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.south_east,
                            size: 15, color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Text(
                          '実質のあなたの負担　${formatYen(t.effectiveAmount)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 明細項目
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                _row('日付',
                    '${t.date.year}/${t.date.month}/${t.date.day}（$wd）'),
                _div(),
                _row('カテゴリ', cat),
                _div(),
                _row('支払方法',
                    t.paymentMethod.isEmpty ? '—' : t.paymentMethod),
                if (t.store != null && t.store!.trim().isNotEmpty) ...[
                  _div(),
                  _row('店舗', t.store!.trim()),
                ],
                if (t.memo != null && t.memo!.trim().isNotEmpty) ...[
                  _div(),
                  _row('メモ', t.memo!.trim()),
                ],
              ],
            ),
          ),
          // 立替精算の内訳（実質いくら自分が負担したか）。
          if (hasReimbursed) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB7E3CE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(
                      children: const [
                        Icon(Icons.volunteer_activism,
                            size: 18, color: Color(0xFF059669)),
                        SizedBox(width: 8),
                        Text('立替精算',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151))),
                      ],
                    ),
                  ),
                  _splitRow('支払った合計', formatYen(t.amount), null),
                  _splitRow('立替（あとで戻る分）',
                      '−${formatYen(reimbursed)}', const Color(0xFF6B7280)),
                  Container(
                    color: const Color(0xFFE7F6EF),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Text('実質の負担',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF059669))),
                        const Spacer(),
                        Text(formatYen(t.effectiveAmount),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 領収書/請求書の保管：ドライブ保存なら閲覧ボタン、
          // 紙で保管する分（店頭レシート・ベンチャーサポート等）は「紙で保管済み」トグル。
          // ※事業モードのみ表示（個人は税務上の証憑保管が不要なため出さない）。
          if (isBusiness) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Row(
                      children: [
                        Text(receiptWord,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151))),
                        const Spacer(),
                        Text(
                          hasReceipt
                              ? '📄 ドライブに保管'
                              : (t.receiptSaved ? '🧾 紙で保管済み' : '未保管'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: (hasReceipt || t.receiptSaved)
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                  if (hasReceipt)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          // 所有者本人の権限(drive.readonly)でDriveから取得し表示。
                          final url = t.receiptUrl;
                          if (url == null || url.trim().isEmpty) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiptViewerScreen(
                                driveUrl: url.trim(),
                                title: receiptWord,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: Text('$receiptWordを見る'),
                      ),
                    )
                  else ...[
                    // 証憑がまだ無いとき：明細のURLを貼る／紙で保管、どちらでも対応済みにできる。
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _attachReceiptUrl,
                        icon: const Icon(Icons.link, size: 18),
                        label: Text('$receiptWordのURLを貼る'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                    CheckboxListTile(
                      value: t.receiptSaved,
                      onChanged:
                          _busy ? null : (v) => _setPaperKept(v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: const Text('紙のレシートで保管済み',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text('現物を保管して税理士へ渡す分（写真は不要）',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // 個人モード：税務用の保管トグルは不要だが、Amazon等でDriveに
          // 領収書が紐づいている場合は「見る」ボタンだけ出す（閲覧はできて良い）。
          if (!isBusiness && hasReceipt) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Row(
                      children: [
                        Text(receiptWord,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151))),
                        const Spacer(),
                        const Text('📄 ドライブに保管',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF059669))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url = t.receiptUrl;
                        if (url == null || url.trim().isEmpty) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReceiptViewerScreen(
                              driveUrl: url.trim(),
                              title: receiptWord,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text('$receiptWordを見る'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          // アクション（編集は支出/収入/振替すべてで可能）
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('編集'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_outline, size: 18),
                  label: const Text('削除'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  /// 銀行明細（通帳の1行）専用レイアウト。
  /// 口座＋入金/出金/振替と摘要・日付だけを見せ、経費の型
  /// （カテゴリ／領収書保管／立替）は隠す。残高の逆算はしない。
  Widget _buildBankScaffold(core.RegisteredBankAccount bankAcc) {
    final t = _t;
    final wd = _wd[(t.date.weekday - 1) % 7];
    final isTransfer = t.type == core.TransactionType.transfer;
    // 売上入金など「収入で請求書(Drive)が紐づく」ときだけ請求書リンクを残す。
    final hasReceipt = t.receiptUrl != null && t.receiptUrl!.trim().isNotEmpty;
    final showInvoice = t.type == core.TransactionType.income && hasReceipt;
    // 口座行の値：振替は「元 → 先」、それ以外は単一口座。
    final acctValue = isTransfer
        ? '${_acctLabel(t.transferFromAccount)} → ${_acctLabel(t.transferToAccount)}'
        : _acctLabel(t.paymentMethod);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('銀行明細')),
      body: CenteredBody(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // 金額カード（摘要＋符号つき金額＋種別バッジ）
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  Text(
                    t.description.isEmpty ? _typeLabel : t.description,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _signedAmount,
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: _accent),
                  ),
                  const SizedBox(height: 12),
                  // 種別バッジ（入金＝緑／出金＝赤／振替＝グレー）
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _typeLabel,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 明細項目（口座／日付／メモ）。カテゴリは出さない。
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  _row(isTransfer ? '口座（振替）' : '口座', acctValue),
                  _div(),
                  _row('日付',
                      '${t.date.year}/${t.date.month}/${t.date.day}（$wd）'),
                  if (t.memo != null && t.memo!.trim().isNotEmpty) ...[
                    _div(),
                    _row('メモ', t.memo!.trim()),
                  ],
                ],
              ),
            ),
            // 売上入金だけ：請求書（Drive）を見るリンクを残す。
            if (showInvoice) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(
                        children: [
                          Text('請求書',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF374151))),
                          Spacer(),
                          Text('📄 ドライブに保管',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF059669))),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final url = t.receiptUrl;
                          if (url == null || url.trim().isEmpty) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiptViewerScreen(
                                driveUrl: url.trim(),
                                title: '請求書',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text('請求書を見る'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 通帳を開く（この取引が属する口座の明細一覧へ）
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AccountDetailScreen(account: bankAcc),
                        ),
                      );
                      // 通帳側で編集/削除された可能性があるので一覧を再読込させる。
                      if (changed == true && mounted) {
                        Navigator.pop(context, true);
                      }
                    },
              icon: const Icon(Icons.account_balance, size: 18),
              label: Text('${bankAcc.name} の通帳を開く'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 12),
            // 編集 / 削除（汎用画面と同じ挙動。振替は専用エディタ）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('編集'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.delete_outline, size: 18),
                    label: const Text('削除'),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _div() => const Divider(height: 1, color: Color(0xFFEEF0F3));

  /// 立替精算の内訳の1行（ラベル＋金額）。
  Widget _splitRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF6B7280))),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? const Color(0xFF111827))),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
